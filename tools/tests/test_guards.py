import copy
import datetime as dt
import importlib.util
import json
import plistlib
import subprocess
import sys
import unittest
import tempfile
import zlib
from pathlib import Path
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
from profile import permitted_certificate, validate_entitlements, validate_profile
import release

spec = importlib.util.spec_from_file_location("simulators", TOOLS / "select-simulators.py")
simulators = importlib.util.module_from_spec(spec)
spec.loader.exec_module(simulators)


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.profile = {
            "TeamIdentifier": ["TESTTEAM01"],
            "ApplicationIdentifierPrefix": ["TESTTEAM01"],
            "Entitlements": {
                "application-identifier": "TESTTEAM01.com.errantactions.soccerposition",
                "com.apple.developer.team-identifier": "TESTTEAM01",
                "get-task-allow": False,
            },
            "ExpirationDate": dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=30),
            "Name": "Example distribution profile",
            "UUID": "12345678-1234-1234-1234-123456789012",
            "DeveloperCertificates": [b"test certificate"],
        }

    def test_valid_profile(self):
        result = validate_profile(self.profile, "TESTTEAM01", "com.errantactions.soccerposition")
        self.assertEqual(result["method"], "app-store-connect")
        self.assertFalse(result["manageAppVersionAndBuildNumber"])
        validate_entitlements({}, self.profile)

    def test_rejects_bad_profiles(self):
        changes = [
            {"TeamIdentifier": ["OTHERTEAM1"]},
            {"ExpirationDate": dt.datetime(2000, 1, 1)},
            {"ProvisionedDevices": []},
            {"ProvisionsAllDevices": True},
            {"DeveloperCertificates": []},
            {"UUID": "../../outside"},
        ]
        for change in changes:
            with self.subTest(change=list(change)):
                with self.assertRaises(ValueError):
                    validate_profile({**self.profile, **change}, "TESTTEAM01", "com.errantactions.soccerposition")

    def test_rejects_wrong_entitlements(self):
        for key, value in [
            ("application-identifier", "TESTTEAM01.*"),
            ("com.apple.developer.team-identifier", "OTHERTEAM1"),
            ("get-task-allow", True),
        ]:
            profile = copy.deepcopy(self.profile)
            profile["Entitlements"][key] = value
            with self.assertRaises(ValueError):
                validate_profile(profile, "TESTTEAM01", "com.errantactions.soccerposition")
        with self.assertRaises(ValueError):
            validate_entitlements({"aps-environment": "production"}, self.profile)

    def test_certificate_must_match_profile(self):
        self.assertFalse(permitted_certificate("0" * 40, self.profile))
        import hashlib
        self.assertTrue(permitted_certificate(hashlib.sha1(b"test certificate").hexdigest(), self.profile))


class SimulatorTests(unittest.TestCase):
    def test_two_distinct_devices(self):
        data = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-1": [
            {"name": "iPhone Duo", "isAvailable": True, "udid": "duo"},
            {"name": "iPhone 18", "isAvailable": True, "udid": "compact"},
        ]}}
        self.assertEqual(simulators.select_devices(data), ["compact", "duo"])
        data["devices"]["com.apple.CoreSimulator.SimRuntime.iOS-27-1"].pop()
        with self.assertRaises(ValueError):
            simulators.select_devices(data)


class ReleaseBoundaryTests(unittest.TestCase):
    def test_refuses_local_signing(self):
        with patch.dict("os.environ", {"GITHUB_ACTIONS": ""}):
            with self.assertRaisesRegex(ValueError, "protected macOS"):
                release.release()

    def test_cleanup_rejects_paths_outside_runner_temp(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "coachai-signing-path").write_text(str(root.parent))
            with patch.dict("os.environ", {"RUNNER_TEMP": str(root)}):
                with self.assertRaisesRegex(ValueError, "unsafe cleanup"):
                    release.cleanup_remaining()

    def test_cleanup_removes_only_owned_temp_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            work = root / "coachai-signing-test"
            work.mkdir()
            (work / "key.p8").write_text("test-only")
            neighbor = root / "leave-this-alone"
            neighbor.write_text("test-only")
            marker = root / "coachai-signing-path"
            marker.write_text(str(work))
            with patch.dict("os.environ", {"RUNNER_TEMP": str(root)}):
                release.cleanup_remaining()
            self.assertFalse(work.exists())
            self.assertFalse(marker.exists())
            self.assertTrue(neighbor.exists())


class ConfigurationTests(unittest.TestCase):
    def test_icon_is_1024_rgb_without_alpha(self):
        icon_spec = importlib.util.spec_from_file_location("assets", TOOLS / "generate-assets.py")
        assets = importlib.util.module_from_spec(icon_spec)
        icon_spec.loader.exec_module(assets)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            assets.generate(root)
            image = (root / "AppIcon.appiconset" / "AppIcon.png").read_bytes()
            self.assertEqual(image[:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(int.from_bytes(image[16:20], "big"), 1024)
            self.assertEqual(int.from_bytes(image[20:24], "big"), 1024)
            self.assertEqual(image[24:26], bytes([8, 2]))
            compressed_length = int.from_bytes(image[33:37], "big")
            self.assertEqual(len(zlib.decompress(image[41:41 + compressed_length])), 1024 * (1 + 1024 * 3))

    def test_privacy_and_entitlements_are_minimal(self):
        app = TOOLS.parent / "App"
        privacy = plistlib.loads((app / "PrivacyInfo.xcprivacy").read_bytes())
        self.assertFalse(privacy["NSPrivacyTracking"])
        self.assertEqual(privacy["NSPrivacyCollectedDataTypes"], [])
        self.assertEqual(privacy["NSPrivacyAccessedAPITypes"], [])
        self.assertEqual(plistlib.loads((app / "CoachAI.entitlements").read_bytes()), {})
        info = plistlib.loads((app / "Info.plist").read_bytes())
        self.assertFalse(any(key.endswith("UsageDescription") for key in info))

    def test_build_numbers_check_all_previous_uploads(self):
        script = """
            import { nextBuild } from './tools/asc.mjs';
            const result = [nextBuild([], '1'), nextBuild(['12','3','1.2.3'], '1'), nextBuild(['12'], '100')];
            let rejected = 0;
            for (const [versions, minimum] of [[['9999'],'1'], [[], '0'], [['bad'],'1']]) {
              try { nextBuild(versions, minimum); } catch { rejected++; }
            }
            console.log(JSON.stringify({result, rejected}));
        """
        output = subprocess.check_output(["node", "--input-type=module", "-e", script], cwd=TOOLS.parent, text=True)
        self.assertEqual(json.loads(output), {"result": ["1", "13", "100"], "rejected": 3})


if __name__ == "__main__":
    unittest.main()
