# CoachAI publication and TestFlight runbook

## Security boundaries

Only audited native source and build configuration belong in this independent
repository. Do not copy upstream `.git`, history, editor settings, build output,
signing files or environment files. Use `ErrantActions` and the public noreply
address `11909244+ErrantActions@users.noreply.github.com` for Git author/committer.
The old source repository remains untouched; it was already public, not a private
backup. Do not change its visibility without separate owner authorization.

Before any public transition, present scan findings and obtain explicit owner
approval. Verify the actual index with `git ls-files --stage`, ignored files with
`git status --ignored`, all refs/history and author metadata. `.gitignore` does not
untrack secrets. If an actual credential is found, stop, revoke it and obtain
approval before any history rewrite. Never print its value.

Repository admins, repository writers, workflow changes, Xcode build scripts,
Homebrew tools and code executed in release jobs must be trusted. The owner
explicitly removed GitHub's separate required-reviewer step and granted standing
authorization to deploy completed, verified app changes to TestFlight. Review the
**exact commit** before dispatch; do not request another per-update approval unless
the owner pauses deployment. GitHub cannot enforce conversational authorization:
anyone with workflow-dispatch permissions can start a release from
main. Changes to workflows or signing helpers can exfiltrate environment secrets.
Secrets are not exposed to pull requests or forks by these manual-only workflows;
the release additionally requires this exact repository and the main ref.

## Repository controls

After approved publication, verify using GitHub settings/API:

1. Repository is public, not a fork, and has one initial root commit with no old
   ancestry. No imported tags or branches.
2. Security and analysis: enable secret scanning and push protection where available.
   These complement local audits; neither detects every private URL or secret.
3. Actions default token permissions: read; do not allow Actions to approve PRs.
   Each workflow also declares `contents: read`.
4. `app-store` environment: no required reviewers, as explicitly requested by the
   owner; custom branch policy permitting **only the branch `main`**, no tag
   policies. Disable admin bypass
   before uploading signing secrets. The helper fails closed if bypass status
   cannot be verified as disabled. If reviewer protection is restored, the helper
   accepts only the sole owner `ErrantActions` and leaves that protection intact.
5. Upload secrets only after the main-only policy is confirmed. Do not remove any
   other protections or change billing limits to work around errors. The reviewer
   exception is an explicit owner decision, not a requirement for free builds.
6. Preserve existing protection rules when uploading secrets. The upload helper
   reads/verifies them and never creates or updates the environment.

All external Actions are full-SHA pinned, verified against official repositories.
Checkout does not persist Git credentials. Reverify SHAs when updating Actions.

## Runner and cost

GitHub lists `xcode-27` as a **standard** public-repository ARM64 macOS runner:

