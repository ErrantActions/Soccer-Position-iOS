# CoachAI delivery preferences

- The owner has standing authorization to deploy completed, verified app changes
  to TestFlight. Include deployment in the task; do not stop at "ready to deploy"
  or request a separate approval each time. Respect any later instruction to pause.
- Push the app changes to `main`, then dispatch the existing manual
  `testflight.yml` workflow with `confirm_upload=true` and
  `run_simulator_tests=false`. Do not add automatic push/PR release triggers.
- Keep signing preflight, safe build-number selection, main-only deployment,
  read-only Actions permissions and signing cleanup intact. Do not deploy failed
  checks, use paid/larger runners, or publish signing material.
- Do not duplicate simulator validation for release candidates. Use focused tests
  as needed; the owner tests physical-device behavior through TestFlight.
- Verify the upload, Apple processing and existing internal tester-group access
  before saying a build is available. Report blockers honestly; never claim phone
  installation, simulator test execution or an App Store release.
- Documentation-only or instruction-only changes do not need a new build unless
  one is requested or a previously completed app update is awaiting deployment.
- Follow [the TestFlight runbook](../docs/TESTFLIGHT.md) for credentials and release
  details. Never request passwords or private-key contents in chat.
