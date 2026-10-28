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

Repository admins, the selected reviewer, workflow changes, Xcode build scripts,
Homebrew tools and code executed in approved jobs must be trusted. Environment
approval is not a sandbox: review the **exact commit** before approving. Changes
to workflows or signing helpers can exfiltrate environment secrets after approval.
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
4. `app-store` environment: required reviewer `ErrantActions`; custom branch policy
   permitting **only the branch `main`**, no tag policies. Disable admin bypass
   before uploading signing secrets. The helper fails closed if bypass status
   cannot be verified as disabled. A sole owner may initiate and explicitly approve
   their own deployment, so prevent-self-review is not enabled.
5. Upload secrets only after required-reviewer and branch protection are confirmed.
   Required reviewers were unavailable on the account's private staging plan;
   do not remove approval requirements as a workaround or change billing limits.
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
Marketing version currently `1.0` in [project.yml](../project.yml); confirm this
against the app record before the first release. No Frigate identifiers or
capabilities are reused. The Apple team ID is an environment variable, not source.

Owner prerequisites:

1. Active Apple Developer membership and accepted agreements.
2. Explicit registered App ID for the exact bundle ID, no extra capabilities.
3. An App Store Connect iOS app record using that App ID and an available name.
   Confirm whether the proposed CoachAI app already exists.
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
The helper verifies public/non-fork status, sole-owner approval, disabled admin
bypass and main-only rules
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

The upload key authenticates to App Store Connect, resolves the exact bundle ID,
and paginates **all** existing builds. The next integer build number exceeds every
uploaded version and the manual minimum. It does not depend on resettable GitHub
run numbers. Unsupported existing formats, API errors and range exhaustion fail
closed. This implementation permits integer build numbers 1 through 9999.
Upload workflows are serialized; uploads from outside this repository must also
be coordinated to avoid a race between preflight and upload.

After preflight: generate the actual CoachAI Xcode project, test both simulator
destinations, archive for a physical device, export, and upload via `altool`.
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
   confirm. This compiles/tests; it does not sign or upload.
3. For a release candidate: Actions > TestFlight > main > confirm upload.
   **Do not run a duplicate simulator workflow first**; TestFlight runs those tests.
4. Inspect the exact commit, then explicitly approve the `app-store` deployment.
5. Successful job upload means Apple accepted the upload request, not that
   processing finished. Check App Store Connect > CoachAI > TestFlight.
6. Resolve export compliance and processing errors; assign internal testers.
   External testers may require Beta App Review.
7. Install via Apple's TestFlight app on the phone and verify controls,
   compact/unfolded transitions, rotation, accessibility and on-device explanations.
   This is a separate manual verification, not implied by a green Actions run.

No public App Store release is submitted by these workflows.

## Initial handoff status (2026-10-28)

- Independent private staging repository created; public transition is awaiting
  explicit owner approval after the new-source audit.
- Default Actions token verified read-only, with PR approval disabled.
- `app-store` exists but has **no effective required-reviewer or branch rules**:
  GitHub rejected required reviewers on the private staging plan. No signing
  secrets were uploaded. Secret scanning/push protection were also unavailable
  for private staging. These must be configured and verified after approved
  publication, before any credential upload.
- Apple membership/team was verified interactively, but the team ID was not put
  in source. No CoachAI app appeared in the signed-in account's visible app list.
  App registration, profile selection and credential upload remain owner actions.
- Local Python/Node guard tests, plist checks, generated-icon checks, shell syntax,
  PowerShell parsing and workflow validation were performed. The workflow validator
  required the documented Xcode 27 preview-label exception.
- No Xcode compilation, simulator execution, signed archive, TestFlight upload,
  Apple processing or physical iPhone installation has been verified.
