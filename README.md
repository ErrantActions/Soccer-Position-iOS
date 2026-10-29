# CoachAI for iPhone

Native SwiftUI soccer positioning coach. Bundle ID: `com.errantactions.soccerposition`.
Designed for iOS 26+ with compact, landscape, iPad and expanded Duo layouts.
The same session survives width changes, rotation and folding. Physical folding
behavior still requires device testing.

The App Store Connect/TestFlight record is **CoachAI Soccer Positions**
([app 6828213509](https://appstoreconnect.apple.com/apps/6828213509)).
Apple's store name "CoachAI" was unavailable; the on-device display name remains CoachAI.

- Drag the ball, select LB / LCB / RCB / RB / CDM, and see a deterministic suggestion.
- Optional position heat spot and goal-side guide; accessible ball sliders.
- Pitch-first dark coaching interface with a striped field, distinct role markers,
  quick scenario presets and large position controls.
- Compare two roles against the same ball; draw smoothed curves or straight passes
  with optional ball/player endpoint snapping, undo and redo. Tiny accidental
  gestures are ignored. Finished routes survive rotation and resizing; changing
  the canvas geometry cancels only the unfinished stroke.
- On iOS 27.1+, Apple's actual division reserved regions drive Duo book-fold and
  tabletop layouts. The pitch and coaching controls stay on opposite sides of the
  active fold. On expanded Duo and wide layouts, the pitch fills its own pane
  without scrolling or an aspect-ratio size cap; all controls live in the
  independently scrolling right panel. A horizontal tabletop fold uses a full
  top pitch pane and bottom controls so nothing crosses the hinge.
- Regular phone landscape and medium iPad windows also get a fixed pitch with
  right-hand settings, based on the safe-area window size rather than a device
  model. Small portrait screens place role controls near the pitch, omit the
  oversized introduction, and fit an aspect-correct pitch to the available height.
  Narrow iPad windows reflow to one column without resetting the session.
- Accessibility-sized text uses a single column on ordinary flat displays; a Duo
  coaching desk keeps the fixed pitch and scrollable settings separate. Active
  fold boundaries remain respected. Control rows and metrics reflow for larger
  text; Increase Contrast strengthens card borders and pitch lines. Animations
  honor Reduce Motion.
- Optional **AI Positioning** uses Apple Foundation Models guided generation to
  propose actual coordinates and reasons for all five defensive roles. Edit the
  ball, current teammates, three opponents and formation; tap Analyze or analyze
  automatically after releasing an edit. Current positions are white outlines,
  opponents are red numbers, and accepted AI suggestions are explicitly labeled.
- AI output is rejected rather than silently clamped when field bounds, role
  channels, spacing, goal-side position, back-line shape or central coverage fail.
  Until a valid response arrives, the instant guide remains visibly labeled.
  Requests are cancelled on scene changes and time out after 45 seconds. These
  checks do not prove good soccer tactics; AI Positioning is experimental.
- Apple Foundation Models can also explain the selected role's current cue.
  Availability, rejection and generation failures are visible.
  No cloud AI, analytics, accounts, camera, microphone, location or push notifications.

The default instant guide is a deliberately simplified native teaching model, not feature parity
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
swift test
bash tools/prepare-ios.sh
bash tools/test-ios.sh
```

Install both iPhone Duo and non-Duo iOS 27 simulators compatible with the selected SDK.
The app and tests build once, then each simulator is booted and tested separately
with explicit timeouts. Results remain local under the ignored build directory.
`swift test` runs positioning, fold-layout/coordinate, route, AI-validation and
request-freshness tests
without booting an iOS simulator. The manual unsigned workflow can also compile
the app and iOS test bundle without executing simulators: set
`run_simulator_tests=false`. The owner has standing authorization for TestFlight
deployment after completed, verified app changes; agents dispatch the existing
manual release workflow as part of delivery.

Windows can run the Python/Node guard tests, parse plists and check shell/workflow
syntax. **None of those checks proves the Swift app compiles.**

## Distribution and security

See [the TestFlight runbook](docs/TESTFLIGHT.md) for publication approval,
environment protection, secure local secret upload and owner actions.

Workflows are manual only. The unsigned simulator job and the TestFlight job
use the documented standard `xcode-27` GitHub-hosted runner with Xcode 27.1.
Both are blocked in private staging to avoid unapproved paid compute.
For a release candidate run **TestFlight only**. Its simulator tests default on,
but can be explicitly disabled with `run_simulator_tests=false` for owner-approved
phone testing. Device compilation and signing preflight remain required.
The owner's standing release authorization is recorded in
[project instructions](.github/copilot-instructions.md); there is no second GitHub
reviewer step or per-update approval prompt. GitHub enforces manual dispatch and
main-only deployment, not this conversational authorization. Documentation-only
changes do not require a new build by themselves.

Release uploads require the existing boolean
`ITSAppUsesNonExemptEncryption=false` declaration to survive in both the archived
app and exported IPA. The build fails before upload if it is missing or changed;
review this declaration if the app's cryptography changes.

## Provenance

Original soccer concept and goal-side/profile reference:
[Soccer Position Visualizer](https://github.com/ErrantActions/Soccer-Position-visualizer).
The owner authorized source translation; none of its Git history was imported.
The build/security pattern was reviewed in
[Frigate Horizon](https://github.com/ErrantActions/Frigate-Horizon-iPhone-Public);
none of its app source, bundle ID or Apple identity is used here.

No open-source license is granted merely by public visibility. The owner should
choose a license before offering third-party redistribution rights.
