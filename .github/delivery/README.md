# Delivery coordinator

## What runs
The trusted-main GitHub Actions coordinator plans every 15 minutes (GitHub schedules may be delayed), on relevant metadata changes, or manual dispatch. It executes no PR code and never merges. PR regression tests are separate and have no dispatch credential. Routine scheduling uses deterministic rules, not billable model polling.

`plan.json` is the reviewed scope/ownership register. Only tasks opted in there can be dispatched. Existing confirmed sessions are adopted as active leases; adoption is not acceptance. Current capacity: five total / four Jules / one Codex, including blocked leases. No automatic expiry or reassignment. File directories end with /; exact files otherwise. New work with overlapping ownership is blocked.

## One authoritative state
For each registered issue, the latest repository-owner-authored state comment overrides the bootstrap lease:
```
<!-- delivery-state:v1 {"issue":24,"agent":"jules","status":"accepted","evidence":["https://github.com/linktopaul/Church-Digital-Platform/pull/52"]} -->
```
Do not copy this example until the actual acceptance criteria are demonstrated. Closed issues, merged documentation, green tests, agent claims and elapsed time alone are not acceptance. Only an accountable owner records acceptance after examining current-head behavior/tests and review. The evidence URL is an audit reference, not an automatic assertion that the referenced PR is accepted. Append records; do not edit history. Valid states: active, dispatched, blocked, handoff, accepted. Invalid owner records fail closed.

An operator handoff must stop/archive the old agent, preserve its commits, record handoff, update the reviewed task owner/branch and reconcile old state comments. Handoff never redispatches automatically. Never remove a lease merely to clear capacity while work is still active. A failed dispatch retains its lease for inspection: this prevents retries from starting duplicate sessions.

## Dispatch adapters
Jules: record dispatch intent first, then apply ready-for-dev/jules using the existing repository-owner token. A label request is NOT proof of a running session. Confirm the Jules acknowledgement/session and append an active record. The token needs Issues write in addition to whatever existing automation uses; no new secret is created here. Token/permission failures fail visibly and retain ownership.

Codex: unattended dispatch is DISABLED. The current GitHub coding mention returns no-environment even after the modern environment was published. Existing manual Codex session stays active and retains files/capacity. Queued Codex work is reported unavailable; no repeated coding mentions or fake session records. Enable only after a supported dispatch/acknowledgement path is demonstrated. No paid API or credits are purchased.

Existing PR/dispatch labels and leases suppress duplicates. Bounded feedback tags only Jules-owned existing PRs with unsuccessful current-head checks, at most once per head and no recent owner reminder in 24 hours. It instructs continuation, not a fresh task. Codex receives no unattended coding requests.

## Review and delivery
Native .NET/Flutter/Review acceptance protection remains unchanged. Parent PBIs are not closed by coordinator. PR title/body closing references still require review; this scheduler cannot prevent a human or another app from putting an erroneous closing keyword in a PR. Status artifact distinguishes leases, dispatch requests, blockers and errors; it does not claim pilot completion.

Legacy sequential PBI dispatch is retired. Legacy supervisor retains branch/status reconciliation and independent review requests but no longer sends implementation instructions. This reduces duplicate assignment channels. External Jules CI Fixer/settings can still generate competing pushes: stop/archive old sessions at handoff and inspect new commit ownership. The registry is a coordination control, not a GitHub enforcement mechanism against another installed app or an administrator. No branch restriction or credential change is performed.

## Operator workflow
1. Add a small task issue with acceptance tests and exclusive paths.
2. Add its task entry in a reviewed plan PR, including dependencies and branch. Parents are not dispatch units.
3. Dry-run manual dispatch; inspect the delivery-status artifact and job summary.
4. After merging the coordinator, real scheduled/event runs dispatch only eligible Jules tasks. No manual workflow approval bypass.
5. Confirm acknowledgement, inspect code/tests/review, then append accepted evidence when justified.
6. If blocked, preserve the lease, document the exact decision needed, and continue independent work.

Unit tests: `node --test .github/delivery/*.test.cjs`. Plan validation and current assignment adoption run in CI. No production data, deployment, credentials, database restore or native runtime verification is authorized by this workflow.
