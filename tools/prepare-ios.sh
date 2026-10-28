#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "ERROR: Native validation requires macOS and full Xcode." >&2
  exit 1
fi
: "${BUILD_NUMBER:?BUILD_NUMBER is required}"
xcodebuild -version
sdk="$(xcrun --sdk iphoneos --show-sdk-version)"
if [[ "$sdk" != 27.* ]]; then
  echo "ERROR: Select the documented Xcode 27 SDK for Duo validation." >&2
  exit 1
fi
python3 tools/generate-assets.py
plutil -lint App/Info.plist App/CoachAI.entitlements App/PrivacyInfo.xcprivacy
xcodegen generate
