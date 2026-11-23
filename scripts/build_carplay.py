#!/usr/bin/env python3
"""Build a native CarPlay dylib and package/sign a supplied native YouTube IPA.

Requires Xcode and cyan (pip install from the pinned source in SOURCES.md).
Inputs stay outside Git. The original IPA and the retired experiment are untouched.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import sys
import struct
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "io.github.youtubecar.app"
KEEP_TWEAKS = {"YouMod.dylib", "YouGroupSettings.dylib", "YouTubeCarPlay.dylib"}
MACHO_MAGICS = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"}


def run(*arguments, capture=False):
    result = subprocess.run([str(arg) for arg in arguments], check=True,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None)
    return result.stdout if capture else None


def commands(data):
    """Read a thin arm64 Mach-O with bounds checks before any mutation."""
    if len(data) < 32 or data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Expected a thin little-endian 64-bit Mach-O; thin the input first")
    count, size = struct.unpack_from("<II", data, 16)
    if 32 + size > len(data):
        raise ValueError("Mach-O load command table extends beyond file")
    offset = 32
    result = []
    for _ in range(count):
        if offset + 8 > 32 + size:
            raise ValueError("Truncated Mach-O command header")
        kind, length = struct.unpack_from("<II", data, offset)
        if length < 8 or length % 8 or offset + length > 32 + size:
            raise ValueError("Invalid Mach-O load command length")
        result.append((kind, data[offset:offset + length]))
        offset += length
    if offset != 32 + size:
        raise ValueError("Inconsistent Mach-O command table")
    return result


def dylib_name(command):
    if len(command) < 24:
        raise ValueError("Truncated dylib command")
    offset = struct.unpack_from("<I", command, 8)[0]
    if offset < 24 or offset >= len(command):
        raise ValueError("Invalid dylib name offset")
    return command[offset:].split(b"\0", 1)[0].decode("utf-8")


def remove_optional_tweaks(data):
    """Remove only appended weak tweak loads; preserve segment/file offsets.

    The supplied release appends weak tweak loads with no imported symbols.
    Native strong dependencies and Swift compatibility libraries are preserved.
    """
    entries = commands(data)
    kept, removed = [], []
    for kind, command in entries:
        name = dylib_name(command) if kind == 0x80000018 else ""
        basename = Path(name).name
        if name.startswith("@rpath/") and basename.endswith(".dylib") and not basename.startswith("libswift") and basename not in KEEP_TWEAKS:
            removed.append(name)
        else:
            kept.append(command)
    packed = b"".join(kept)
    old_size = struct.unpack_from("<I", data, 20)[0]
    output = bytearray(data)
    struct.pack_into("<II", output, 16, len(kept), len(packed))
    output[32:32 + old_size] = packed + bytes(old_size - len(packed))
    return bytes(output), removed


def assert_decrypted(data):
    for kind, command in commands(data):
        if kind in (0x21, 0x2C) and struct.unpack_from("<I", command, 16)[0] != 0:
            raise ValueError("The YouTube executable is encrypted; a decrypted input is required")


def patch_scene_manifest(info):
    """Preserve Google's exact phone configuration and add both proven car roles."""
    manifest = info.setdefault("UIApplicationSceneManifest", {})
    manifest["UIApplicationSupportsMultipleScenes"] = True
    configurations = manifest.setdefault("UISceneConfigurations", {})
    if not configurations.get("UIWindowSceneSessionRoleApplication"):
        raise ValueError("No native phone scene configuration in this YouTube build")
    configurations["CPTemplateApplicationSceneSessionRoleApplication"] = [{
        "UISceneConfigurationName": "YouTube CarPlay", "UISceneClassName": "CPTemplateApplicationScene",
        "UISceneDelegateClassName": "YCPTemplateDelegate"}]
    for role in ("UIWindowSceneSessionRoleCarPlay", "UIWindowSceneSessionRoleExternalDisplayNonInteractive"):
        configurations[role] = [{"UISceneConfigurationName": "YouTube CarPlay Window",
                                  "UISceneClassName": "UIWindowScene", "UISceneDelegateClassName": "YCPWindowDelegate"}]
    info["UIApplicationSupportsIndirectInputEvents"] = True
    info["UIFileSharingEnabled"] = True
    info["LSSupportsOpeningDocumentsInPlace"] = True
    info["UISupportedInterfaceOrientations"] = ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
    modes = info.setdefault("UIBackgroundModes", [])
    if "audio" not in modes:
        modes.append("audio")
    return info


