# CoachAI for iPhone

Native SwiftUI soccer positioning coach. Bundle ID: `com.errantactions.soccerposition`.
Designed for iOS 26+ with compact, landscape, iPad and expanded Duo layouts.
The same ball and position state survive width changes; wider windows show the
pitch and controls side by side. Physical folding behavior still requires device testing.

The App Store Connect/TestFlight record is **CoachAI Soccer Positions**
([app 6828213509](https://appstoreconnect.apple.com/apps/6828213509)).
Apple's store name "CoachAI" was unavailable; the on-device display name remains CoachAI.

- Drag the ball, select LB / LCB / RCB / RB / CDM, and see a deterministic suggestion.
- Optional position heat spot and goal-side guide; accessible ball sliders.
- Apple Foundation Models can explain the teaching cue on supported devices.
  AI does **not** calculate positions. Availability and generation failures are visible.
  No cloud AI, analytics, accounts, camera, microphone, location or push notifications.

This is a new, deliberately simplified native teaching model, not feature parity
with the web application's full multi-player tactical engine or challenge mode.
It is not professional match analysis. Model-generated explanations can be wrong.

## Build

The source of truth is [project.yml](project.yml); XcodeGen generates the ignored
Xcode project and shared scheme. No generated project or local editor settings
are committed.

On macOS, with full Xcode 27.1 selected, Homebrew, Python 3 and Node.js installed:

```bash
brew bundle --file Brewfile
export DEVELOPER_DIR=/Applications/Xcode_27.1.app/Contents/Developer
export BUILD_NUMBER=1
python3 -m unittest discover -s tools/tests
bash tools/prepare-ios.sh
bash tools/test-ios.sh
```

Install both iPhone Duo and non-Duo iOS 27 simulators compatible with the selected SDK.
The app and tests build once, then each simulator is booted and tested separately
with explicit timeouts. Results remain local under the ignored build directory.
Windows can run the Python/Node guard tests, parse plists and check shell/workflow
syntax. **None of those checks proves the Swift app compiles.**

## Distribution and security

See [the TestFlight runbook](docs/TESTFLIGHT.md) for publication approval,
environment protection, secure local secret upload and owner actions.

Workflows are manual only. The unsigned simulator job and the TestFlight job
use the documented standard `xcode-27` GitHub-hosted runner with Xcode 27.1.
Both are blocked in private staging to avoid unapproved paid compute.
For a release candidate run **TestFlight only**: it already includes the same tests.

## Provenance

Original soccer concept and goal-side/profile reference:
[Soccer Position Visualizer](https://github.com/ErrantActions/Soccer-Position-visualizer).
The owner authorized source translation; none of its Git history was imported.
The build/security pattern was reviewed in
[Frigate Horizon](https://github.com/ErrantActions/Frigate-Horizon-iPhone-Public);
none of its app source, bundle ID or Apple identity is used here.

No open-source license is granted merely by public visibility. The owner should
choose a license before offering third-party redistribution rights.
