import copy
import datetime as dt
import importlib.util
import json
import os
import plistlib
import shutil
import subprocess
import sys
import unittest
import tempfile
import zlib
import zipfile
from pathlib import Path
from unittest.mock import Mock, patch

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
from profile import permitted_certificate, validate_entitlements, validate_profile
import release
import ios_tests as simulators


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
        self.assertEqual([device["udid"] for device in simulators.select_devices(data, "27.1")], ["compact", "duo"])
        data["devices"]["com.apple.CoreSimulator.SimRuntime.iOS-27-1"].pop()
        with self.assertRaises(ValueError):
            simulators.select_devices(data, "27.1")

    def test_selects_newest_compatible_runtime_for_each_device(self):
        data = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                {"name": "iPhone 18", "isAvailable": True, "udid": "old-compact"},
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-1": [
                {"name": "iPhone Duo", "isAvailable": True, "udid": "duo"},
            ],
        }}
        self.assertEqual([device["udid"] for device in simulators.select_devices(data, "27.1")], ["old-compact", "duo"])
        data["devices"]["com.apple.CoreSimulator.SimRuntime.iOS-27-2"] = [
            {"name": "iPhone 18", "isAvailable": True, "udid": "future-compact"}
        ]
        self.assertEqual([device["udid"] for device in simulators.select_devices(data, "27.1")], ["old-compact", "duo"])
        data["devices"]["com.apple.CoreSimulator.SimRuntime.iOS-27-1"].append(
            {"name": "iPhone 18", "isAvailable": True, "udid": "compact"}
        )
        self.assertEqual([device["udid"] for device in simulators.select_devices(data, "27.1")], ["compact", "duo"])
        with self.assertRaises(ValueError):
            simulators.select_devices(data, "26.0")

    def test_builds_once_and_tests_each_destination_separately(self):
        devices = [
            {"name": "iPhone 18", "udid": "compact", "state": "Shutdown"},
            {"name": "iPhone Duo", "udid": "duo", "state": "Booted"},
        ]
        with patch.object(simulators, "run_command") as run:
            simulators.test_devices(devices)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(sum("build-for-testing" in command for command in commands), 1)
        test_commands = [command for command in commands if "test-without-building" in command]
        self.assertEqual(len(test_commands), 2)
        for command in test_commands:
            self.assertEqual(command.count("-destination"), 1)
            self.assertIn("-test-timeouts-enabled", command)
        self.assertIn(["xcrun", "simctl", "shutdown", "compact"], commands)
        self.assertNotIn(["xcrun", "simctl", "shutdown", "duo"], commands)

    def test_boot_timeout_stops_testing_and_cleans_up_our_device(self):
        devices = [{"name": "iPhone 18", "udid": "compact", "state": "Shutdown"}]
        def execute(command, timeout, label):
            if "bootstatus" in command:
                raise RuntimeError("boot timed out")
        with patch.object(simulators, "run_command", side_effect=execute) as run:
            with self.assertRaisesRegex(RuntimeError, "boot timed out"):
                simulators.test_devices(devices)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertFalse(any("test-without-building" in command for command in commands))
        self.assertIn(["xcrun", "simctl", "shutdown", "compact"], commands)

    def test_command_timeout_terminates_only_its_process_group(self):
        process = Mock(pid=1234)
        process.wait.side_effect = [subprocess.TimeoutExpired("test", 240), 0]
        with patch.object(simulators.subprocess, "Popen", return_value=process) as popen:
            with patch.object(simulators.os, "killpg", create=True) as kill:
                with self.assertRaisesRegex(RuntimeError, "timed out after 240"):
                    simulators.run_command(["test-command"], 240, "Simulator tests")
        popen.assert_called_once_with(["test-command"], start_new_session=True)
        kill.assert_called_once_with(1234, simulators.signal.SIGTERM)
        self.assertEqual(process.wait.call_args_list[0].kwargs["timeout"], 240)

    def test_nonzero_command_fails_validation(self):
        process = Mock()
        process.wait.return_value = 17
        with patch.object(simulators.subprocess, "Popen", return_value=process):
            with self.assertRaisesRegex(RuntimeError, "exit code 17"):
                simulators.run_command(["test-command"], 240, "Simulator tests")


class ReleaseBoundaryTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("openssl"), "OpenSSL is required for the container integration test")
    def test_real_openssl_can_repackage_a_modern_p12(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            certificate = root / "synthetic.pem"
            key = root / "synthetic-key.pem"
            original = root / "synthetic.p12"
            env = {**os.environ, "COACHAI_CERT_PASSWORD": "synthetic-test-password"}
            subprocess.run(
                ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                 "-subj", "/CN=CoachAI synthetic test", "-keyout", str(key), "-out", str(certificate)],
                check=True, capture_output=True, env=env,
            )
            subprocess.run(
                ["openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(certificate),
                 "-passout", "env:COACHAI_CERT_PASSWORD", "-out", str(original)],
                check=True, capture_output=True, env=env,
            )
            converted = release.normalize_certificate(original, root, dict(os.environ), "synthetic-test-password")
            verified = subprocess.run(
                ["openssl", "pkcs12", "-in", str(converted), "-noout", "-info",
                 "-passin", "env:COACHAI_CERT_PASSWORD"],
                check=True, capture_output=True, text=True, env=env,
            )
            self.assertIn("pbeWithSHA1And3-KeyTripleDES-CBC", verified.stderr)
            self.assertIn("MAC: sha1", verified.stderr)
            self.assertTrue(original.exists())

    def test_normalizes_certificate_without_plaintext_files_or_password_arguments(self):
        encrypted_key = "synthetic encrypted test key material"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with patch.object(release, "run", side_effect=[encrypted_key, ""]) as run:
                result = release.normalize_certificate(Path("original.p12"), root, {}, "synthetic-password")
            self.assertEqual(result, root / "certificate-apple.p12")
            self.assertFalse((root / "certificate-encrypted.pem").exists())
        self.assertEqual(run.call_count, 2)
        first, second = run.call_args_list
        self.assertIn("env:COACHAI_CERT_PASSWORD", first.args[0])
        self.assertNotIn("synthetic-password", first.args[0])
        self.assertNotIn("-nodes", first.args[0])
        self.assertIn("-passout", first.args[0])
        self.assertEqual(first.kwargs["env"]["COACHAI_CERT_PASSWORD"], "synthetic-password")
        self.assertIn("-passin", second.args[0])
        self.assertIn("PBE-SHA1-3DES", second.args[0])
        self.assertIn("sha1", second.args[0])
        self.assertNotIn(encrypted_key, second.args[0])

    def test_failed_certificate_decoding_never_prints_process_output(self):
        process = subprocess.CompletedProcess([], 1, stdout=b"synthetic private data", stderr=b"synthetic sensitive log")
        with patch.object(release.subprocess, "run", return_value=process):
            with self.assertRaisesRegex(RuntimeError, "Verify its password") as error:
                release.run(["openssl"], "Distribution certificate decoding", env={})
        self.assertNotIn("synthetic", str(error.exception))

    def test_release_runs_simulator_tests_by_default(self):
        with patch.object(release, "run") as run:
            release.prepare_project({})
        self.assertEqual([call.args[0] for call in run.call_args_list], [
            ["bash", "tools/prepare-ios.sh"], ["bash", "tools/test-ios.sh"],
        ])

    def test_owner_can_waive_simulator_tests_without_skipping_project_generation(self):
        env = {"RUN_SIMULATOR_TESTS": "false"}
        with patch.object(release, "run") as run:
            release.prepare_project(env)
        run.assert_called_once_with(["bash", "tools/prepare-ios.sh"], "Project generation", env=env)

    def test_invalid_simulator_test_choice_fails_before_building(self):
        with patch.object(release, "run") as run:
            with self.assertRaisesRegex(ValueError, "must be true or false"):
                release.prepare_project({"RUN_SIMULATOR_TESTS": "maybe"})
        run.assert_not_called()

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
    def test_source_has_a_boolean_exempt_encryption_declaration(self):
        info = plistlib.loads((TOOLS.parent / "App" / "Info.plist").read_bytes())
        self.assertIs(info.get("ITSAppUsesNonExemptEncryption"), False)

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


class ExportComplianceTests(unittest.TestCase):
    def test_accepts_only_boolean_false_not_missing_string_or_number(self):
        release.validate_export_compliance({"ITSAppUsesNonExemptEncryption": False})
        for value in [True, None, 0, "NO", "false"]:
            with self.subTest(value=value):
                with self.assertRaisesRegex(ValueError, "boolean ITSAppUsesNonExemptEncryption=false"):
                    release.validate_export_compliance({"ITSAppUsesNonExemptEncryption": value})
        for info in [{}, [], None]:
            with self.assertRaises(ValueError):
                release.validate_export_compliance(info)

    def test_binary_archive_plist_preserves_false_as_a_boolean(self):
        binary = plistlib.dumps({"ITSAppUsesNonExemptEncryption": False}, fmt=plistlib.FMT_BINARY)
        release.validate_export_compliance(plistlib.loads(binary))

    def test_checks_the_exported_ipas_real_embedded_plist(self):
        with tempfile.TemporaryDirectory() as temporary:
            ipa = Path(temporary) / "synthetic.ipa"
            for format in [plistlib.FMT_BINARY, plistlib.FMT_XML]:
                with zipfile.ZipFile(ipa, "w") as archive:
                    archive.writestr(
                        "Payload/CoachAI.app/Info.plist",
                        plistlib.dumps({"ITSAppUsesNonExemptEncryption": False}, fmt=format),
                    )
                release.validate_ipa_export_compliance(ipa)

    def test_rejects_an_ipa_missing_the_declaration(self):
        with tempfile.TemporaryDirectory() as temporary:
            ipa = Path(temporary) / "synthetic.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/CoachAI.app/Info.plist", plistlib.dumps({}))
            with self.assertRaisesRegex(ValueError, "Refusing to upload"):
                release.validate_ipa_export_compliance(ipa)

    def test_rejects_an_ipa_with_the_wrong_or_missing_app(self):
        with tempfile.TemporaryDirectory() as temporary:
            ipa = Path(temporary) / "synthetic.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/Other.app/Info.plist", plistlib.dumps({"ITSAppUsesNonExemptEncryption": False}))
            with self.assertRaisesRegex(ValueError, "no readable CoachAI"):
                release.validate_ipa_export_compliance(ipa)

    def test_rejects_a_corrupt_ipa(self):
        with tempfile.TemporaryDirectory() as temporary:
            ipa = Path(temporary) / "synthetic.ipa"
            ipa.write_bytes(b"synthetic invalid archive")
            with self.assertRaisesRegex(ValueError, "no readable CoachAI"):
                release.validate_ipa_export_compliance(ipa)


if __name__ == "__main__":
    unittest.main()