def read_profile(path):
    return plistlib.loads(run("security", "cms", "-D", "-i", path, capture=True))


def find_profile(explicit=None):
    roots = [Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
             Path.home() / "Library/MobileDevice/Provisioning Profiles"]
    candidates = [Path(explicit)] if explicit else [p for root in roots for p in root.glob("*.mobileprovision")]
    matches = []
    for path in candidates:
        profile = read_profile(path)
        entitlements = profile["Entitlements"]
        if entitlements.get("application-identifier", "").endswith("." + BUNDLE_ID) and entitlements.get("com.apple.developer.carplay-video"):
            matches.append((path, profile))
    if not matches:
        raise ValueError("No authorized CarPlay video provisioning profile for " + BUNDLE_ID)
    path, profile = max(matches, key=lambda pair: pair[1]["ExpirationDate"])
    if profile["ExpirationDate"] < datetime.datetime.utcnow():
        raise ValueError("CarPlay provisioning profile has expired")
    return path, profile


def signing_entitlements(profile):
    authorized = profile["Entitlements"]
    application_id = authorized["application-identifier"]
    return {"application-identifier": application_id,
            "com.apple.developer.team-identifier": authorized["com.apple.developer.team-identifier"],
            "keychain-access-groups": [application_id],
            "get-task-allow": authorized.get("get-task-allow", False),
            **{key: authorized[key] for key in ("com.apple.developer.carplay-audio", "com.apple.developer.carplay-video") if key in authorized}}


def signing_identity(profile, explicit=None):
    identities = run("security", "find-identity", "-v", "-p", "codesigning", capture=True).decode()
    for certificate in profile["DeveloperCertificates"]:
        fingerprint = hashlib.sha1(certificate).hexdigest().upper()
        if fingerprint in identities and (not explicit or explicit == fingerprint or explicit in identities.split(fingerprint, 1)[1].split("\n", 1)[0]):
            return fingerprint
    raise ValueError("No local signing identity matches this profile's DeveloperCertificates")


