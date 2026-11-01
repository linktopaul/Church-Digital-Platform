import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/auth/auth_provider.dart';
import 'package:church_digital_platform_mobile/auth/auth_session.dart';
import 'package:church_digital_platform_mobile/auth/auth_session_manager.dart';
import '../support/mock_auth_provider.dart';
import '../support/in_memory_secure_token_storage.dart';

AuthSession session(String id, {bool expired = false}) => AuthSession(
  accessToken: id, refreshToken: 'refresh-$id', userId: id, tenantId: 'tenant-$id',
  roles: const ['Member'],
  expiresAt: DateTime.now().add(Duration(hours: expired ? -1 : 1)),
);

class DeferredProvider extends MockAuthProvider {
  final entered = Completer<void>();
  final result = Completer<AuthSession>();
  final revokeEntered = Completer<void>();
  final revoked = Completer<void>();
  bool delayRevoke = false;
  @override
  Future<AuthSession> refreshSession({required String refreshToken}) {
    refreshCount++;
    if (!entered.isCompleted) entered.complete();
    return result.future;
  }
  @override
  Future<AuthSession> exchangeAuthorizationCode({required String code,
    required String codeVerifier, required String redirectUri}) {
    if (!entered.isCompleted) entered.complete();
    return result.future;
  }
  @override
  Future<void> revokeSession({required String token}) async {
    if (delayRevoke) {
      revokeEntered.complete();
      await revoked.future;
    }
  }
}

class DeferredStorage extends InMemorySecureTokenStorage {
  DeferredStorage(super.initialSession);
  final readEntered = Completer<void>();
  final read = Completer<AuthSession?>();
  final saveEntered = Completer<void>();
  final saved = Completer<void>();
  bool delayRead = false;
  bool delaySave = false;
  @override
  Future<AuthSession?> getSession() {
    if (!delayRead) return super.getSession();
    readEntered.complete();
    return read.future;
  }
  @override
  Future<void> saveSession(AuthSession session) async {
    if (delaySave) {
      saveEntered.complete();
      await saved.future;
    }
    await super.saveSession(session);
  }
}

