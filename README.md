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
- The native navigation toolbar exposes position, drawing, AI analysis and a More
  menu backed by the same state as the coaching panels. iOS adapts this real
  toolbar to Duo's vertical edge bar; custom control cards alone do not populate it.
- Compare two roles against the same ball; draw smoothed curves or straight passes
  with optional ball/player endpoint snapping, undo and redo. Tiny accidental
  gestures are ignored. Finished routes survive rotation and resizing; changing
  the canvas geometry cancels only the unfinished stroke.
- On iOS 27.1+, Apple's actual division reserved regions drive Duo book-fold and
  tabletop layouts. The pitch and coaching controls stay on opposite sides of the
  active fold. On expanded Duo and wide layouts, the pitch fits its own pane
  without scrolling or stretching; all controls live in the
  independently scrolling right panel. A horizontal tabletop fold uses a full
  top pitch pane and bottom controls so nothing crosses the hinge.
- The actual playing area uses a common **105 x 68 m** reference with one uniform
  metre-to-screen scale. It letterboxes when needed rather than distorting the
  field, circles or player/route geometry. Box, spot and goal markings use metres.
  The navigation title bar is hidden so settings scrolling cannot collapse it
  and resize the field; the native action toolbar remains registered and visible.
- Duo uses its dedicated route-tools / AI / role control ordering and spacing,
  independent of regular-device refinements. Active folds select that presentation
  directly; the fully open inner display uses inactive division information.
  A flat Duo window with room for two 240-point panes keeps the full-pitch desk.
  Closed or narrower views retain usable compact controls.
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
- A local playbook keeps named setups, coaching notes, favorites and captured
  sequences. Search, duplicate, import/export editable JSON play files, or share
  a self-contained SVG field diagram. Four example scenes help you get started.
- Capture up to 24 decision steps, replace or remove a step, choose its hold time,
  and play the sequence. Playback locks scene edits and pauses when the app becomes
  inactive. Save the play to persist the sequence; the unsaved workbench is a session.
- Positioning practice hides hints, routes and target accessibility coordinates
  until you check your guess. It uses an 8 m reference zone on the real-size pitch,
  not a claim that one precise coordinate is correct. Your-player sliders support
  VoiceOver; session totals track checked rounds and in-zone guesses.
- Optional spoken cues use system speech synthesis, with no microphone, recording
  or background audio. Speech stops when the scene changes or the app is inactive.
- Current teammates and opponents can be edited without AI. Reviewed AI suggestions
  can be adopted as editable positions before saving or sequencing.
- Six researched, original animated tactical patterns show passes and player runs:
  outside overlap, inside underlap, third-player combination, switch of play,
  wide press-and-cover and a compact defensive slide. Scrub, step, loop or play at
  0.5x/1x/2x; Reduce Motion switches to discrete phases. Save a copy in the playbook
  to rename, annotate, favorite or share it.
- On **iOS 27+**, field-only external presentation uses Apple's scene-accessory API
  with supported AirPlay or wired displays. Ball, players, routes, AI suggestions,
  practice reveals and animated plays appear without the device's control panels
  or saved notes. A device-side switch blanks the external field. No display is
  needed to use the app.

The default instant guide is a deliberately simplified native teaching model, not feature parity
with the web application's full multi-player tactical engine or challenge mode.
It is not professional match analysis. Model-generated explanations can be wrong.

## Coaching workbench

Open **Playbook** in the coaching panel or native **More** menu. Quick save stores
the current editable scene and sequence; the library lets you rename it, add notes,
favorite it or share it. Loading a setup stops AI preview and restores editable
inputs, routes and layers; it never reuses a saved model response as authority.
Tap a numbered sequence step to load it before editing/replacing. SVG diagrams
show editable positions, not a cached AI preview, and include only the first 240
notes characters; JSON includes full notes and all steps. Import `.coachai.json`
files through Files. Share deliberately: recipients receive your notes.

The local library is stored in Application Support and written atomically, with
complete file protection on iOS. The app does not upload it; iOS device backups may
include it according to system settings. Imports are validated before saving and
given new identities so they cannot overwrite another play. Limits are 100 plays,
24 steps/play, 2 MB per share/import and 20 MB for the library. Each board supports
100 routes and 20,000 total route points. Invalid data fails visibly rather than
being silently repaired. A damaged library is preserved and locked against edits;
the library offers recovery export and an explicit reset that keeps a recovery copy.

Start **Your turn** to practice. Place your player, then check to reveal the guide
and zone. Use **Next scenario**, change role, or end practice to continue coaching.
Practice uses the simplified instant guide, not Apple Intelligence or a professional
tactical assessment. Spoken cues are manually started and do not read saved notes.

## Animated patterns and presentation

Open **Playbook > Animated tactical patterns**, select a play and press Play.
Lime represents the coaching team; red represents opposition. These focused
illustrations show selected players, not full match simulations or offside checks.
Coordinates, coaching text and diagrams are original CoachAI work. No source
images, videos, authored drill instructions or match reconstructions are bundled.
Links in each play explain the underlying principles and open only when tapped:

- [Full-back overlaps and underlaps](https://learning.coachesvoice.com/cv/modern-full-back-explained-alexander-arnold-robertson-alba/)
- [Third-man combinations](https://learning.coachesvoice.com/cv/third-man-runs-football-tactics-explained-gasperini-guardiola/)
- [Switching play and defensive recovery](https://learning.coachesvoice.com/cv/switches-of-play-football-tactics-explained/)
- [Compact blocks and coordinated pressure](https://learning.coachesvoice.com/cv/mid-block-football-tactics-explained/)

These are research references, not affiliations, endorsements or licenses to copy
those sites' material. Coaching choices remain illustrative and need coach review.

Animated JSON files use schema version 2 and preserve player motion, phases,
notes and references. Existing version-1 scenes and libraries still load.
Older app versions reject animated version-2 files rather than show a misleading
static scene. SVG sharing exports the animation's **opening frame only** and
labels it as static. Animated clips support 2–22 players, 2–24 phases and up to
120 seconds. Ordinary editable-board sequences remain a separate format.

For presentation, connect a supported AirPlay display through Control Center, or
use a video-capable wired adapter, then return to CoachAI. Keep the controller app
in the foreground. iOS 27+ registers a noninteractive external-display accessory;
the system chooses when to connect it. Watch the connection status and verify
the audience view. Blanking keeps that scene black rather than intentionally
switching back to mirroring the private controls. Before iOS 27, the app retains
normal operation but does not offer separate field presentation.

**This is not a custom FaceTime/Zoom broadcast.** General device screen sharing,
system UI, app switching and unsupported receivers may still mirror the phone.
Never assume the app's external scene hides other applications or system screens.
Physical receiver/cable behavior needs device verification.

Apple reference: [Presenting content on a connected display](https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display).
The animation viewer reuses the main fold-aware layout policy and real field
projection; native playback toolbar items remain on the device.

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
`swift test` runs positioning, fold-layout/coordinate, route, AI-validation,
request-freshness, playbook/codec/persistence, practice, sequence and SVG tests
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