def build_dylib(destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    sdk = run("xcrun", "--sdk", "iphoneos", "--show-sdk-path", capture=True).decode().strip()
    with tempfile.TemporaryDirectory(prefix="youmod-module-") as temp:
        objects = []
        for source in ("YCPNative", "YCPHooks", "YCPWatchLayout", "YCPResponsiveLayout", "YCPBrowseLayout", "YCPHeaderLayout"):
            obj = Path(temp) / (source + ".o")
            run("xcrun", "clang", "-target", "arm64-apple-ios17.0", "-isysroot", sdk,
                "-fobjc-arc", "-g0", "-ffile-prefix-map=" + str(ROOT) + "=.", "-fdebug-prefix-map=" + str(ROOT) + "=.", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter",
                "-c", ROOT / ("CarPlay/" + source + ".m"), "-o", obj)
            objects.append(obj)
        run("xcrun", "swiftc", "-emit-library", "-target", "arm64-apple-ios17.0", "-sdk", sdk,
            "-file-prefix-map", str(ROOT) + "=.", "-debug-prefix-map", str(ROOT) + "=.",
            "-module-name", "YouTubeCarPlay", ROOT / "CarPlay/YCPKeyboard.swift", *objects,
            "-framework", "UIKit", "-framework", "CarPlay", "-framework", "Foundation",
            "-Xlinker", "-install_name", "-Xlinker", "@rpath/YouTubeCarPlay.dylib", "-o", destination)
        run("codesign", "--remove-signature", destination)


def extract_ipa(source, directory):
    with zipfile.ZipFile(source) as archive:
        for entry in archive.infolist():
            if not (directory / entry.filename).resolve().is_relative_to(directory.resolve()):
                raise ValueError("Unsafe path in input archive")
        archive.extractall(directory)
    apps = list((directory / "Payload").glob("*.app"))
    if len(apps) != 1:
        raise ValueError("Expected exactly one app under Payload")
    return apps[0]


def main():
    global BUNDLE_ID
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path)
    parser.add_argument("--profile", type=Path)
    parser.add_argument("--identity")
    parser.add_argument("--cyan", help="Optional cyan executable; default: current Python -m cyan")
    parser.add_argument("--bundle-id", default=BUNDLE_ID, help="App ID authorized by your own provisioning profile")
    parser.add_argument("--unsigned", action="store_true", help="Package without certificates, profiles, or signing entitlements")
    parser.add_argument("--reported-version", default="21.45.4", help="Bundle-version compatibility value; use native to disable")
    parser.add_argument("--keep-extra-tweaks", action="store_true")
    parser.add_argument("--compile-only", action="store_true")
    parser.add_argument("--device", help="Confirmed physical iPhone identifier; installs and launches when supplied")
    args = parser.parse_args()
    BUNDLE_ID = args.bundle_id
    if args.unsigned and args.device:
        parser.error("Unsigned apps must be signed with your own profile before device installation")
    output = ROOT / "build"
    output.mkdir(exist_ok=True)
    dylib = output / "YouTubeCarPlay.dylib"
    build_dylib(dylib)
    if args.compile_only:
        print("Compiled", dylib)
        return
    if not args.ipa or not args.ipa.is_file():
        parser.error("--ipa must point to the supplied native YouTube IPA")
    profile_path, profile, identity = None, None, None
    if not args.unsigned:
        profile_path, profile = find_profile(args.profile)
        identity = signing_identity(profile, args.identity)
    if args.device:
        run("xcrun", "devicectl", "device", "info", "details", "--device", args.device,
            "--json-output", output / "device.json", capture=True)
        details = json.loads((output / "device.json").read_text())
        result = details["result"]
        udid = result.get("properties", {}).get("hardware", {}).get("udid") or result.get("hardwareProperties", {}).get("udid")
        if udid not in profile.get("ProvisionedDevices", []):
            raise ValueError("Selected iPhone is not registered in this provisioning profile")
    with tempfile.TemporaryDirectory(prefix="youtube-carplay-") as temp:
        temp = Path(temp)
        app = extract_ipa(args.ipa, temp / "original")
        info_path = app / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        executable = app / info["CFBundleExecutable"]
        original_id = info["CFBundleIdentifier"]
        original_version = info["CFBundleShortVersionString"]
        data = executable.read_bytes()
        if data[:4] != b"\xcf\xfa\xed\xfe":
            run("xcrun", "lipo", executable, "-thin", "arm64", "-output", temp / "thin")
            data = (temp / "thin").read_bytes()
        assert_decrypted(data)
        removed = []
        if not args.keep_extra_tweaks:
            data, removed = remove_optional_tweaks(data)
        executable.write_bytes(data)
        # Unloaded optional dylibs remain absent from the app, not just disabled.
        for dependency in removed:
            path = app / "Frameworks" / Path(dependency).name
            if path.is_file():
                path.unlink()
        patch_scene_manifest(info)
        info["CFBundleIdentifier"] = BUNDLE_ID
        info["CFBundleDisplayName"] = "YouDash"
        if args.reported_version != "native":
            info["YCPActualYouTubeVersion"] = original_version
            info["YCPActualYouTubeBuild"] = info["CFBundleVersion"]
            info["CFBundleShortVersionString"] = args.reported_version
            info["CFBundleVersion"] = args.reported_version
        # Invalid after changing Google's signing team. These are optional features.
        info.pop("BGTaskSchedulerPermittedIdentifiers", None)
        info["UIBackgroundModes"] = [mode for mode in info["UIBackgroundModes"] if mode == "audio"]
        info_path.write_bytes(plistlib.dumps(info))
        signed_app = temp / "signed/Payload/YouTube.app"
        cyan_command = [args.cyan] if args.cyan else [sys.executable, "-m", "cyan"]
        run(*cyan_command, "-i", app, "-o", signed_app, "-f", dylib, "-u", "-w", "-e")
        for directory in signed_app.rglob("_CodeSignature"):
            if directory.is_dir():
                shutil.rmtree(directory)
        for provision in signed_app.rglob("*.mobileprovision"):
            provision.unlink()
        if not args.unsigned:
            shutil.copy2(profile_path, signed_app / "embedded.mobileprovision")
            entitlements = signing_entitlements(profile)
            ent_path = temp / "entitlements.plist"
            ent_path.write_bytes(plistlib.dumps(entitlements))
        binary_paths = []
        for path in signed_app.rglob("*"):
            if path.is_file() and not path.is_symlink():
                with path.open("rb") as stream:
                    if stream.read(4) in MACHO_MAGICS and path != signed_app / info["CFBundleExecutable"]:
                        binary_paths.append(path)
        if args.unsigned:
            # Remove every input signature, not just the app's outer signature.
            # A distributable unsigned IPA must not contain someone's Team ID,
            # provisioning profile, signing certificate, or signed entitlements.
            for path in sorted(binary_paths, key=lambda p: len(p.parts), reverse=True):
                signature = subprocess.run(["codesign", "-d", str(path)], capture_output=True)
                if signature.returncode == 0:
                    run("codesign", "--remove-signature", path)
                elif b"not signed at all" not in signature.stderr:
                    raise RuntimeError("Could not inspect nested code signature: " + path.name)
            signature = subprocess.run(["codesign", "-d", str(signed_app)], capture_output=True)
            if signature.returncode == 0:
                run("codesign", "--remove-signature", signed_app)
            elif b"not signed at all" not in signature.stderr:
                raise RuntimeError("Could not inspect app signature")
        else:
            for path in sorted(binary_paths, key=lambda p: len(p.parts), reverse=True):
                run("codesign", "--force", "--sign", identity, "--timestamp=none", path)
            for framework in sorted(signed_app.rglob("*.framework"), key=lambda p: len(p.parts), reverse=True):
                run("codesign", "--force", "--sign", identity, "--timestamp=none", framework)
            run("codesign", "--force", "--sign", identity, "--timestamp=none", "--entitlements", ent_path, signed_app)
            run("codesign", "--verify", "--deep", "--strict", signed_app)
        signed_info = plistlib.loads((signed_app / "Info.plist").read_bytes())
        assert signed_info["CFBundleIdentifier"] == BUNDLE_ID
        dependencies = run("xcrun", "otool", "-L", signed_app / info["CFBundleExecutable"], capture=True).decode()
        assert "@rpath/YouTubeCarPlay.dylib" in dependencies, "CarPlay module was not injected"
        destination = ROOT / "dist"
        destination.mkdir(exist_ok=True)
        app_destination = destination / "YouTube.app"
        if app_destination.exists():
            shutil.rmtree(app_destination)
        shutil.copytree(signed_app, app_destination)
        ipa_destination = destination / ("YouTubeCarPlay-" + original_version + ("-unsigned" if args.unsigned else "") + ".ipa")
        run("ditto", "-c", "-k", "--keepParent", signed_app.parent, ipa_destination)
        metadata = {"bundle_id": BUNDLE_ID, "youtube_version": original_version, "input_bundle_id": original_id,
                    "input_sha256": hashlib.sha256(args.ipa.read_bytes()).hexdigest(),
                    "output_sha256": hashlib.sha256(ipa_destination.read_bytes()).hexdigest(),
                    "reported_version": signed_info["CFBundleShortVersionString"],
                    "removed_optional_tweaks": removed, "unsigned": args.unsigned,
                    "device_tested": False}
        (destination / "build-manifest.json").write_text(json.dumps(metadata, indent=2) + "\n")
        print("Packaged app:", app_destination, "\nIPA:", ipa_destination)
        if args.device:
            run("xcrun", "devicectl", "device", "install", "app", "--device", args.device, app_destination)
            run("xcrun", "devicectl", "device", "process", "launch", "--device", args.device, BUNDLE_ID)


if __name__ == "__main__":
    main()
