#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun simctl list devices available --json > build/simulators.json
destinations=()
while IFS= read -r identifier; do
  destinations+=("-destination" "platform=iOS Simulator,id=$identifier")
done < <(python3 tools/select-simulators.py build/simulators.json)
if [[ ${#destinations[@]} -ne 4 ]]; then
  echo "ERROR: Both compact and Duo iOS simulators are required." >&2
  exit 1
fi
xcodebuild test -project CoachAI.xcodeproj -scheme CoachAI \
  -configuration Debug "${destinations[@]}" \
  -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