void main() {
  for (final replacement in [false, true]) {
    for (final terminal in [false, true]) {
      test('late refresh ${terminal ? 'rejection' : 'success'} after '
          '${replacement ? 'replacement' : 'signout'} cannot mutate state', () async {
        final provider = DeferredProvider();
        final storage = InMemorySecureTokenStorage();
        final manager = AuthSessionManager(provider: provider, storage: storage);
        addTearDown(manager.dispose);
        await manager.setSession(session('A'));
        final events = <AuthSession?>[];
        final subscription = manager.sessionStateStream.listen(events.add);
        addTearDown(subscription.cancel);
        final pending = manager.refresh();
        final failed = expectLater(pending, throwsA(isA<StateError>()));
        await provider.entered.future;
        if (replacement) {
          await manager.setSession(session('B'));
        } else {
          await manager.signOut();
        }
        if (terminal) {
          provider.result.completeError(const TerminalAuthException());
        } else {
          provider.result.complete(session('A-late'));
        }
        await failed;
        await pumpEventQueue();
        expect(manager.currentSession?.userId, replacement ? 'B' : null);
        expect((await storage.getSession())?.userId, replacement ? 'B' : null);
        expect(events.any((s) => s?.userId == 'A-late'), isFalse);
      });
    }
  }

  for (final replacement in [false, true]) {
    test('late sign-in cannot supersede newer lifecycle', () async {
      final provider = DeferredProvider();
      final storage = InMemorySecureTokenStorage();
      final manager = AuthSessionManager(provider: provider, storage: storage);
      addTearDown(manager.dispose);
      final pending = manager.signInWithAuthorizationCode(
        code: 'code', codeVerifier: 'verifier', redirectUri: 'callback');
      final failed = expectLater(pending, throwsA(isA<StateError>()));
      await provider.entered.future;
      if (replacement) {
        await manager.setSession(session('B'));
      } else {
        await manager.signOut();
      }
      provider.result.complete(session('A'));
      await failed;
      expect(manager.currentSession?.userId, replacement ? 'B' : null);
      expect((await storage.getSession())?.userId, replacement ? 'B' : null);
    });

    test('late initialize storage read cannot restore older credentials', () async {
      final storage = DeferredStorage(null)..delayRead = true;
      final manager = AuthSessionManager(provider: MockAuthProvider(), storage: storage);
      addTearDown(manager.dispose);
      final pending = manager.initialize();
      final failed = expectLater(pending, throwsA(isA<StateError>()));
      await storage.readEntered.future;
      if (replacement) {
        await manager.setSession(session('B'));
      } else {
        await manager.signOut();
      }
      storage.read.complete(session('A'));
      await failed;
      storage.delayRead = false;
      expect((await storage.getSession())?.userId, replacement ? 'B' : null);
      expect(manager.currentSession?.userId, replacement ? 'B' : null);
    });
  }

  test('startup refresh cannot restore after signout', () async {
    final provider = DeferredProvider();
    final storage = InMemorySecureTokenStorage(session('A', expired: true));
    final manager = AuthSessionManager(provider: provider, storage: storage);
    addTearDown(manager.dispose);
    final pending = manager.initialize();
    final failed = expectLater(pending, throwsA(isA<StateError>()));
    await provider.entered.future;
    await manager.signOut();
    provider.result.complete(session('A'));
    await failed;
    expect(manager.currentSession, isNull);
    expect(await storage.getSession(), isNull);
  });

  test('in-flight platform save finishes before newer clear', () async {
    final storage = DeferredStorage(null)..delaySave = true;
    final manager = AuthSessionManager(provider: MockAuthProvider(), storage: storage);
    addTearDown(manager.dispose);
    final pending = manager.setSession(session('A'));
    final failed = expectLater(pending, throwsA(isA<StateError>()));
    await storage.saveEntered.future;
    final logout = manager.signOut();
    storage.saved.complete();
    await failed;
    await logout;
    expect(await storage.getSession(), isNull);
    expect(manager.currentSession, isNull);
  });

  for (final replacementSucceeds in [false, true]) {
    test('queued signout clear survives a replacement attempt that '
        '${replacementSucceeds ? 'succeeds' : 'fails'}', () async {
      final storage = DeferredStorage(null);
      final provider = MockAuthProvider()..mockSessionToReturn = session('A');
      final manager = AuthSessionManager(provider: provider, storage: storage);
      addTearDown(manager.dispose);
      await manager.setSession(session('A'));
      storage.delaySave = true;
      final refresh = manager.refresh();
      final stale = expectLater(refresh, throwsA(isA<StateError>()));
      await storage.saveEntered.future;
      final logout = manager.signOut();
      Future<void>? replacement;
      if (replacementSucceeds) {
        replacement = manager.setSession(session('B'));
      } else {
        provider.exchangeException = Exception('fixture exchange failure');
        await expectLater(manager.signInWithAuthorizationCode(
          code: 'code', codeVerifier: 'verifier', redirectUri: 'callback'), throwsException);
      }
      storage.delaySave = false;
      storage.saved.complete();
      await stale;
      await logout;
      if (replacement != null) await replacement;
      expect(provider.revokeCount, 1);
      expect((await storage.getSession())?.userId, replacementSucceeds ? 'B' : null);
      final restored = AuthSessionManager(provider: provider, storage: storage);
      addTearDown(restored.dispose);
      expect((await restored.initialize())?.userId, replacementSucceeds ? 'B' : null);
    });
  }

  test('remote revocation finishing late cannot clear replacement', () async {
    final provider = DeferredProvider()..delayRevoke = true;
    final storage = InMemorySecureTokenStorage();
    final manager = AuthSessionManager(provider: provider, storage: storage);
    addTearDown(manager.dispose);
    await manager.setSession(session('A'));
    final logout = manager.signOut();
    await provider.revokeEntered.future;
    await manager.setSession(session('B'));
    provider.revoked.complete();
    await logout;
    expect(manager.currentSession?.userId, 'B');
    expect((await storage.getSession())?.userId, 'B');
  });

  test('offline startup retains expired credentials and permits later retry', () async {
    final original = session('A', expired: true);
    final storage = InMemorySecureTokenStorage(original);
    final provider = MockAuthProvider()..refreshException = TimeoutException('offline');
    final manager = AuthSessionManager(provider: provider, storage: storage);
    addTearDown(manager.dispose);
    expect(await manager.initialize(), original);
    expect(manager.isAuthenticated, isFalse);
    expect(await storage.getSession(), original);
    provider.refreshException = null;
    provider.mockSessionToReturn = session('A');
    await manager.refresh();
    expect(manager.isAuthenticated, isTrue);
  });

  test('explicit transient refresh retains credentials and original error', () async {
    final original = session('A');
    final storage = InMemorySecureTokenStorage();
    final failure = TimeoutException('offline');
    final provider = MockAuthProvider()..refreshException = failure;
    final manager = AuthSessionManager(provider: provider, storage: storage);
    addTearDown(manager.dispose);
    await manager.setSession(original);
    await expectLater(manager.refresh(), throwsA(same(failure)));
    expect(manager.currentSession, original);
    expect(await storage.getSession(), original);
  });

  test('dispose prevents a late provider result from writing or emitting', () async {
    final provider = DeferredProvider();
    final original = session('A');
    final storage = InMemorySecureTokenStorage();
    final manager = AuthSessionManager(provider: provider, storage: storage);
    await manager.setSession(original);
    final pending = manager.refresh();
    final failed = expectLater(pending, throwsA(isA<StateError>()));
    await provider.entered.future;
    manager.dispose();
    provider.result.complete(session('late'));
    await failed;
    expect(await storage.getSession(), original);
  });

  test('concurrent refresh calls share provider work', () async {
    final provider = DeferredProvider();
    final manager = AuthSessionManager(provider: provider, storage: InMemorySecureTokenStorage());
    addTearDown(manager.dispose);
    await manager.setSession(session('A'));
    final first = manager.refresh();
    final second = manager.refresh();
    await provider.entered.future;
    provider.result.complete(session('A'));
    expect(await first, await second);
    expect(provider.refreshCount, 1);
  });
}
