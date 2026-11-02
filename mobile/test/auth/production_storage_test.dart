import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/auth/auth_session.dart';
import 'package:church_digital_platform_mobile/auth/oidc_configuration.dart';
import 'package:church_digital_platform_mobile/auth/platform_secure_token_storage.dart';

OidcConfiguration config({String issuer = 'https://issuer.example.test'}) => OidcConfiguration(
  issuer: issuer, clientId: 'fictional-client', redirectUri: 'test.church:/callback',
  scopes: ['openid', 'offline_access', 'fictional-api'], memberIdClaim: 'member_id',
  tenantIdClaim: 'tenant_id', rolesClaim: 'roles',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final values = <String, String>{};
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    values.clear();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        final args = call.arguments as Map;
        final key = args['key'] as String;
        switch (call.method) {
          case 'write': values[key] = args['value'] as String; return null;
          case 'read': return values[key];
          case 'delete': values.remove(key); return null;
          default: throw StateError('Unexpected storage method');
        }
      });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  AuthSession session({bool expired = false}) => AuthSession(
    accessToken: 'fictional-token', refreshToken: 'fictional-refresh', userId: 'member',
    tenantId: 'tenant', roles: ['Member'],
    expiresAt: DateTime.now().add(Duration(hours: expired ? -1 : 1)),
  );

  test('native storage roundtrip, issuer isolation and scoped deletion', () async {
    final first = PlatformSecureTokenStorage(configuration: config());
    final second = PlatformSecureTokenStorage(configuration: config(issuer: 'https://other.example.test'));
    final original = session();
    await first.saveSession(original);
    expect(await first.getSession(), original);
    expect(await first.hasValidSession(), isTrue);
    expect(await second.getSession(), isNull);
    await second.saveSession(original);
    await first.clearSession();
    expect(await first.getSession(), isNull);
    expect(await second.getSession(), original);
    expect(calls.any((c) => c.method == 'deleteAll'), isFalse);
  });
  test('Android read errors propagate without reset or deletion', () async {
    final storage = PlatformSecureTokenStorage(configuration: config());
    await storage.saveSession(session());
    final options = (calls.single.arguments as Map)['options'] as Map;
    expect(options['resetOnError'], 'false');
    final failure = PlatformException(code: 'locked');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async { throw failure; });
    await expectLater(storage.getSession(), throwsA(isA<PlatformException>()));
    expect(values, isNotEmpty);
  });
  test('iOS credentials are device-local, unlocked-only and not synchronized', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await PlatformSecureTokenStorage(configuration: config()).saveSession(session());
    final options = (calls.single.arguments as Map)['options'] as Map;
    expect(options['accessibility'], 'unlocked_this_device');
    expect(options['synchronizable'], 'false');
  });
  test('expired credentials remain available for refresh', () async {
    final storage = PlatformSecureTokenStorage(configuration: config());
    final original = session(expired: true);
    await storage.saveSession(original);
    expect(await storage.hasValidSession(), isFalse);
    expect(await storage.getSession(), original);
  });
  test('malformed records fail closed without deleting other credentials', () async {
    final storage = PlatformSecureTokenStorage(configuration: config());
    await storage.saveSession(session());
    values[values.keys.single] = '{}';
    await expectLater(storage.getSession(), throwsFormatException);
    expect(values.values.single, '{}');
  });
  test('unsupported platforms never silently use a browser or memory store', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await expectLater(PlatformSecureTokenStorage(configuration: config()).getSession(), throwsUnsupportedError);
    expect(calls, isEmpty);
  });
}
