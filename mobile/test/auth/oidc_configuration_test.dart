import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/auth/oidc_configuration.dart';

void main() {
  OidcConfiguration config({String issuer = 'https://identity.example.test/church',
    String client = 'fictional', String redirect = 'test.church:/callback',
    List<String> scopes = const ['openid', 'offline_access', 'api'], String tenantClaim = 'tenant_id',
  }) => OidcConfiguration(issuer: issuer, clientId: client, redirectUri: redirect,
    scopes: scopes, memberIdClaim: 'member_id', tenantIdClaim: tenantClaim, rolesClaim: 'roles');

  test('preserves configured issuer path and derives only the standard discovery path', () {
    final value = config();
    expect(value.discoveryUri.toString(), 'https://identity.example.test/church/.well-known/openid-configuration');
    expect(value.clientId, 'fictional');
    expect(value.redirectUri.toString(), 'test.church:/callback');
    expect(() => value.scopes.add('extra'), throwsUnsupportedError);
  });
  test('missing operator configuration has no production defaults', () {
    expect(OidcConfiguration.fromEnvironment, throwsArgumentError);
    expect(() => config(client: ''), throwsArgumentError);
    expect(() => config(tenantClaim: ''), throwsArgumentError);
  });
  for (final issuer in ['', 'http://issuer.test', 'https://user:pass@issuer.test', 'https://issuer.test?q=1', 'https://issuer.test/#x']) {
    test('rejects unsafe issuer $issuer', () => expect(() => config(issuer: issuer), throwsArgumentError));
  }
  for (final redirect in ['', '/callback', 'http://app.test/callback', 'javascript:callback', 'test.church:/callback#fragment']) {
    test('rejects invalid redirect $redirect', () => expect(() => config(redirect: redirect), throwsArgumentError));
  }
  test('requires explicit OIDC/refresh scopes and rejects malformed scope values', () {
    expect(() => config(scopes: ['openid']), throwsArgumentError);
    expect(() => config(scopes: ['openid', 'offline_access', 'two scopes']), throwsArgumentError);
  });
}
