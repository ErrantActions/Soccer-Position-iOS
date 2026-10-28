"""Require two distinct installed iPhone sizes without guessing simulator UUIDs."""
import json
import sys
from pathlib import Path


def select_devices(data: dict) -> list[str]:
    devices = [
        device
        for runtime, entries in data["devices"].items()
        if "iOS-27-" in runtime
        for device in entries
        if device.get("isAvailable") and "iPhone" in device["name"]
    ]
    duo = next((device for device in devices if "Duo" in device["name"]), None)
    compact = next((device for device in devices if "Duo" not in device["name"]), None)
    if not duo or not compact:
        raise ValueError("Install both an iPhone Duo and a non-Duo iOS 27 simulator.")
    return [compact["udid"], duo["udid"]]


if __name__ == "__main__":
    try:
        print("\n".join(select_devices(json.loads(Path(sys.argv[1]).read_text()))))
    except (ValueError, KeyError, OSError) as error:
        raise SystemExit(f"Simulator selection failed: {error}") from error
