"""Validate App Store distribution identity before compiling."""
import datetime as dt
import hashlib
import re
from typing import Any


def validate_profile(profile: dict[str, Any], team: str, bundle: str) -> dict[str, Any]:
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("Configure a valid APPLE_TEAM_ID environment variable.")
    if profile.get("TeamIdentifier") != [team]:
        raise ValueError("Provisioning profile team does not match this app's team.")
    entitlements = profile.get("Entitlements", {})
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    if len(prefixes) != 1 or entitlements.get("application-identifier") != f"{prefixes[0]}.{bundle}":
        raise ValueError("Profile must match this app's exact bundle ID, not a wildcard.")
    if entitlements.get("com.apple.developer.team-identifier") != team:
        raise ValueError("Profile's team entitlement is inconsistent.")
    expiry = profile.get("ExpirationDate")
    if not isinstance(expiry, dt.datetime):
        raise ValueError("Profile has no valid expiry date.")
    if expiry.replace(tzinfo=dt.timezone.utc) <= dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=1):
        raise ValueError("Profile is expired or expires within one hour.")
    if "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices") or entitlements.get("get-task-allow") is not False:
        raise ValueError("Use an App Store distribution profile, not development/ad hoc/enterprise.")
    if not profile.get("DeveloperCertificates"):
        raise ValueError("Profile has no permitted signing certificates.")
    if not isinstance(profile.get("Name"), str) or not profile["Name"]:
        raise ValueError("Profile has no name.")
    if not re.fullmatch(r"[A-Fa-f0-9-]{36}", str(profile.get("UUID", ""))):
        raise ValueError("Profile has no safe UUID.")
    return {
        "method": "app-store-connect",
        "destination": "export",
        "signingStyle": "manual",
        "teamID": team,
        "signingCertificate": "Apple Distribution",
        "provisioningProfiles": {bundle: profile["Name"]},
        "manageAppVersionAndBuildNumber": False,
        "uploadSymbols": False,
    }


def validate_entitlements(required: dict[str, Any], profile: dict[str, Any]) -> None:
    # This first release has no optional capabilities. Fail closed if that changes.
    if required:
        raise ValueError("New app entitlements require explicit profile-validation support before release.")
    if profile["Entitlements"].get("get-task-allow") is not False:
        raise ValueError("Debug entitlement is not permitted for distribution.")


def permitted_certificate(identity_sha1: str, profile: dict[str, Any]) -> bool:
    return any(hashlib.sha1(cert).hexdigest().upper() == identity_sha1.upper()
               for cert in profile["DeveloperCertificates"])
