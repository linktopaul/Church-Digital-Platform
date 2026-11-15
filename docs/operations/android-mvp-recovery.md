# Android pilot delivery recovery

The roadmap architect reconciles module issues on roadmap changes, manual runs from main, and weekly. Missing modules become planning issues. A reviewed task entry, an open issue, accepted dependencies, and available ownership and capacity govern implementation dispatch.

Run Delivery coordinator with its default dry-run input and inspect `delivery-status`. Review held leases against session and PR evidence. Closed historical issues can still hold leases. Record acceptance only with verified evidence or use the documented handoff procedure after stopping the old session. Treat the artifact's capacity counts as repository limits. Vendor quota is unknown. Jules label application requests a session, and the owner verifies acknowledgement. Codex and Antigravity work require a manual handoff with recorded branch, scope, and owner.

## P0 · Pilot sign-in and announcements

- **Codex or operator, device and environment.** Use a synthetic pilot tenant to verify Android authorization code with PKCE, signed-in session restore, token refresh, and logout against the deployed pilot API. Own device validation evidence and the pilot runbook. Route auth or deployment defects separately before changing shared app files.
- **Jules, issue #66 feed integration.** Own Home, the announcement API service, and feed tests in one branch. Use the existing authenticated client and the composer already merged in #68. Verify loading, empty, retry, refresh, and role visibility. Confirm acknowledgement before recording active work. Register the reviewed task and reconcile historical leases before enabling automated dispatch.
- **Antigravity, independent acceptance.** Review the exact head and verify the composer/feed integration using the Android pilot environment as soon as the candidate is available. Record proof that Pastor/Admin can publish, a same-church member can read after relaunch, direct member publishing returns 403, and another church cannot read the post. Review work owns evidence and review only. Route fixes to the owning branch.

## P1 · Android release candidate

Run Flutter analysis, widget/unit tests and Android APK build, .NET API tests, and the existing current-head review gate before merge. Smoke-test the installable candidate against pilot services for announcements, profile, confidential prayer, Fellowship, and worship persistence. Verify pilot provisioning and recovery evidence in parallel using isolated synthetic data. Record the commit, build, device, and acceptance evidence on the pilot tracker. File any failing journey with its own scope and dependencies. Release only after the candidate passes the device checks and the operator approves pilot rollout.
