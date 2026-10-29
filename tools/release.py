"""Approved-job-only signing. Never print commands containing credentials or raw logs."""
import base64
import json
import os
import plistlib
import re
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

from profile import permitted_certificate, validate_entitlements, validate_profile

ROOT = Path(__file__).resolve().parents[1]
SECRET_NAMES = (
    "DISTRIBUTION_CERTIFICATE_BASE64", "DISTRIBUTION_CERTIFICATE_PASSWORD",
    "PROVISIONING_PROFILE_BASE64", "APP_STORE_CONNECT_KEY_ID",
    "APP_STORE_CONNECT_ISSUER_ID", "APP_STORE_CONNECT_PRIVATE_KEY",
)


def mask(value: str) -> None:
    if value:
        escaped = value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::add-mask::{escaped}", flush=True)


def run(args: list[str], label: str, *, env: dict[str, str], capture: bool = False) -> str:
    result = subprocess.run(args, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(f"{label} failed (exit {result.returncode}). Raw signing logs are intentionally not published; reproduce locally with trusted credentials.")
    return result.stdout.decode("utf-8", errors="strict") if capture else ""


def prepare_project(env: dict[str, str]) -> None:
    simulator_tests = env.get("RUN_SIMULATOR_TESTS", "true")
    if simulator_tests not in ("true", "false"):
        raise ValueError("RUN_SIMULATOR_TESTS must be true or false.")
    run(["bash", "tools/prepare-ios.sh"], "Project generation", env=env)
    if simulator_tests == "true":
        run(["bash", "tools/test-ios.sh"], "Simulator build/tests", env=env)
    else:
        print(
            "Simulator tests waived by workflow input. The signed device archive will compile "
            "the app; testing on the physical phone is still required.",
            flush=True,
        )


def cleanup(work: Path) -> None:
    state_path = work / "cleanup.json"
    if state_path.exists():
        state = json.loads(state_path.read_text())
        env = {key: value for key, value in os.environ.items() if key not in SECRET_NAMES}
        keychain = work / "signing.keychain-db"
        failures = []
        if keychain.exists():
            result = subprocess.run(["security", "delete-keychain", str(keychain)], env=env, capture_output=True)
            if result.returncode:
                failures.append("temporary keychain removal")
        if state["keychains"]:
            result = subprocess.run(["security", "list-keychains", "-d", "user", "-s", *state["keychains"]], env=env, capture_output=True)
            if result.returncode:
                failures.append("original keychain-list restoration")
        if state.get("profile"):
            Path(state["profile"]).unlink(missing_ok=True)
        if failures:
            raise RuntimeError("Signing cleanup failed: " + ", ".join(failures))
    shutil.rmtree(work)


def release() -> None:
    if sys.platform != "darwin" or os.environ.get("GITHUB_ACTIONS") != "true":
        raise ValueError("Signing is supported only inside the protected macOS Actions job.")
    for name in (*SECRET_NAMES, "APPLE_TEAM_ID", "MINIMUM_BUILD_NUMBER", "RUNNER_TEMP"):
        if not os.environ.get(name):
            raise ValueError(f"Missing environment configuration: {name}")
    bundle = os.environ.get("APP_BUNDLE_ID")
    if bundle != "com.errantactions.soccerposition":
        raise ValueError("Refusing to sign a different app identity.")
    team = os.environ["APPLE_TEAM_ID"]
    env = {key: value for key, value in os.environ.items() if key not in SECRET_NAMES}
    old_umask = os.umask(0o077)
    work = Path(tempfile.mkdtemp(prefix="coachai-signing-", dir=os.environ["RUNNER_TEMP"]))
    marker = Path(os.environ["RUNNER_TEMP"]) / "coachai-signing-path"
    if marker.exists():
        raise ValueError("A prior signing session needs cleanup.")
    marker.write_text(str(work))
    try:
        cert = work / "certificate.p12"
        profile_file = work / "profile.mobileprovision"
        cert.write_bytes(base64.b64decode(os.environ["DISTRIBUTION_CERTIFICATE_BASE64"], validate=True))
        profile_file.write_bytes(base64.b64decode(os.environ["PROVISIONING_PROFILE_BASE64"], validate=True))
        decoded = run(["security", "cms", "-D", "-i", str(profile_file)], "Profile decoding", env=env, capture=True)
        profile = plistlib.loads(decoded.encode())
        options = validate_profile(profile, team, bundle)
        validate_entitlements(plistlib.loads((ROOT / "App" / "CoachAI.entitlements").read_bytes()), profile)
        mask(profile["Name"])
        keychains_raw = run(["security", "list-keychains", "-d", "user"], "Keychain-list read", env=env, capture=True)
        original_keychains = re.findall(r'"([^"]+)"', keychains_raw)
        if not original_keychains:
            raise ValueError("Could not safely parse the original keychain search list.")
        state = {"keychains": original_keychains, "profile": None}
        (work / "cleanup.json").write_text(json.dumps(state))
        keychain = work / "signing.keychain-db"
        password = secrets.token_hex(32)
        mask(password)
        run(["security", "create-keychain", "-p", password, str(keychain)], "Keychain creation", env=env)
        run(["security", "set-keychain-settings", "-lut", "3600", str(keychain)], "Keychain settings", env=env)
        run(["security", "unlock-keychain", "-p", password, str(keychain)], "Keychain unlock", env=env)
        run(["security", "import", str(cert), "-P", os.environ["DISTRIBUTION_CERTIFICATE_PASSWORD"],
             "-T", "/usr/bin/codesign", "-T", "/usr/bin/security", "-k", str(keychain)], "Distribution certificate import", env=env)
        identities = run(["security", "find-identity", "-v", "-p", "codesigning", str(keychain)], "Signing identity validation", env=env, capture=True)
        matches = re.findall(r'([A-Fa-f0-9]{40}) "([^"]+)"', identities)
        if len(matches) != 1 or not matches[0][1].startswith("Apple Distribution:"):
            raise ValueError("Expected exactly one valid Apple Distribution certificate/private-key identity.")
        fingerprint, identity = matches[0]
        mask(identity)
        mask(identity.removeprefix("Apple Distribution:").strip().removesuffix(f" ({team})"))
        if not permitted_certificate(fingerprint, profile):
            raise ValueError("The signing certificate is not allowed by this app's profile.")
        key_dir = work / "private_keys"
        key_dir.mkdir()
        key_id = os.environ["APP_STORE_CONNECT_KEY_ID"]
        if not re.fullmatch(r"[A-Z0-9]{10}", key_id):
            raise ValueError("Invalid App Store Connect key ID.")
        key_path = key_dir / f"AuthKey_{key_id}.p8"
        key_path.write_text(os.environ["APP_STORE_CONNECT_PRIVATE_KEY"])
        api_env = {**env, "ASC_KEY_FILE": str(key_path),
                   "APP_STORE_CONNECT_KEY_ID": key_id,
                   "APP_STORE_CONNECT_ISSUER_ID": os.environ["APP_STORE_CONNECT_ISSUER_ID"]}
        # This authenticated query prevents run-number resets and rejects APNs keys.
        number = run(["node", "tools/asc.mjs"], "App Store Connect app/build-number preflight", env=api_env, capture=True).strip()
        if not re.fullmatch(r"[1-9]\d{0,3}", number):
            raise ValueError("App Store Connect preflight returned an invalid build number.")
        env["BUILD_NUMBER"] = number
        print(f"Preflight passed. Selected build {number}.", flush=True)
        prepare_project(env)
        run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, str(keychain)], "Signing key access configuration", env=env)
        run(["security", "list-keychains", "-d", "user", "-s", str(keychain), *original_keychains], "Signing search-list configuration", env=env)
        profiles = Path.home() / "Library" / "MobileDevice" / "Provisioning Profiles"
        profiles.mkdir(parents=True, exist_ok=True)
        installed_profile = profiles / f'{profile["UUID"]}.mobileprovision'
        if installed_profile.exists():
            raise ValueError("Refusing to overwrite an existing provisioning profile.")
        state["profile"] = str(installed_profile)
        (work / "cleanup.json").write_text(json.dumps(state))
        shutil.copyfile(profile_file, installed_profile)
        export_options = work / "ExportOptions.plist"
        export_options.write_bytes(plistlib.dumps(options))
        archive = work / "CoachAI.xcarchive"
        run(["xcodebuild", "-project", "CoachAI.xcodeproj", "-scheme", "CoachAI",
             "-configuration", "Release", "-destination", "generic/platform=iOS",
             "-archivePath", str(archive), "-derivedDataPath", str(work / "DerivedData"),
             f"DEVELOPMENT_TEAM={team}", "CODE_SIGN_STYLE=Manual",
             "CODE_SIGN_IDENTITY=Apple Distribution",
             f'PROVISIONING_PROFILE_SPECIFIER={profile["Name"]}',
             "OTHER_CODE_SIGN_FLAGS=--keychain " + str(keychain), "archive"], "Signed archive", env=env)
        exported = work / "export"
        run(["xcodebuild", "-exportArchive", "-archivePath", str(archive),
             "-exportPath", str(exported), "-exportOptionsPlist", str(export_options)], "IPA export", env=env)
        ipas = list(exported.glob("*.ipa"))
        if len(ipas) != 1:
            raise ValueError("Expected exactly one exported IPA.")
        upload_env = {**env, "API_PRIVATE_KEYS_DIR": str(key_dir)}
        run(["xcrun", "altool", "--upload-app", "-f", str(ipas[0]), "-t", "ios",
             "--apiKey", key_id, "--apiIssuer", os.environ["APP_STORE_CONNECT_ISSUER_ID"]],
            "TestFlight upload", env=upload_env)
        print("Upload accepted by Apple. Processing, tester assignment, and phone installation are not yet verified.")
    finally:
        try:
            cleanup(work)
            marker.unlink(missing_ok=True)
        finally:
            os.umask(old_umask)


def cleanup_remaining() -> None:
    root = Path(os.environ["RUNNER_TEMP"]).resolve()
    marker = root / "coachai-signing-path"
    if marker.exists():
        work = Path(marker.read_text()).resolve()
        if work.parent != root or not work.name.startswith("coachai-signing-"):
            raise ValueError("Refusing an unsafe cleanup path.")
        if work.exists():
            cleanup(work)
        marker.unlink()


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda *_: sys.exit("Job cancelled; cleaning up signing material."))
    try:
        if sys.argv[1:] == ["--cleanup"]:
            cleanup_remaining()
        else:
            release()
    except (ValueError, RuntimeError, OSError, plistlib.InvalidFileException) as error:
        raise SystemExit(f"Release failed: {error}") from error
