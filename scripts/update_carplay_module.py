#!/usr/bin/env python3
"""Fast device iteration: replace only our dylib in the already packaged app."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import shutil
import tempfile
import build_carplay as build

from build_carplay import ROOT, BUNDLE_ID, build_dylib, read_profile, signing_identity, signing_entitlements, remove_optional_tweaks, run


def main():
    global BUNDLE_ID
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    version = parser.add_mutually_exclusive_group()
    version.add_argument("--reported-version", help="Reversible bundle-version compatibility override")
    version.add_argument("--restore-reported-version", action="store_true")
    parser.add_argument("--reuse-module", action="store_true", help="Only re-sign metadata; retain the current compiled CarPlay module")
    args = parser.parse_args()
    if args.reported_version and not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", args.reported_version):
        parser.error("--reported-version must be a numeric app version")
    app = ROOT / "dist/YouTube.app"
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if not (app / "Frameworks/YouTubeCarPlay.dylib").is_file():
        raise ValueError("Refusing to modify an app without the CarPlay module")
    BUNDLE_ID = info["CFBundleIdentifier"]
    build.BUNDLE_ID = BUNDLE_ID
    profile = read_profile(app / "embedded.mobileprovision")
    run("xcrun", "devicectl", "device", "info", "details", "--device", args.device,
        "--json-output", ROOT / ".local/update-device.json", capture=True)
    device = json.loads((ROOT / ".local/update-device.json").read_text())["result"]
    udid = device.get("properties", {}).get("hardware", {}).get("udid") or device.get("hardwareProperties", {}).get("udid")
    if udid not in profile.get("ProvisionedDevices", []):
        raise ValueError("Device is not registered in the profile")
    identity = signing_identity(profile)
    executable = app / info["CFBundleExecutable"]
    native_binary, removed = remove_optional_tweaks(executable.read_bytes())
    if removed:
        executable.write_bytes(native_binary)
        print("Disabled optional playback/request patches:", ", ".join(removed))
    installed_dylib = app / "Frameworks/YouTubeCarPlay.dylib"
    if args.reuse_module:
        if not installed_dylib.is_file():
            raise ValueError("No existing CarPlay module to reuse")
    else:
        dylib = ROOT / "build/YouTubeCarPlay.dylib"
        build_dylib(dylib)
        shutil.copy2(dylib, installed_dylib)
        run("codesign", "--force", "--sign", identity, "--timestamp=none", installed_dylib)
    if args.reported_version:
        info.setdefault("YCPActualYouTubeVersion", info["CFBundleShortVersionString"])
        info.setdefault("YCPActualYouTubeBuild", info["CFBundleVersion"])
        info["CFBundleShortVersionString"] = args.reported_version
        info["CFBundleVersion"] = args.reported_version
        print("Version compatibility override:", info["YCPActualYouTubeVersion"], "reports", args.reported_version)
    elif args.restore_reported_version:
        if "YCPActualYouTubeVersion" in info:
            info["CFBundleShortVersionString"] = info.pop("YCPActualYouTubeVersion")
            info["CFBundleVersion"] = info.pop("YCPActualYouTubeBuild")
    (app / "Info.plist").write_bytes(plistlib.dumps(info))
    with tempfile.TemporaryDirectory() as temp:
        entitlements = Path(temp) / "entitlements.plist"
        entitlements.write_bytes(plistlib.dumps(signing_entitlements(profile)))
        run("codesign", "--force", "--sign", identity, "--timestamp=none", "--entitlements", entitlements, app)
    run("codesign", "--verify", "--deep", "--strict", app)
    run("xcrun", "devicectl", "device", "install", "app", "--device", args.device, app)
    run("xcrun", "devicectl", "device", "process", "launch", "--device", args.device, BUNDLE_ID)
    print("Updated device app. Run build_carplay.py to refresh the distributable IPA.")


if __name__ == "__main__":
    main()
