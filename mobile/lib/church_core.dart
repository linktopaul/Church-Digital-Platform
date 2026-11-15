/// Church Digital Platform — Core Engine & Architecture Framework (`church_core`).
///
/// Exports all foundational auth, security, domain models, network clients,
/// and church theming configuration contracts.
///
/// Dedicated church applications in separate repositories can import this library
/// directly to inherit the battle-tested backend contracts, UPI almsgiving,
/// role-gating, and session management while maintaining full freedom over their
/// dedicated UI/UX layouts.
library church_core;

// Configuration & Themes
export 'config/church_profile_config.dart';
export 'config/church_theme_config.dart';
export 'theme/app_theme.dart';

// Authentication & Security Architecture
export 'auth/auth_provider.dart';
export 'auth/auth_session.dart';
export 'auth/auth_session_manager.dart';
export 'auth/oidc_configuration.dart';
export 'auth/openiddict_auth_provider.dart';
export 'auth/platform_secure_token_storage.dart';
export 'auth/secure_token_storage.dart';

// Network & Tenant Isolation Guards
export 'network/api_exceptions.dart';
export 'network/authenticated_http_client.dart';

// Domain Models
export 'models/announcement_models.dart';
export 'models/celebration_models.dart';
export 'models/fellowship_models.dart';
export 'models/member_models.dart';
export 'models/offering_models.dart';
export 'models/prayer_models.dart';
export 'models/worship_models.dart';

// Service API Clients
export 'services/announcement_api_client.dart';
export 'services/celebration_api_client.dart';
export 'services/fellowship_api_client.dart';
export 'services/member_api_client.dart';
export 'services/offering_api_client.dart';
export 'services/prayer_api_client.dart';
export 'services/worship_api_client.dart';
