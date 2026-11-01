# Native authentication adapter integration

Status: concrete adapters are available on #50/#25. The application is not wired yet.
#24 owns OpenIddict/backend registration; #51 owns navigation/Fellowship wiring.
No issuer, client registration or endpoint deployment is supplied by this code.

## Required non-secret configuration

Construct `OidcConfiguration` from runtime configuration, or supply these build
values to `OidcConfiguration.fromEnvironment()` with `--dart-define`:

- `CHURCH_AUTH_ISSUER`: exact HTTPS issuer, including any path/trailing slash.
- `CHURCH_AUTH_CLIENT_ID`: registered **public native** client; no client secret.
- `CHURCH_AUTH_REDIRECT_URI`: exact registered redirect, also configured in each
  native runner. No default scheme or application identifier is chosen here.
- `CHURCH_AUTH_SCOPES`: space-separated registered scopes, including `openid`
  and `offline_access`, plus the confirmed API/claims scopes from #24.
- `CHURCH_AUTH_MEMBER_ID_CLAIM`, `CHURCH_AUTH_TENANT_ID_CLAIM`,
  `CHURCH_AUTH_ROLES_CLAIM`: exact confirmed UserInfo keys. Member and tenant IDs
  must come from authenticated server data; no locally invented role/tenant headers.

Missing configuration fails closed. Discovery uses the standard issuer-relative
`/.well-known/openid-configuration` document, not guessed OpenIddict endpoint paths.

## Native provider

Construct `OpenIddictAuthProvider(configuration: config, storage: storage)` with
**the same** `PlatformSecureTokenStorage` supplied to `AuthSessionManager`.
The future navigation owner should call `provider.authorizeAndSignIn(manager)`:
it binds the browser result to the manager lifecycle, then uses the existing
code-exchange interface. The advanced split flow `authorize()` returns AppAuth's
code/verifier/nonce result; its matching exchange is single-use and expires after
five minutes. Do not reconstruct callbacks or discard the generated nonce.

AppAuth owns browser authorization, PKCE/state/nonce generation and native token
processing. Discovery requires an exact configured issuer, advertised S256 and
HTTPS same-origin authorization/token/UserInfo/revocation endpoints. Redirects
on adapter HTTP requests are rejected. Missing capabilities fail closed and need
#24 contract resolution; cross-origin endpoints are not silently trusted.

Initial identity comes from bearer-authenticated UserInfo, whose standard `sub`
is bound to the native exchange's ID-token subject. Configured member/tenant
claims must be nonempty strings and roles a string array. Claims are UI/session
snapshots only; backend authorization remains authoritative on every request.
Refresh retains that snapshot and the old refresh token if rotation omits one;
it accepts a replacement refresh token when supplied. It deliberately performs
no UserInfo HTTP call after rotation, so temporary UserInfo outages cannot lose
the replacement credential. Future identity/profile updates must be coordinated
with #24 rather than inventing an unconfirmed DTO. Only native OAuth
`invalid_grant` becomes `TerminalAuthException`; transport/server/client-config
errors remain retryable errors. The manager owns persistence/clearing, so stale
provider work cannot write credentials. `close()` releases the HTTP client.

Local sign-out clears credentials even if discovered token revocation fails; it
does not imply the browser's SSO cookie was cleared. Native end-session/logout
UI is a separate contract and is not guessed from a revocation URL.

## Storage

`PlatformSecureTokenStorage(configuration: config)` persists one session record
using `flutter_secure_storage`. It scopes records by issuer/client/redirect and
only deletes that record at sign-out. Android uses the library's default
Keystore-backed encrypted storage with automatic error reset disabled. iOS uses
unlocked-only, device-local, non-synchronizing Keychain storage. Errors propagate;
there is no SharedPreferences, browser-storage or in-memory fallback.

Call `WidgetsFlutterBinding.ensureInitialized()` before using native plugins.
This adapter supports Android/iOS only. Expired credentials remain readable so
the session manager can retry refresh. Storage permissions/lock failures are not
interpreted as an absent session.

## Native runner blockers and required setup

The repository currently has **no `mobile/android` or `mobile/ios` runner**.
Partial manifests alone would not create buildable native applications. Runner
creation requires the agreed application/bundle identifiers and redirect scheme;
these have not been inferred from test fixtures or repository names.

When those values are confirmed, the native/dependency owner must:

- Generate/review native runners with the supported Flutter toolchain.
- Android: meet the plugin minimum SDKs, enable AndroidX, configure
  `appAuthRedirectScheme` in `defaultConfig.manifestPlaceholders` (preserving
  existing placeholders), or use the documented exact redirect intent filter.
  Disable credential auto-backup/device transfer as documented by secure storage.
  Keep HTTPS/TLS verification enabled; do not add cleartext exceptions.
- iOS: register the confirmed scheme in `CFBundleURLTypes`, configure Keychain
  capability/entitlements and signing for the actual app identifier. Audit native
  URL caching so authentication responses are not retained in `cache.db`.
- Verify release builds on Android and iOS, browser return/cancellation, PKCE,
  cold start, refresh rotation/rejection, sign-out and actual encrypted storage.
  Dart method-channel fixtures do not establish native/device behavior or
  hardware-backed availability on every device.

Dependencies: `flutter_appauth` 12.0.0 is the maintained native AppAuth bridge
compatible with the published Flutter 3.41/Dart 3.11 setup (13 requires a newer
SDK); `flutter_secure_storage` 11.2.0 supplies the native credential plugin.
The local environment has no Flutter SDK and its proxy is unreachable. CI uses `pub get`; `pubspec.lock` was captured from its successful resolver run
41323429022, then committed unchanged. The temporary capture diagnostic is removed.
Local validation against the published Flutter 3.41 toolchain remains blocked.

Official references consulted:

- https://pub.dev/packages/flutter_appauth/versions/12.0.0
- https://github.com/MaikuB/flutter_appauth/tree/flutter_appauth-v12.0.0/flutter_appauth
- https://pub.dev/packages/flutter_secure_storage/versions/11.2.0
- https://github.com/juliansteenbakker/flutter_secure_storage/tree/develop/flutter_secure_storage

## Outstanding acceptance

Await #24's precise issuer/audience, public client/redirect registration, scopes,
UserInfo claims and refresh/revocation contract; await #51's explicit navigation
boundary agreement. Integrate one manager/provider/storage/shared-client instance
only after those contracts are agreed. Keep #25/#18/#21 open until real wiring
and end-to-end acceptance, independent review and native checks are complete.
