"""Build once, then test SDK-compatible simulators sequentially with bounded waits."""
import json
import os
import re
import signal
import subprocess
import sys
from pathlib import Path


def select_devices(data: dict, sdk: str) -> list[dict]:
    if not re.fullmatch(r"27\.\d+(?:\.\d+)?", sdk):
        raise ValueError("Select the documented iOS 27 simulator SDK.")
    runtimes = []
    for runtime, entries in data["devices"].items():
        match = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-27-(\d+)(?:-(\d+))?", runtime)
        if match and int(match.group(1)) <= int(sdk.split(".")[1]):
            runtimes.append(((int(match.group(1)), int(match.group(2) or 0)), runtime, entries))
    devices = [
        {**device, "runtime": runtime}
        for _, runtime, entries in sorted(runtimes, key=lambda item: item[0], reverse=True)
        for device in entries
        if device.get("isAvailable") and "iPhone" in device["name"]
    ]
    duo = next((device for device in devices if "Duo" in device["name"]), None)
    compact = next((device for device in devices if "Duo" not in device["name"]), None)
    if not duo or not compact:
        raise ValueError(f"Install iPhone Duo and non-Duo iOS 27 simulators compatible with SDK {sdk}.")
    return [compact, duo]


def run_command(command: list[str], timeout: int, label: str) -> None:
    print(label, flush=True)
    process = subprocess.Popen(command, start_new_session=True)
    try:
        code = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired as error:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        raise RuntimeError(f"{label} timed out after {timeout} seconds.") from error
    if code:
        raise RuntimeError(f"{label} failed with exit code {code}.")


def test_devices(devices: list[dict]) -> None:
    common = [
        "-project", "CoachAI.xcodeproj", "-scheme", "CoachAI", "-configuration", "Debug",
        "-derivedDataPath", "build/DerivedData",
        "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "DEVELOPMENT_TEAM=",
    ]
    run_command(
        ["xcodebuild", "build-for-testing", *common, "-destination", "generic/platform=iOS Simulator"],
        600, "Building the unsigned simulator app and test bundle",
    )
    for index, device in enumerate(devices):
        identifier = device["udid"]
        started = False
        try:
            if device.get("state") != "Booted":
                run_command(["xcrun", "simctl", "boot", identifier], 30, f"Booting {device['name']}")
                started = True
            run_command(["xcrun", "simctl", "bootstatus", identifier, "-b"], 150, f"Waiting for {device['name']} readiness")
            run_command(
                ["xcodebuild", "test-without-building", *common,
                 "-only-testing:CoachAITests",
                 "-destination", f"platform=iOS Simulator,id={identifier}",
                 "-destination-timeout", "60", "-parallel-testing-enabled", "NO",
                 "-test-timeouts-enabled", "YES",
                 "-default-test-execution-time-allowance", "30",
                 "-maximum-test-execution-time-allowance", "60",
                 "-resultBundlePath", f"build/Tests-{index}.xcresult"],
                240, f"Running tests on {device['name']}",
            )
        finally:
            if started:
                run_command(["xcrun", "simctl", "shutdown", identifier], 30, f"Shutting down {device['name']}")


def main() -> None:
    if sys.platform != "darwin":
        raise ValueError("Native validation requires macOS and full Xcode.")
    os.chdir(Path(__file__).resolve().parents[1])
    Path("build").mkdir(exist_ok=True)
    sdk = subprocess.check_output(
        ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True, timeout=30
    ).strip()
    data = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True, timeout=30
    ))
    devices = select_devices(data, sdk)
    print(f"Testing with iOS SDK {sdk}: " + ", ".join(
        f"{device['name']} ({device['runtime'].removeprefix('com.apple.CoreSimulator.SimRuntime.').replace('-', '.')})"
        for device in devices
    ), flush=True)
    test_devices(devices)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(f"Native validation failed: {error}") from error
