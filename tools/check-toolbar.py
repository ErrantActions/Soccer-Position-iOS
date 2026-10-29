"""One bounded, ad-hoc-signed simulator UI check; no distribution credentials."""
import json
import os
import subprocess
import sys
from pathlib import Path

from ios_tests import run_command, select_devices


def main() -> None:
    if sys.platform != "darwin":
        raise ValueError("The rendered toolbar check requires macOS and Xcode.")
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    sdk = subprocess.check_output(
        ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True, timeout=30
    ).strip()
    data = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True, timeout=30
    ))
    device = next(device for device in select_devices(data, sdk) if "Duo" in device["name"])
    identifier = device["udid"]
    results = root / "build" / "Toolbar.xcresult"
    screenshots = root / "build" / "ToolbarScreenshots"
    started = False
    try:
        if device.get("state") != "Booted":
            run_command(["xcrun", "simctl", "boot", identifier], 30, "Booting the Duo UI-check simulator")
            started = True
        run_command(["xcrun", "simctl", "bootstatus", identifier, "-b"], 150, "Waiting for Duo simulator readiness")
        run_command([
            "xcodebuild", "test", "-project", "CoachAI.xcodeproj", "-scheme", "CoachAI",
            "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={identifier}",
            "-destination-timeout", "60", "-parallel-testing-enabled", "NO",
            "-only-testing:CoachAIUITests/ToolbarSmokeTests/testNativeToolbarIsPopulatedAndDrawingActionWorks",
            "-test-timeouts-enabled", "YES", "-maximum-test-execution-time-allowance", "120",
            "-derivedDataPath", "build/DerivedData", "-resultBundlePath", str(results),
            "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Automatic", "DEVELOPMENT_TEAM=",
        ], 420, "Checking visible native toolbar controls and their drawing action")
    finally:
        try:
            if results.exists():
                run_command([
                    "xcrun", "xcresulttool", "export", "attachments",
                    "--path", str(results), "--output-path", str(screenshots),
                ], 30, "Exporting only toolbar screenshot attachments")
        finally:
            if started:
                run_command(["xcrun", "simctl", "shutdown", identifier], 30, "Shutting down the UI-check simulator")
    if not any(screenshots.rglob("*.png")):
        raise RuntimeError("The UI check did not produce its required screenshot evidence.")
    print("Native toolbar actions rendered and drawing toggled in Duo portrait and landscape.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Toolbar UI check failed: {error}") from error