- [Standard runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Xcode 27 image inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
- [Billing: standard public runners are free; larger runners are not](https://docs.github.com/en/billing/concepts/product-billing/github-actions)

Verified 2026-10-28: the image includes `/Applications/Xcode_27.1.app` and iOS 27.1.
It is a public-preview runner with GitHub's preview availability limitations.
Do not silently substitute a larger, paid or self-hosted runner. Recheck image
inventory if provisioning fails. No billing settings are modified by this setup.

Simulator jobs time out at 30 minutes, TestFlight at 40. Artifacts are off by
default; the simulator workflow may save **only** the unsigned `.app` for one day.
Storage has separate billing rules. No archives, results, signing files or raw
signing logs are uploaded. An unsigned simulator app cannot install on an iPhone.

The pinned actionlint version may not yet recognize `xcode-27`. After verifying
the current official runner reference, validate with an exception only for its
unknown-label diagnostic; do not suppress other diagnostics.

## Apple identity and credentials

Display name: **CoachAI**. Bundle ID: **com.errantactions.soccerposition**.
App Store Connect/TestFlight name: **CoachAI Soccer Positions**,
[app 6828213509](https://appstoreconnect.apple.com/apps/6828213509).
The shorter store name was already taken; the on-device display name is unchanged.
Marketing version currently `1.0` in [project.yml](../project.yml); confirm this
against the app record before the first release. No Frigate identifiers or
capabilities are reused. The Apple team ID is an environment variable, not source.

Owner prerequisites:

1. Active Apple Developer membership and accepted agreements.
2. Explicit registered App ID for the exact bundle ID, no extra capabilities.
3. Access to the existing CoachAI Soccer Positions app record above. It was created
   using the exact soccer bundle ID; do not create a duplicate record.
4. Valid Apple Distribution `.p12` including its private key; it may be reused
   from the same Apple team if valid and permitted by the new app's profile.
5. A new/matching **App Store Connect distribution provisioning profile** for
   this app, including that certificate. Not development, ad hoc or enterprise.
6. An **App Store Connect API key** with sufficient access to this app and build
   uploads (usually App Manager). An **APNs provider key is not an upload key**.
   Existing encrypted GitHub secret values cannot be read back and copied.

Never paste passwords, base64 credentials or `.p8` contents into chat.
Keep local originals in a restricted directory outside the repository, preferably
not cloud-synced. Do not run upload commands under PowerShell transcription,
verbose shell tracing or shared terminal recording.

## Secure local upload (Windows)

Install/authenticate official GitHub CLI using `gh auth login`; do not put a token
in a command or chat. Run the helper locally, substituting **file paths and IDs**:

```powershell
.\tools\upload-signing.ps1 `
  -CertificatePath 'C:\PrivateSigning\distribution.p12' `
  -ProfilePath 'C:\PrivateSigning\CoachAI.mobileprovision' `
  -ApiKeyPath 'C:\PrivateSigning\AuthKey_UPLOADKEY.p8' `
  -KeyId 'UPLOADKEY1' -IssuerId 'YOUR-APP-STORE-CONNECT-ISSUER-UUID' `
  -TeamId 'YOURTEAMID'
```

Use your real 10-character key/team IDs and issuer UUID. `-GhPath` can point at a
portable official `gh.exe`. The certificate password is prompted with masked
entry and sent to GitHub over stdin, never as a command argument or plaintext file.
The helper verifies public/non-fork status, disabled admin bypass and main-only
rules; any configured reviewer must be the sole owner
before sending values; a partial network failure may require rerunning it.

Encrypted **app-store environment** secrets:

| Secret | Source |
|---|---|
| DISTRIBUTION_CERTIFICATE_BASE64 | Binary `.p12`, base64 encoded in memory |
| DISTRIBUTION_CERTIFICATE_PASSWORD | Masked local prompt |
| PROVISIONING_PROFILE_BASE64 | Matching `.mobileprovision`, encoded in memory |
| APP_STORE_CONNECT_KEY_ID | Upload key identifier |
| APP_STORE_CONNECT_ISSUER_ID | App Store Connect issuer UUID |
| APP_STORE_CONNECT_PRIVATE_KEY | Upload key `.p8` |

The helper also sets `APPLE_TEAM_ID` in the same environment. It never mutates
reviewers, deployment branches or environment protection rules.

## What release validation actually does

Before compiling, the approved job validates the profile team, application prefix,
exact bundle ID, expiry (at least one hour), App Store distribution type, debug
entitlement, valid signing identity and certificate membership in the profile.
The app's required-entitlements file is currently empty. Adding capabilities
fails closed until profile validation is updated.

The encrypted P12 is repackaged in the restricted temporary job directory using
Apple-compatible PKCS12 encryption before keychain import. The intermediate PEM
private key remains encrypted and is immediately removed after repackaging; no
plaintext private-key file is written. The password stays in the signing subprocess environment, not command
arguments, build environments or logs. The original credential is not modified.

The upload key authenticates to App Store Connect, resolves the exact bundle ID,
and paginates **all** existing builds. The next integer build number exceeds every
uploaded version and the manual minimum. It does not depend on resettable GitHub
run numbers. Unsupported existing formats, API errors and range exhaustion fail
closed. This implementation permits integer build numbers 1 through 9999.
Upload workflows are serialized; uploads from outside this repository must also
be coordinated to avoid a race between preflight and upload.

After preflight: generate the actual CoachAI Xcode project, test both simulator
destinations, archive for a physical device, export, and upload via `altool`.
Simulator validation builds once, selects each device's newest installed iOS 27
runtime no newer than the selected SDK, and runs each destination sequentially.
The runner currently supplies regular iPhones on iOS 27.0 and Duo on iOS 27.1;
both are supported by Xcode 27.1, so identical runtime versions are not required.
Boot readiness is limited to
150 seconds and each simulator's test process to 240 seconds; a timeout fails
the job rather than proceeding to signing. Only simulators started by the helper
are shut down. Local result bundles are not uploaded as artifacts.
Temporary files use owner-only permissions; credentials are removed from child
build/test environments. Certificate identity and generated keychain password
are masked. Private subprocess output is not printed as public signing logs.
Cleanup restores the keychain search list and removes the temporary profile,
keychain, API key, archive, IPA and other signing files. An always-run step retries
cleanup after failure/cancellation; GitHub also discards its hosted VM. Hard
termination can prevent cleanup, so never use this on a persistent shared runner.

Privacy manifest: no tracking, collected data or required-reason APIs in the
current implementation. No permission prompts for unused sensors are declared.
Reassess the manifest, purpose strings and export-compliance answer when features
or dependencies change. Foundation Models needs supported hardware, a supported
region/language, enabled Apple Intelligence and a downloaded model; simulator
tests do not establish model availability.

## Manual workflow and verification stages

1. Publish only after owner approval and repository/security verification.
2. For routine unsigned validation: Actions > Simulator validation > main >
   confirm. This compiles/tests; it does not sign or upload. To avoid launching
   simulators, disable **Execute compact and Duo simulators**: the workflow still
   runs portable Swift positioning/layout tests and compiles the full native app
   and iOS test bundle. It does not claim simulator execution or device testing.
3. For a release candidate: Actions > TestFlight > main > confirm upload.
   **Do not run a duplicate simulator workflow first**. Simulator tests default on;
   disable **Run simulator tests** for the owner-approved physical-phone path.
   Apple does not require simulator tests for TestFlight. The signed device archive
   still compiles the app, and signing/app/build-number checks are never waived.
4. Inspect the exact commit and use the owner's standing release authorization for
   completed, verified app changes. Dispatch the existing manual workflow with
   `confirm_upload=true` and `run_simulator_tests=false`; no separate approval
   prompt is needed. Respect later requests to pause, and never deploy failed
   checks. Documentation-only changes do not require a release by themselves.
   There is no separate `app-store` reviewer prompt under the owner-selected policy.
5. Successful job upload means Apple accepted the upload request, not that
   processing finished. Check App Store Connect > CoachAI > TestFlight.
6. Resolve export compliance and processing errors; assign internal testers.
   External testers may require Beta App Review.
7. Install via Apple's TestFlight app on the phone and verify controls,
   compact/unfolded transitions, rotation, accessibility and on-device explanations.
   This is a separate manual verification, not implied by a green Actions run.

No public App Store release is submitted by these workflows.

## Publication and signing handoff (2026-10-28)

- The owner explicitly approved publication. The repository is public and not a
  fork, with a new noreply-authored root and no imported upstream ancestry.
  Push only `main`; never mirror local editor/agent checkpoint refs.
- Secret scanning and push protection are enabled; the alert list was empty.
  Default Actions token permissions are read-only, with PR approval disabled.
- Effective `app-store` rules were read back: only the branch `main` may deploy
  and admin bypass is disabled. The owner later explicitly removed the separate
  required-reviewer step in favor of chat release approval. All six encrypted
  signing secrets are now present; preserve existing rules during secret upload.
- Apple membership/team was verified interactively and `APPLE_TEAM_ID` was saved
  only as an environment variable, not in source.
- The explicit soccer App ID and CoachAI Soccer Positions app record were created.
  A matching **CoachAI App Store Distribution** profile was generated using the
  team's existing valid distribution certificate. The portal reports expiry
  2027-10-27. No existing certificate was revoked or replaced.
- The matching profile was downloaded to restricted storage outside Git. Existing
  local `.p12` and App Store Connect upload `.p8` credentials were reused through
  the secure local helper, with the password entered in a masked terminal.
  Existing encrypted GitHub secrets were not read back or copied.
- Twenty-two local Python/Node guard tests, including a real OpenSSL container
  conversion test using a synthetic certificate, and PowerShell main-only/
  admin-bypass/optional-reviewer tests passed. Plist/icon, shell, Python,
  PowerShell and workflow checks also passed.
  The workflow validator required the documented Xcode 27 preview-label exception.
- The first manual unsigned Xcode validation was requested against
  `16f3c06e0149df68941d072a85ed5cc0e53edfa7`:
  [native validation run](https://github.com/ErrantActions/Soccer-Position-iOS/actions/runs/40792436312).
  Consult its actual result rather than treating local Windows checks as proof.
  It uses the standard `xcode-27` runner and requests no artifacts or signing secrets.
  The first run compiled and linked the app and test bundle, but test execution
  hung and reached the job's 30-minute timeout. Its log includes an Xcode SDK-record
  `invalidDigitCount` diagnostic; it does not establish passing native tests.
  The test harness now selects SDK-compatible runtimes, checks boot readiness and
  tests individual destinations with bounded waits instead of one multi-destination run.
- The owner subsequently requested physical-phone testing instead of waiting for
  simulators. The remaining simulator run was cancelled, and TestFlight now has an
  explicit `run_simulator_tests` input. Use `false` for this upload; a successful
  upload must not be described as passing simulator tests.
- Signed archive, IPA export, TestFlight upload and signing cleanup succeeded in
  [release run 40799030087](https://github.com/ErrantActions/Soccer-Position-iOS/actions/runs/40799030087)
  against commit `c7aaf4f139e8590eaddfa35a78dad4f666df2b23`. The release selected
  build **1**; no simulator tests or release artifacts were requested.
- Apple subsequently reported build `4c54f2ca-a0d6-4640-bead-5a0ec4c0cf80`
  (version **1**) as `VALID`, not expired, with internal state
  `READY_FOR_BETA_TESTING` and external state `READY_FOR_BETA_SUBMISSION`.
  This verifies processing, not Beta App Review or an App Store release.
- No tester groups were assigned at this check. In App Store Connect > CoachAI
  Soccer Positions > TestFlight, create an internal group, add your App Store
  Connect user, and assign build 1. Then accept its invitation and install through
  Apple's TestFlight app. Physical iPhone installation, folding behavior and
  on-device AI still require owner verification.

## UI and Duo redesign validation

The pitch-first redesign, normalized route drawing, role comparison and native
iOS 27.1 fold-region layouts were validated against commit
`fd55e99f17a2c46d378377f987141bfc9aa95dc4` in
[unsigned validation run 40803008819](https://github.com/ErrantActions/Soccer-Position-iOS/actions/runs/40803008819).
All 15 Swift positioning/layout/coordinate tests and existing release guards passed;
Xcode compiled the full app and iOS test bundle successfully. Simulator execution,
artifacts and signing were disabled for that validation. Real folding transitions,
Pencil input and visual appearance on the phone still need device verification.

## Redesigned TestFlight release: build 2

The owner subsequently authorized deployment of main commit
`4ba322d27e0da1f6df3c8e6af0ee2961329e8018`.
[Release run 40803660017](https://github.com/ErrantActions/Soccer-Position-iOS/actions/runs/40803660017)
successfully validated signing, built the signed device archive, exported and
uploaded **build 2**, and cleaned up signing material. Simulator execution was
explicitly disabled; no duplicate validation run or release artifacts were created.

Apple reported build `139ffd68-f7e4-4274-9dff-7739cdc1eb71` as `VALID`, not expired,
with internal state `IN_BETA_TESTING`. Access to build 2 was verified in the app's
existing internal tester group. English TestFlight testing notes describe the
new pitch-first UI, Duo layouts, comparison, route drawing and device checks.
No external group was modified and no public App Store release was submitted.
Existing internal testers can update through the TestFlight app; installation on
the owner's physical phone remains a separate verification.

## Smart routes and fixed pitch update

Source commit `a9882bad637043b5dcbb97a9d7d778126ada2a96` replaces the scrolling
split-mode pitch with a full-pane canvas. All route tools, reset, role selection
and settings live in the right panel; a horizontal tabletop hinge instead uses
top pitch/bottom controls. Expanded Duo layouts no longer require tablet width,
and their settings can scroll independently even at accessibility text sizes.

Routes now have curve/straight modes, screen-space sampling and simplification,
optional nearby ball/player endpoint snapping with a target preview, accidental
gesture rejection, and undo/redo. Finished routes remain normalized; interrupted
strokes are cancelled on resize, rotation or tool changes rather than joined to
stale coordinates. Clearing routes explicitly clears history too.

[Unsigned validation run 40809903744](https://github.com/ErrantActions/Soccer-Position-iOS/actions/runs/40809903744)
passed all 31 Swift tests, 22 release guard tests, PowerShell upload guards and
full app/iOS test bundle compilation. No simulator was launched and no artifacts
were uploaded. This update was not included in TestFlight build 2; the owner has
since granted standing authorization to deploy completed app changes.
Real touch/Pencil and fold interactions
still need device verification.

## Smart-route TestFlight release: build 3

The owner's "always push to TestFlight" preference is persisted in
[project instructions](../.github/copilot-instructions.md). Completed, verified
app updates include dispatching the existing manual release workflow; no separate
per-update approval is needed. This does not add push/PR release triggers or
authorize paid runners, failed builds, public App Store submissions or secret
disclosure. Documentation-only follow-ups do not create another app build.

[Release run 40811224328](https://github.com/ErrantActions/Soccer-Position-iOS/actions/runs/40811224328)
deployed main commit `1a98bf07bdc0ef9879f00efe9a0bdadbac08ec55` as **build 3**.
The signed archive, export, upload and signing cleanup succeeded; simulator
execution was explicitly waived and no release artifacts were uploaded.
Apple reported build `a6399c05-47c2-4e1c-a8da-4be1379a62ff` as `VALID`, not
expired, with internal state `IN_BETA_TESTING`. Build 3 access was verified in
the existing internal tester group, and English testing notes were saved.
No external group was changed.

For an internal group with `hasAccessToAllBuilds=true`, allow automatic assignment
to catch up after Apple processing instead of forcing a manual build assignment.
The group can initially omit a newly valid build and reject an immediate POST
with HTTP 422; re-read its build list and verify membership before reporting
availability. Physical installation remains the owner's separate device check.

## On-device AI Positioning

The optional experimental mode uses Foundation Models guided generation to return
actual normalized coordinates and per-role reasons for LB, LCB, RCB, RB and CDM.
It is not just rewritten coaching text. Its input snapshot includes the ball,
current teammates, three editable opponents, opposition possession and a chosen
4-3-3 or 4-4-2 formation. Only the five-player defensive unit is modeled, not a
complete eleven-player team.

AI output is applied only after finite/field-bound, complete-role, channel,
teammate/opponent clearance, goal-side, back-line order/compactness and central
goal-coverage checks pass. These are geometry safeguards, not proof of correct
soccer tactics. Rejection, unavailability, failures and timeouts are visible; the
instant guide remains explicitly labeled until valid AI output is accepted.
Requests use fresh sessions, are debounced after edits, are cancelled when the
scene changes or app becomes inactive, and time out after 45 seconds. Request
tokens and full scene snapshots prevent old results overwriting newer edits.

The release workflow runs portable Swift validation tests before signing in the
same job; no separate duplicate validation or simulator execution is required.
Native compilation checks Foundation Models types/schema macros. It does not
verify that an on-device model can generate a good plan: enable Apple Intelligence
and finish its model download on supported hardware, then test Analyze, automatic
after-edit analysis, cancellation, all player-edit controls, invalid-output
rejection and labeled fallback on the phone. No cloud API, extra capability,
sensor permission or collected data was introduced.

### AI Positioning release: build 4

[Release run 40813624829](https://github.com/ErrantActions/Soccer-Position-iOS/actions/runs/40813624829)
deployed main commit `219713024fc98935abf3f489a4c751843b31de27` as **build 4**.
All **52 Swift tests** (including 21 AI scene/proposal/freshness tests), 22 release
guard tests and PowerShell signing guards passed. Native signed compilation,
archive/export/upload and signing cleanup succeeded in that same job. Simulator
execution was explicitly waived and no release artifacts were uploaded.

Apple reported build `17bc74b5-5201-4b66-8fde-d973e56351c9` as `VALID`, not expired,
with internal state `IN_BETA_TESTING`. Access was verified in the existing internal
tester group; English testing notes were saved and read back. External groups
were not modified. Update through TestFlight, enable **AI Positioning**, edit the
scene and tap **Analyze positions**. Actual on-device model availability,
generation quality and physical interaction were not exercised in CI.

## Device layouts and encryption declaration

The existing experience now adapts to ordinary phone landscape safe-area widths,
medium iPad windows, narrow multitasking windows and accessibility text. Compact
portrait layouts place role selection above the pitch and fit an aspect-correct
pitch to a height budget; the large introduction is reserved for roomy windows.
Wide layouts keep a fixed pitch and independently scrolling settings, with
fold-specific Duo behavior preserved.

`App/Info.plist` already declares **boolean**
`ITSAppUsesNonExemptEncryption=false`. The current app uses Apple system frameworks
and introduces no custom or third-party encryption implementation. Apple's build
metadata for builds 1-4 was read back as `usesNonExemptEncryption=false`; those
values alone cannot distinguish automatic handling from prior manual answers.

The release now verifies the declaration in both the **actual archived app** and
the **exported IPA** before upload, not just in source. Missing keys, true, numeric
or string substitutes, a missing app plist and corrupt IPA containers fail the
release explicitly. Public logs report only the verified boolean, not app/signing
contents. After upload, verify Apple's stored encryption value and beta state.

Apple documents that including the correct declaration avoids the repeated export
questionnaire. No separate "France" plist boolean or fabricated export approval
code is added. Reassess the declaration and any country-specific documentation if
the app's cryptography changes; do not retain this exemption blindly.

- [Apple: ITSAppUsesNonExemptEncryption](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)
- [Apple: export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)

### Device and compliance release: build 5

[Release run 40817495920](https://github.com/ErrantActions/Soccer-Position-iOS/actions/runs/40817495920)
deployed main commit `e5f3797e16a399cc214b1db4e86efd1760ce3808` as **build 5**.
All **64 Swift tests**, including the 12 new device-layout/fit tests, and **29
release/compliance guard tests** passed. Native archive/export/upload and signing
cleanup succeeded; simulator execution was waived and no artifacts were uploaded.

The actual archived app and exported IPA both passed the exact boolean
`ITSAppUsesNonExemptEncryption=false` checks. After processing, Apple reported
build `785f9a1e-c132-43da-91f9-c25620b99507` as `VALID`, not expired, with
`usesNonExemptEncryption=false` and internal state `IN_BETA_TESTING`.
No compliance metadata PATCH or questionnaire answers were submitted by the
agent for this build. Access was verified in the existing internal group and
English testing notes were saved/read back. External groups and France
availability were not changed.

This verifies the declaration's source-to-upload path and current Apple handling;
the original prompts on older builds were not reproduced. Visual appearance,
rotation, iPad window resizing and accessibility behavior still require physical
device verification.

## Dedicated Duo control presentation

Duo and ordinary devices now choose separate control presentations. An active
book or tabletop division always selects Duo controls, even if the separate
inactive-region query does not identify the display. A flat inner display uses
Apple's inactive division information and keeps a two-pane desk whenever both
panes can be at least 240 points wide.

Duo restores its route-tools, AI-positioning, then role-selector ordering and
22-point panel spacing. Ordinary devices retain role-first controls and tighter
narrow-panel spacing. This policy is shared by the pure layout model and actual
SwiftUI control rendering, rather than duplicated device-name checks.
The pitch remains fixed in its own pane; a horizontal tabletop hinge still uses
the other pane below the pitch. Closed or genuinely narrow windows retain compact
controls instead of forcing unusable columns. Verify the flat/folded transitions
on the phone; compilation and geometry tests do not establish physical behavior.

### Duo controls release: build 6

[Release run 40818947225](https://github.com/ErrantActions/Soccer-Position-iOS/actions/runs/40818947225)
deployed commit `d55565d1bc5d60cecdd1b1b7bad4e719ebbfa54c` as **build 6**.
All **70 Swift tests**, including six new Duo-vs-ordinary control-presentation
regressions, and **29 release/compliance guards** passed. Native signed
archive/export/upload and cleanup succeeded without simulator execution or
uploaded artifacts. The actual archive and IPA retained the exempt-encryption
boolean.

Apple reported build `9d9ff2c5-3076-4150-a2e4-6d590c1cde86` as `VALID`, not
expired, with `usesNonExemptEncryption=false` and internal state
`IN_BETA_TESTING`. Existing internal-group access and English testing notes were
verified. No external group was changed; physical Duo behavior remains to check
through TestFlight.
