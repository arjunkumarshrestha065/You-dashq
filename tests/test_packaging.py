import copy
import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location("build_carplay", Path(__file__).resolve().parents[1] / "scripts/build_carplay.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


def dylib(name, kind=0x80000018):
    encoded = name.encode() + b"\0"
    size = (24 + len(encoded) + 7) & ~7
    return struct.pack("<IIIIII", kind, size, 24, 0, 0, 0) + encoded + bytes(size - 24 - len(encoded))


def binary(*entries):
    commands = b"".join(entries)
    header = struct.pack("<IIIIIIII", 0xFEEDFACF, 0x100000C, 0, 2, len(entries), len(commands), 0, 0)
    return header + commands + b"unchanged executable content"


class PackagingTests(unittest.TestCase):
    def test_optional_removal_preserves_native_dependencies_and_file_offsets(self):
        native = dylib("/System/Library/Frameworks/UIKit.framework/UIKit", 0xC)
        youmod = dylib("@rpath/YouMod.dylib")
        swift = dylib("@rpath/libswiftCompatibilitySpan.dylib")
        optional = dylib("@rpath/VolumeBoostYT.dylib")
        source = binary(native, optional, youmod, swift)
        patched, removed = build.remove_optional_tweaks(source)
        self.assertEqual(removed, ["@rpath/VolumeBoostYT.dylib"])
        self.assertEqual([entry for _, entry in build.commands(patched)], [native, youmod, swift])
        self.assertEqual(len(source), len(patched))
        offset = 32 + struct.unpack_from("<I", source, 20)[0]
        self.assertEqual(source[offset:], patched[offset:])
        self.assertEqual(build.remove_optional_tweaks(patched), (patched, []))

    def test_rejects_corrupt_command_tables(self):
        source = bytearray(binary(dylib("@rpath/YouMod.dylib")))
        struct.pack_into("<I", source, 36, 0)
        with self.assertRaises(ValueError):
            build.remove_optional_tweaks(source)
        with self.assertRaises(ValueError):
            build.commands(b"not a macho")

    def test_rejects_encrypted_input(self):
        encrypted = struct.pack("<IIIIII", 0x2C, 24, 16384, 100, 1, 0)
        with self.assertRaisesRegex(ValueError, "encrypted"):
            build.assert_decrypted(binary(encrypted))
        decrypted = struct.pack("<IIIIII", 0x2C, 24, 16384, 100, 0, 0)
        build.assert_decrypted(binary(decrypted))

    def test_native_phone_lifecycle_and_other_configurations_survive(self):
        phone = [{"UISceneConfigurationName": "Default Configuration", "UISceneDelegateClassName": "YTSceneDelegate", "UISceneClassName": "UIWindowScene"}]
        info = {"UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False,
                "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": copy.deepcopy(phone), "another-role": [{"custom": True}]}}, "UIBackgroundModes": ["audio"]}
        build.patch_scene_manifest(info)
        configurations = info["UIApplicationSceneManifest"]["UISceneConfigurations"]
        self.assertEqual(configurations["UIWindowSceneSessionRoleApplication"], phone)
        self.assertEqual(configurations["another-role"], [{"custom": True}])
        self.assertEqual(configurations["UIWindowSceneSessionRoleCarPlay"][0]["UISceneDelegateClassName"], "YCPWindowDelegate")
        self.assertEqual(configurations["CPTemplateApplicationSceneSessionRoleApplication"][0]["UISceneDelegateClassName"], "YCPTemplateDelegate")

    def test_no_foreign_entitlements_copied(self):
        app_id = "TEAM." + build.BUNDLE_ID
        result = build.signing_entitlements({"Entitlements": {"application-identifier": app_id,
            "com.apple.developer.team-identifier": "TEAM", "com.apple.developer.carplay-video": True,
            "keychain-access-groups": ["TEAM.*"], "com.apple.security.application-groups": ["foreign.group"]}})
        self.assertEqual(result["keychain-access-groups"], [app_id])
        self.assertNotIn("com.apple.security.application-groups", result)
        self.assertTrue(result["com.apple.developer.carplay-video"])


if __name__ == "__main__":
    unittest.main()
