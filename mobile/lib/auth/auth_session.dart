import 'dart:convert';

/// Represents an authenticated user session in the mobile application.
///
/// Contains cryptographically signed tokens, tenant identifiers, and server-validated
/// claims. Under no circumstances should client screens construct or forge
/// tenant IDs or user roles.
class AuthSession {
  final String accessToken;
  final String? refreshToken;
  final String userId;
  final String tenantId;
  final List<String> roles;
  final DateTime expiresAt;
  final String? email;
  final String? displayName;

  const AuthSession({
    required this.accessToken,
    this.refreshToken,
    required this.userId,
    required this.tenantId,
    required this.roles,
    required this.expiresAt,
    this.email,
    this.displayName,
  });

  /// Indicates whether the access token has expired according to client time.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Helper to check if the session possesses a server-assigned role.
  bool hasRole(String role) => roles.contains(role);

  /// Checks if token is near expiration within a given threshold duration.
  bool willExpireWithin(Duration duration) {
    return DateTime.now().add(duration).isAfter(expiresAt);
  }

  AuthSession copyWith({
    String? accessToken,
    String? refreshToken,
    String? userId,
    String? tenantId,
    List<String>? roles,
    DateTime? expiresAt,
    String? email,
    String? displayName,
  }) {
    return AuthSession(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      userId: userId ?? this.userId,
      tenantId: tenantId ?? this.tenantId,
      roles: roles ?? this.roles,
      expiresAt: expiresAt ?? this.expiresAt,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'userId': userId,
      'tenantId': tenantId,
      'roles': roles,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'email': email,
      'displayName': displayName,
    };
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String?,
      userId: json['userId'] as String? ?? '',
      tenantId: json['tenantId'] as String? ?? '',
      roles: (json['roles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
    );
  }

  String serialize() => jsonEncode(toJson());

  factory AuthSession.deserialize(String source) {
    return AuthSession.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthSession &&
        other.accessToken == accessToken &&
        other.refreshToken == refreshToken &&
        other.userId == userId &&
        other.tenantId == tenantId &&
        _listEquals(other.roles, roles) &&
        other.expiresAt.isAtSameMomentAs(expiresAt) &&
        other.email == email &&
        other.displayName == displayName;
  }

  @override
  int get hashCode {
    return Object.hash(
      accessToken,
      refreshToken,
      userId,
      tenantId,
      Object.hashAll(roles),
      expiresAt,
      email,
      displayName,
    );
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
