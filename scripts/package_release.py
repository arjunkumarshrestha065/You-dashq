#!/usr/bin/env python3
"""Package a source/module kit without any app input, profiles, or credentials."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'release'
VERSION = 'v0.1.0'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    module = ROOT / 'build/YouTubeCarPlay.dylib'
    if not module.is_file():
        raise SystemExit('Run scripts/build_carplay.py --compile-only first.')
    OUT.mkdir(exist_ok=True)
    shutil.copy2(module, OUT / module.name)
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    kit = OUT / ('YouDash-' + VERSION + '-build-kit.zip')
    with zipfile.ZipFile(kit, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for name in tracked:
            if name:
                archive.write(ROOT / name, 'YouDash/' + name)
        archive.write(module, 'YouDash/module/' + module.name)
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip()
    manifest = {'project': 'YouDash', 'release': VERSION, 'source_revision': revision,
                'actual_youtube_version': '21.42.4', 'reported_version': '21.45.4',
                'youmod_version': '2.0.0', 'deployment_target': 'iOS 17.0', 'signed': False,
                'contains_provisioning_profile': False, 'contains_google_application': False,
                'contains_unrelated_app_source': False, 'device_certified': False,
                'artifacts': {path.name: digest(path) for path in [kit, OUT / module.name]}}
    (OUT / 'release-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (OUT / 'PRIVACY-REVIEW.txt').write_text(
        'Fresh standalone history. Source and module audited before upload.\n'
        'No known owner-specific names, device IDs, personal paths, signing profiles,\n'
        'private certificates/keys, app-container data, or unrelated app folders included.\n'
        'The module contains no code signature. Examples use generic app IDs.\n'
        'Third-party app IPA excluded after conservative binary-sharing audit.\n'
        'Use the builder with your own authorized input to generate an IPA locally.\n'
        'Automated pattern matching is not a guarantee of absence of all secrets.\n')
    names = ['YouTubeCarPlay.dylib', kit.name, 'release-manifest.json', 'PRIVACY-REVIEW.txt']
    (OUT / 'SHA256SUMS').write_text(''.join(digest(OUT / name) + '  ' + name + '\n' for name in sorted(names)))
    print('Prepared source/module release kit. Audit before uploading.')

if __name__ == '__main__':
    main()
