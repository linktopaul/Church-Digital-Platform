import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:church_digital_platform_mobile/auth/auth_provider.dart';
import 'package:church_digital_platform_mobile/auth/auth_session.dart';
import 'package:church_digital_platform_mobile/auth/auth_session_manager.dart';
import 'package:church_digital_platform_mobile/network/authenticated_http_client.dart';
import 'package:church_digital_platform_mobile/network/api_exceptions.dart';
import '../support/mock_auth_provider.dart';
import '../support/in_memory_secure_token_storage.dart';

AuthSession session(String id) => AuthSession(
  accessToken: id, refreshToken: 'refresh-$id', userId: id, tenantId: 'tenant-$id',
  roles: const ['Member'], expiresAt: DateTime.now().add(const Duration(hours: 1)),
);

class StreamingClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  StreamingClient(this.handler);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => handler(request);
}

class RefreshProvider extends MockAuthProvider {
  final entered = Completer<void>();
  final result = Completer<AuthSession>();
  @override
  Future<AuthSession> refreshSession({required String refreshToken}) {
    entered.complete();
    return result.future;
  }
}

void main() {
  for (final failure in [false, true]) {
    test('401 stream canceled before refresh ${failure ? 'failure' : 'retry'}', () async {
      var canceled = false;
      var sends = 0;
      final provider = RefreshProvider();
      final manager = AuthSessionManager(provider: provider, storage: InMemorySecureTokenStorage());
      addTearDown(manager.dispose);
      await manager.setSession(session('A'));
      final body = StreamController<List<int>>(onCancel: () { canceled = true; });
      addTearDown(() { body.close(); });
      final client = AuthenticatedHttpClient(authService: manager, inner: StreamingClient((request) async {
        sends++;
        if (sends == 1) return http.StreamedResponse(body.stream, 401);
        expect(canceled, isTrue);
        return http.StreamedResponse(Stream.value(<int>[]), 200);
      }));
      final pending = client.get(Uri.parse('https://example.test/api'));
      final check = failure
        ? expectLater(pending, throwsA(isA<AuthExpiredException>()))
        : expectLater(pending, completion(isA<http.Response>().having((r) => r.statusCode, 'status', 200)));
      await provider.entered.future;
      expect(canceled, isTrue);
      if (failure) {
        provider.result.completeError(const TerminalAuthException());
      } else {
        provider.result.complete(session('A').copyWith(accessToken: 'new'));
      }
      await check;
      expect(sends, failure ? 1 : 2);
    });
  }

  for (final signOut in [false, true]) {
    test('delayed POST 401 after ${signOut ? 'signout' : 'account switch'} is never replayed', () async {
      final provider = MockAuthProvider();
      final manager = AuthSessionManager(provider: provider, storage: InMemorySecureTokenStorage());
      addTearDown(manager.dispose);
      await manager.setSession(session('A'));
      final sent = Completer<void>();
      final response = Completer<http.StreamedResponse>();
      var sends = 0;
      var canceled = false;
      final body = StreamController<List<int>>(onCancel: () { canceled = true; });
      addTearDown(() { body.close(); });
      final client = AuthenticatedHttpClient(authService: manager, inner: StreamingClient((request) {
        sends++;
        expect(request.headers['Authorization'], 'Bearer A');
        sent.complete();
        return response.future;
      }));
      final pending = client.post(Uri.parse('https://example.test/api'), body: 'private A content');
      final check = expectLater(pending, throwsA(isA<AuthExpiredException>()));
      await sent.future;
      if (signOut) {
        await manager.signOut();
      } else {
        await manager.setSession(session('B'));
      }
      response.complete(http.StreamedResponse(body.stream, 401));
      await check;
      expect(canceled, isTrue);
      expect(sends, 1);
      expect(provider.refreshCount, 0);
    });
  }

  test('switch during refresh prevents replay', () async {
    final provider = RefreshProvider();
    final manager = AuthSessionManager(provider: provider, storage: InMemorySecureTokenStorage());
    addTearDown(manager.dispose);
    await manager.setSession(session('A'));
    var sends = 0;
    final client = AuthenticatedHttpClient(authService: manager, inner: StreamingClient((_) async {
      sends++;
      return http.StreamedResponse(Stream.value(<int>[]), 401);
    }));
    final pending = client.post(Uri.parse('https://example.test/api'), body: 'A');
    final check = expectLater(pending, throwsA(isA<StateError>()));
    await provider.entered.future;
    await manager.setSession(session('B'));
    provider.result.complete(session('A'));
    await check;
    expect(sends, 1);
    expect(manager.currentSession?.userId, 'B');
  });

  for (final retryFailure in [false, true]) {
    test('${retryFailure ? 'retry transport' : 'transient refresh'} error keeps its type and session', () async {
      final provider = MockAuthProvider()..mockSessionToReturn = session('A');
      final failure = http.ClientException('offline');
      if (!retryFailure) provider.refreshException = failure;
      final storage = InMemorySecureTokenStorage();
      final manager = AuthSessionManager(provider: provider, storage: storage);
      addTearDown(manager.dispose);
      await manager.setSession(session('A'));
      var sends = 0;
      final client = AuthenticatedHttpClient(authService: manager, inner: StreamingClient((_) async {
        sends++;
        if (sends == 1) return http.StreamedResponse(Stream.value(<int>[]), 401);
        throw failure;
      }));
      await expectLater(client.get(Uri.parse('https://example.test/api')), throwsA(same(failure)));
      expect(manager.currentSession?.userId, 'A');
      expect((await storage.getSession())?.userId, 'A');
      expect(sends, retryFailure ? 2 : 1);
    });
  }

  test('401 without refresh token remains readable by caller', () async {
    final manager = AuthSessionManager(provider: MockAuthProvider(), storage: InMemorySecureTokenStorage());
    addTearDown(manager.dispose);
    final client = AuthenticatedHttpClient(authService: manager, inner: StreamingClient((_) async =>
      http.StreamedResponse(Stream.value([111, 107]), 401)));
    final response = await client.get(Uri.parse('https://example.test/api'));
    expect(response.statusCode, 401);
    expect(response.body, 'ok');
  });
}
