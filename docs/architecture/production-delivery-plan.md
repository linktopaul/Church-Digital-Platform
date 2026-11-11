# Production delivery plan

The release target is a multi-church platform with a complete Android member app, an administration portal, and a supported production service. The roadmap's module numbers remain stable for issue references. Increment order controls dependencies and release risk, while the scope below defines the production target.

## Baseline at 6c767af

This is a source inventory. End-to-end behavior, production deployment, and store distribution require separate evidence.

| Area | Present on main | Next production gap |
| --- | --- | --- |
| Identity and tenant | Auth endpoints, native OIDC adapter, secure storage, shared authenticated HTTP client | Verify Android refresh and logout against deployed services, then exercise invitations, role changes, and tenant isolation using two churches. |
| Announcements | Backend read/publish endpoints and merged Flutter composer | #66 Home feed and authenticated publish integration. Verify role denial, tenant isolation, and refresh or relaunch. Add administration lifecycle and delivery preferences after the shared contract is agreed. |
| Prayer and Fellowship | Backend routes, Flutter clients and screens | Verify private visibility, persisted mutations, group membership and leadership controls on real services. |
| Worship | Song and setlist API, Flutter screen with direct HTTP calls | Move worship onto the authenticated client and verify persisted song and setlist workflows and editor permissions. |
| Member and celebrations | Backend endpoints and Flutter clients and screens | Verify family visibility and role changes. Deliver consent, scheduling, and delivery history for celebration notifications. |
| Offerings | UPI ledger endpoints and Flutter offering client and screen | Verify contribution status and receipts. Deliver finance reconciliation and audited corrections with role separation. |
| Administration | Announcement web components | Define portal shell, tenant onboarding, invitations, directory and ministry administration, publishing, finance, and audit history. |
| Operations | Flutter CI, backup/restore verification, and pilot provisioning/runbook | Verify production rollout and rollback, signing and distribution, observability, incident response, and restore against documented objectives. |

## First parallel assignments

- **Member app — existing Jules session on #66.** Home, announcement API client, and focused Flutter tests. Preserve the merged composer. Reconcile session and branch before handoff. Start worship on a separate branch only with exclusive worship screen, model, client, and test ownership.
- **Administration — open owner.** Start with the authenticated portal shell and read-only announcement listing. Own frontend files. Use the existing API contract. Propose onboarding, invitation, role, and audit endpoint changes for review before touching backend startup or shared identity files.
- **Platform and release — Codex or release operator.** Own Android release verification and operational evidence. Exercise APK install, sign-in, refresh, logout, and two-church isolation. Scope any fixes in shared authentication, startup, migrations, or Android signing separately before implementation.
- **Independent review — Antigravity after CLI verification.** Review the exact candidate commit, report findings and tests, and return implementation changes to their owners. Record Android device acceptance separately.

## Delivery order and gates

1. Close the announcements journey and establish a repeatable Android release build and two-church verification environment. Build the portal shell in parallel.
2. Deliver onboarding and roles, then close prayer, Fellowship, worship, profiles, celebrations, and offerings as complete member/admin journeys. Agree shared contracts before assigning work that changes them.
3. Complete production operations and release evidence. Document deployment and rollback, migration recovery, signing ownership, backup and restore objectives, alerts, data retention, support ownership, and provider decisions.

Every change needs a named owner, exclusive paths, and an acceptance test. Require the relevant Flutter, .NET, and portal checks and independent review on the exact PR head. Record two-tenant authorization evidence for sensitive workflows. Release evidence includes a signed Android candidate tested on a device or emulator, portal access and role checks, and a deployment and restore rehearsal. GitHub records ownership and evidence. Agent dispatch automation may advance independently of product delivery.
