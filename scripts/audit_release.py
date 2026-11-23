#!/usr/bin/env python3
"""Audit source/artifacts for common credentials, personal paths and signing data.

This is a release gate, not a guarantee that arbitrary input contains no secrets.
Also review local owner-specific names/identifiers outside committed config.
"""
import argparse
import io
from pathlib import Path
import re
import struct
import sys
import zipfile

SKIP = {'.git', '.local', '.venv', 'venv', 'build', 'dist', 'release', '__pycache__'}
FORBIDDEN_SUFFIXES = {'.mobileprovision', '.provisionprofile', '.p12', '.pfx', '.pem', '.key', '.cer', '.ips', '.crash', '.log'}
RULES = {
    'private signing key': rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'GitHub credential': rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})',
    'AWS credential': rb'AKIA[0-9A-Z]{16}',
    'Slack credential': rb'xox[baprs]-[A-Za-z0-9-]{20,}',
    'device identifier': rb'\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\b',
    'personal filesystem path': rb'/(?:Users|home)/[A-Za-z0-9_.-]+/',
}
COMPILED = {label: re.compile(pattern) for label, pattern in RULES.items()}

def signed_macho(data):
    if len(data) < 32 or data[:4] != b'\xcf\xfa\xed\xfe':
        return False
    count, size = struct.unpack_from('<II', data, 16)
    if 32 + size > len(data):
        return False
    offset = 32
    for _ in range(count):
        if offset + 8 > 32 + size:
            return False
        kind, length = struct.unpack_from('<II', data, offset)
        if length < 8 or offset + length > 32 + size:
            return False
        if kind == 0x1D and length >= 16:
            if struct.unpack_from('<I', data, offset + 12)[0] > 0:
                return True
        offset += length
    return False

def check(name, data, artifact, failures):
    path = Path(name)
    if path.suffix.lower() in FORBIDDEN_SUFFIXES or path.name.startswith('.env'):
        failures.append((name, 'forbidden local/signing file'))
    if '_CodeSignature' in path.parts:
        failures.append((name, 'code-signature directory'))
    for label, pattern in COMPILED.items():
        if pattern.search(data):
            failures.append((name, label))
    if artifact and signed_macho(data):
        failures.append((name, 'Mach-O contains a code signature'))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--artifact', type=Path, action='append', default=[])
    args = parser.parse_args()
    failures = []
    count = 0
    for path in args.root.rglob('*'):
        if not path.is_file() or any(part in SKIP for part in path.relative_to(args.root).parts):
            continue
        check(str(path.relative_to(args.root)), path.read_bytes(), False, failures)
        count += 1
    for path in args.artifact:
        if not path.is_file():
            failures.append((path.name, 'artifact missing'))
            continue
        if zipfile.is_zipfile(path):
            with zipfile.ZipFile(path) as archive:
                for item in archive.infolist():
                    if not item.is_dir():
                        check(path.name + ':' + item.filename, archive.read(item), True, failures)
                        count += 1
        else:
            check(path.name, path.read_bytes(), True, failures)
            count += 1
    if failures:
        for name, reason in failures:
            print('REJECT:', name, '—', reason)
        print('Audit failed; matched values are intentionally not printed.')
        return 1
    print('Privacy/signing audit passed for', count, 'files. Manual owner-specific review is still required.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
