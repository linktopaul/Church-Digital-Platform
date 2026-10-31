# Repository guidance

## Codex Code Review Rules

Apply these checks to pull requests that touch the relevant code. Report a finding only when the diff creates or leaves a concrete risk; cite the changed path and explain the impact. Avoid speculative findings and do not repeat an existing finding.

### Tenant isolation and authorization
- Church-owned records and queries must remain scoped to the authenticated church tenant. Never trust a client-supplied tenant ID, role, or member ID as proof of access; derive identity and permissions from validated server-side claims and enforce authorization on every endpoint.
- Check private-group, prayer, profile, and other sensitive-data flows for unauthorized access paths, including join/create/update operations and indirect access through related records.
- Preserve tests that demonstrate role boundaries and cross-tenant isolation. Flag a change that weakens these boundaries or omits a necessary regression test.

### Privacy and member data
- Member and family data must follow explicit visibility rules and default to private when visibility is unspecified. Return only fields the caller is permitted to see, including in nested responses, lists, and search results.
- Check that names, prayer content, contact details, and other private data are not exposed through logs, notifications, or overly broad API responses.

### Mobile/API integration
- For a mobile feature that adds or changes backend endpoints, verify that the app path uses the authenticated shared API client and persists user actions through those endpoints. Sample/demo data and local-only mutations are acceptable in tests or explicitly marked previews, but must not silently stand in for production behavior.
- Credentials must use platform-secure storage; widgets should not make unauthenticated direct requests or invent role/tenant headers. Flag concrete gaps between UI actions and the backend contract, with the affected user flow and data-loss/privacy impact.
