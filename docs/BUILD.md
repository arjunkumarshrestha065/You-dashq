# Build YouDash for CarPlay

## Prerequisites

- macOS with Xcode selected (`xcode-select -p`), an iPhoneOS SDK, and command-line tools.
- Python 3.9 or later. The code targets iOS 17.0.
- A compatible, decrypted YouTube + YouMod IPA you are authorized to modify. The baseline is actual YouTube **21.42.4 + YouMod 2.0.0**. A plain App Store download is encrypted and the packager rejects it.
- For device installation: your own signing certificate/private key in Keychain and a provisioning profile that authorizes your exact bundle ID, registered device, and necessary CarPlay capabilities. Those assets are never supplied by this repository.

```sh
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements-build.txt
python3 scripts/build_carplay.py --compile-only
```

The last command produces `build/YouTubeCarPlay.dylib`. It compiles the module without changing or installing an app.

## Produce an unsigned IPA

```sh
python3 scripts/build_carplay.py   --ipa /path/to/YouMod.ipa   --unsigned   --bundle-id com.example.youtubecar   --reported-version 21.45.4
```

`com.example.youtubecar` is a placeholder. Use your own identifier when signing. Outputs are `dist/YouTube.app`, `dist/YouTubeCarPlay-21.42.4-unsigned.ipa`, and a hash/version manifest. The output name uses the **actual** version; the bundle reports the compatibility value. To use the unmodified input version instead, pass `--reported-version native`.

The unsigned path does not read your signing profiles or certificates. It strips embedded provisioning profiles and signatures from nested binaries and the app. It still contains Google's and the input provider's proprietary binaries; their rights remain separate from our source license.

## Sign and install with your own profile

First create an app ID/profile through your own authorized developer setup. Match the bundle ID to that profile. Import its certificate/private key into Keychain using your usual secure process; do not copy them into this repository.

```sh
xcrun devicectl list devices

python3 scripts/build_carplay.py   --ipa /path/to/YouMod.ipa   --profile /path/to/your.mobileprovision   --bundle-id com.example.youtubecar   --device YOUR_DEVICE_UDID
```

Use your own UDID locally. The script checks profile/device membership, compiles the module, injects it through cyan, signs nested code, verifies signatures, then installs and launches. It uses only the profile's permitted entitlements and does not copy foreign application groups. Missing CarPlay capabilities require an authorized profile; changing a plist or installing with a sideloader does not grant them.

## Update the module without repackaging the input

After a signed package has been created in `dist/YouTube.app`:

```sh
python3 scripts/update_carplay_module.py --device YOUR_DEVICE_UDID
```

Metadata-only version changes can reuse the module:

```sh
python3 scripts/update_carplay_module.py   --device YOUR_DEVICE_UDID --reported-version 21.45.4 --reuse-module

python3 scripts/update_carplay_module.py   --device YOUR_DEVICE_UDID --restore-reported-version --reuse-module
```

Actual input version fields are retained under `YCPActualYouTubeVersion` and `YCPActualYouTubeBuild`. Do not use the displayed compatibility value to identify the underlying executable.

## What the packager changes

1. Verifies a decrypted arm64 main executable.
2. Preserves native phone scene entries and adds CarPlay template/window routes.
3. Removes unselected optional weak tweak loads; retains YouMod, YouGroupSettings, and our integration.
4. Injects `YouTubeCarPlay.dylib`, changes app identity, enables audio background mode, and sets the reported-version compatibility fields.
5. Either removes all signatures/profiles for an unsigned package or signs using your own profile.

The `YouFixPlaybackIssues` TV-client patch is excluded from this working baseline. YouMod's ad-blocking behavior is retained. No alternative player is installed.

## Rebuilding YouMod itself

The compiled YouMod in the input IPA is reused. `vendor/YouMod/` is the attributed source snapshot for inspection and modification. Editing it does not change an existing dylib. To rebuild it, use Theos with the upstream headers/dependencies and the original build instructions in `vendor/YouMod/README.md`; then provide an IPA containing your newly built YouMod. This repository's module build does not pretend to rebuild Google or every third-party tweak from source.

## Common build problems

- **Encrypted input:** supply a compatible decrypted input you are authorized to use.
- **cyan unavailable:** activate `.venv` and install `requirements-build.txt`. The script runs cyan with the current Python interpreter.
- **Profile/app ID mismatch:** use the exact ID authorized by your profile.
- **Device unavailable/locked:** reconnect and unlock the device before installation/launch.
- **App installs but no CarPlay window:** inspect your authorized capabilities and OS/head-unit support. See `COMPATIBILITY.md`.

## Optional maintainer checks

These are not required for an end user to install. The native harnesses require a booted iOS simulator:

```sh
python3 -m unittest discover -s tests -v
python3 tests/run_native_surface.py YOUR_SIMULATOR_UDID
python3 tests/run_watch_layout.py YOUR_SIMULATOR_UDID
```
