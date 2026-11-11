import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:church_digital_platform_mobile/auth/auth_session.dart';
import 'package:church_digital_platform_mobile/auth/auth_session_manager.dart';
import 'package:church_digital_platform_mobile/models/worship_models.dart';
import 'package:church_digital_platform_mobile/network/api_exceptions.dart';
import 'package:church_digital_platform_mobile/network/authenticated_http_client.dart';
import 'package:church_digital_platform_mobile/services/worship_api_client.dart';

class _FakeAuthService implements AuthService {
  AuthSession? _session;
  final _controller = StreamController<AuthSession?>.broadcast();

  _FakeAuthService([this._session]);

  @override
  Stream<AuthSession?> get sessionStateStream => _controller.stream;

  @override
  AuthSession? get currentSession => _session;

  @override
  Object? get sessionIdentity => _session != null ? Object() : null;

  @override
  Future<AuthSession?> initialize() async => _session;

  @override
  Future<AuthSession> signInWithAuthorizationCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> setSession(AuthSession session) async {
    _session = session;
    _controller.add(session);
  }

  @override
  Future<AuthSession> refresh() => throw UnimplementedError();

  @override
  Future<void> signOut() async {
    _session = null;
    _controller.add(null);
  }

  @override
  void dispose() {
    _controller.close();
  }
}

void main() {
  group('Worship Models Serialization', () {
    test('SongItem round-trips through fromJson and toJson', () {
      final json = {
        'id': 'song-1',
        'churchId': 'church-alpha',
        'title': 'Amazing Grace',
        'artist': 'John Newton',
        'defaultKey': 'G',
        'tempoBpm': 72,
        'lyrics': 'Amazing grace how sweet the sound',
        'chords': '[G] Amazing [C] grace',
        'createdAt': '2026-11-01T10:00:00.000Z',
      };

      final song = SongItem.fromJson(json);
      expect(song.id, 'song-1');
      expect(song.churchId, 'church-alpha');
      expect(song.title, 'Amazing Grace');
      expect(song.artist, 'John Newton');
      expect(song.defaultKey, 'G');
      expect(song.tempoBpm, 72);
      expect(song.lyrics, 'Amazing grace how sweet the sound');
      expect(song.chords, '[G] Amazing [C] grace');
      expect(song.createdAt, DateTime.parse('2026-11-01T10:00:00.000Z'));

      final serialized = song.toJson();
      expect(serialized['id'], 'song-1');
      expect(serialized['churchId'], 'church-alpha');
      expect(serialized['title'], 'Amazing Grace');
      expect(serialized['tempoBpm'], 72);
      expect(SongItem.fromJson(serialized), song);
    });

    test('SetlistSongItem and SetlistItemData parse backend SetlistResponse and SetlistDetailResponse', () {
      final summaryJson = {
        'id': 'setlist-1',
        'churchId': 'church-alpha',
        'title': 'Sunday Morning Service',
        'serviceDate': '2026-11-15T00:00:00.000Z',
        'notes': 'Communion service',
        'itemCount': 2,
        'createdAt': '2026-11-10T09:00:00.000Z',
      };

      final summary = SetlistItemData.fromJson(summaryJson);
      expect(summary.id, 'setlist-1');
      expect(summary.churchId, 'church-alpha');
      expect(summary.title, 'Sunday Morning Service');
      expect(summary.effectiveItemCount, 2);
      expect(summary.items, isEmpty);

      final detailJson = {
        'id': 'setlist-1',
        'churchId': 'church-alpha',
        'title': 'Sunday Morning Service',
        'serviceDate': '2026-11-15T00:00:00.000Z',
        'notes': 'Communion service',
        'createdAt': '2026-11-10T09:00:00.000Z',
        'items': [
          {
            'id': 'item-1',
            'songId': 'song-1',
            'songTitle': 'Amazing Grace',
            'songArtist': 'John Newton',
            'defaultKey': 'G',
            'keyOverride': 'Ab',
            'tempoBpm': 72,
            'lyrics': 'Amazing grace',
            'chords': '[Ab] Amazing grace',
            'order': 1,
            'notes': 'Acoustic intro',
          },
        ],
      };

      final detail = SetlistItemData.fromJson(detailJson);
      expect(detail.items, hasLength(1));
      expect(detail.effectiveItemCount, 1);
      expect(detail.items.first.title, 'Amazing Grace');
      expect(detail.items.first.artist, 'John Newton');
      expect(detail.items.first.effectiveKey, 'Ab');

      final roundTrip = SetlistItemData.fromJson(detail.toJson());
      expect(roundTrip.id, detail.id);
      expect(roundTrip.items.first.title, 'Amazing Grace');
      expect(roundTrip.items.first.effectiveKey, 'Ab');
    });
  });

  group('HttpWorshipApiClient', () {
    const baseUrl = 'https://api.church.local';

    test('normalizes baseUrl with trailing slashes', () async {
      final mockClient = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.church.local/api/v1/worship/songs',
        );
        return http.Response('[]', 200, headers: {'content-type': 'application/json'});
      });

      final client = HttpWorshipApiClient(
        client: mockClient,
        baseUrl: 'https://api.church.local///',
      );

      final songs = await client.getSongs();
      expect(songs, isEmpty);
    });

    test('getSongs and getSong call /api/v1/worship/songs endpoints', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        if (request.url.path == '/api/v1/worship/songs') {
          return http.Response(
            jsonEncode([
              {
                'id': 's-1',
                'churchId': 'c-1',
                'title': 'Way Maker',
                'artist': 'Sinach',
                'defaultKey': 'E',
                'tempoBpm': 68,
                'lyrics': 'You are here',
                'chords': '[E] You are here',
              }
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/v1/worship/songs/s-1') {
          return http.Response(
            jsonEncode({
              'id': 's-1',
              'churchId': 'c-1',
              'title': 'Way Maker',
              'artist': 'Sinach',
              'defaultKey': 'E',
              'tempoBpm': 68,
              'lyrics': 'You are here moving in our midst',
              'chords': '[E] You are here [B] moving',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final client = HttpWorshipApiClient(client: mockClient, baseUrl: baseUrl);
      final songs = await client.getSongs();
      expect(songs, hasLength(1));
      expect(songs.first.title, 'Way Maker');

      final song = await client.getSong('s-1');
      expect(song.id, 's-1');
      expect(song.lyrics, 'You are here moving in our midst');
    });

    test('createSong, updateSong, and deleteSong send authenticated CRUD requests', () async {
      var deleted = false;
      final mockClient = MockClient((request) async {
        if (request.method == 'POST' && request.url.path == '/api/v1/worship/songs') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['title'], 'Goodness of God');
          expect(body['defaultKey'], 'G');
          return http.Response(
            jsonEncode({
              'id': 's-new',
              'churchId': 'c-1',
              'title': body['title'],
              'artist': body['artist'],
              'defaultKey': body['defaultKey'],
              'tempoBpm': body['tempoBpm'],
              'lyrics': body['lyrics'],
              'chords': body['chords'],
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'PUT' && request.url.path == '/api/v1/worship/songs/s-new') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['title'], 'Goodness of God (Acoustic)');
          return http.Response(
            jsonEncode({
              'id': 's-new',
              'churchId': 'c-1',
              'title': body['title'],
              'artist': body['artist'],
              'defaultKey': 'A',
              'tempoBpm': 70,
              'lyrics': body['lyrics'],
              'chords': body['chords'],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'DELETE' && request.url.path == '/api/v1/worship/songs/s-new') {
          deleted = true;
          return http.Response('', 204);
        }
        return http.Response('Unexpected', 500);
      });

      final client = HttpWorshipApiClient(client: mockClient, baseUrl: baseUrl);
      final created = await client.createSong(
        const SongInput(
          title: 'Goodness of God',
          artist: 'Bethel Music',
          defaultKey: 'G',
          tempoBpm: 70,
          lyrics: 'I love You Lord',
          chords: '[G] I love You Lord',
        ),
      );
      expect(created.id, 's-new');
      expect(created.title, 'Goodness of God');

      final updated = await client.updateSong(
        's-new',
        const SongInput(
          title: 'Goodness of God (Acoustic)',
          artist: 'Bethel Music',
          defaultKey: 'A',
          tempoBpm: 70,
          lyrics: 'I love You Lord',
          chords: '[A] I love You Lord',
        ),
      );
      expect(updated.title, 'Goodness of God (Acoustic)');
      expect(updated.defaultKey, 'A');

      await client.deleteSong('s-new');
      expect(deleted, isTrue);
    });

    test('getSetlists, getSetlist, createSetlist, updateSetlist, and deleteSetlist cover setlist CRUD', () async {
      var setlistDeleted = false;
      final mockClient = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/api/v1/worship/setlists') {
          return http.Response(
            jsonEncode([
              {
                'id': 'sl-1',
                'churchId': 'c-1',
                'title': 'Sunday Service',
                'serviceDate': '2026-11-15T00:00:00.000Z',
                'notes': 'Opening service',
                'itemCount': 1,
              }
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' && request.url.path == '/api/v1/worship/setlists/sl-1') {
          return http.Response(
            jsonEncode({
              'id': 'sl-1',
              'churchId': 'c-1',
              'title': 'Sunday Service',
              'serviceDate': '2026-11-15T00:00:00.000Z',
              'notes': 'Opening service',
              'items': [
                {
                  'id': 'item-1',
                  'songId': 's-1',
                  'songTitle': 'Amazing Grace',
                  'songArtist': 'John Newton',
                  'defaultKey': 'G',
                  'keyOverride': 'A',
                  'tempoBpm': 72,
                  'lyrics': 'Amazing grace',
                  'chords': '[A] Amazing grace',
                  'order': 1,
                  'notes': 'Choir leads verse 1',
                }
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' && request.url.path == '/api/v1/worship/setlists') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['title'], 'Evening Praise');
          expect((body['items'] as List).length, 1);
          return http.Response(
            jsonEncode({
              'id': 'sl-2',
              'churchId': 'c-1',
              'title': body['title'],
              'serviceDate': body['serviceDate'],
              'notes': body['notes'],
              'items': [
                {
                  'id': 'item-2',
                  'songId': 's-1',
                  'songTitle': 'Amazing Grace',
                  'defaultKey': 'G',
                  'lyrics': 'Amazing grace',
                  'chords': '[G] Amazing grace',
                  'order': 1,
                }
              ],
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'PUT' && request.url.path == '/api/v1/worship/setlists/sl-2') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['title'], 'Updated Evening Praise');
          return http.Response(
            jsonEncode({
              'id': 'sl-2',
              'churchId': 'c-1',
              'title': body['title'],
              'serviceDate': body['serviceDate'],
              'notes': body['notes'],
              'items': const [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'DELETE' && request.url.path == '/api/v1/worship/setlists/sl-2') {
          setlistDeleted = true;
          return http.Response('', 204);
        }
        return http.Response('Unexpected', 500);
      });

      final client = HttpWorshipApiClient(client: mockClient, baseUrl: baseUrl);
      final setlists = await client.getSetlists();
      expect(setlists, hasLength(1));
      expect(setlists.first.effectiveItemCount, 1);

      final detail = await client.getSetlist('sl-1');
      expect(detail.items, hasLength(1));
      expect(detail.items.first.effectiveKey, 'A');

      final created = await client.createSetlist(
        SetlistInput(
          title: 'Evening Praise',
          serviceDate: DateTime.utc(2026, 11, 22),
          notes: 'Youth band',
          items: const [
            SetlistSongInput(songId: 's-1', order: 1),
          ],
        ),
      );
      expect(created.id, 'sl-2');
      expect(created.title, 'Evening Praise');

      final updated = await client.updateSetlist(
        'sl-2',
        SetlistInput(
          title: 'Updated Evening Praise',
          serviceDate: DateTime.utc(2026, 11, 22),
        ),
      );
      expect(updated.title, 'Updated Evening Praise');

      await client.deleteSetlist('sl-2');
      expect(setlistDeleted, isTrue);
    });

    test('maps 400, 401, 403, 404, and 500 responses to WorshipApiException', () async {
      int statusToReturn = 401;
      String bodyToReturn = 'Unauthorized';

      final mockClient = MockClient((request) async {
        return http.Response(bodyToReturn, statusToReturn);
      });

      final client = HttpWorshipApiClient(client: mockClient, baseUrl: baseUrl);

      await expectLater(
        client.getSongs(),
        throwsA(
          isA<WorshipApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', contains('Authentication required')),
        ),
      );

      statusToReturn = 403;
      bodyToReturn = 'Forbidden';
      await expectLater(
        client.createSong(const SongInput(title: 'Forbidden Song')),
        throwsA(
          isA<WorshipApiException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', contains('Access denied')),
        ),
      );

      statusToReturn = 400;
      bodyToReturn = jsonEncode({'error': 'Song title is required.'});
      await expectLater(
        client.createSong(const SongInput(title: '')),
        throwsA(
          isA<WorshipApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.message, 'message', contains('Song title is required.')),
        ),
      );

      statusToReturn = 404;
      bodyToReturn = jsonEncode({'error': 'Song not found.'});
      await expectLater(
        client.getSong('missing-id'),
        throwsA(
          isA<WorshipApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', contains('Song not found.')),
        ),
      );

      statusToReturn = 500;
      bodyToReturn = 'Internal Server Error';
      await expectLater(
        client.getSetlists(),
        throwsA(
          isA<WorshipApiException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.message, 'message', contains('server error occurred')),
        ),
      );
    });

    test('retries GET on transient ClientException and does not retry POST mutations', () async {
      int getAttempts = 0;
      int postAttempts = 0;

      final mockClient = MockClient((request) async {
        if (request.method == 'GET') {
          getAttempts++;
          if (getAttempts == 1) {
            throw http.ClientException('Connection reset');
          }
          return http.Response('[]', 200, headers: {'content-type': 'application/json'});
        }
        postAttempts++;
        throw http.ClientException('Broken pipe on POST');
      });

      final client = HttpWorshipApiClient(
        client: mockClient,
        baseUrl: baseUrl,
        maxRetries: 2,
      );

      final songs = await client.getSongs();
      expect(songs, isEmpty);
      expect(getAttempts, 2);

      await expectLater(
        client.createSong(const SongInput(title: 'Test')),
        throwsA(isA<WorshipApiException>()),
      );
      expect(postAttempts, 1);
    });

    test('works with AuthenticatedHttpClient attaching Bearer token without forged tenant/role headers', () async {
      http.BaseRequest? capturedRequest;
      final innerClient = MockClient((request) async {
        capturedRequest = request;
        return http.Response('[]', 200, headers: {'content-type': 'application/json'});
      });

      final session = AuthSession(
        accessToken: 'jwt-worship-token',
        refreshToken: 'refresh-token',
        userId: 'user-1',
        tenantId: 'tenant-1',
        roles: const ['WorshipLeader'],
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final authService = _FakeAuthService(session);
      final authHttpClient = AuthenticatedHttpClient(
        authService: authService,
        inner: innerClient,
      );

      final worshipClient = HttpWorshipApiClient(
        client: authHttpClient,
        baseUrl: baseUrl,
      );

      await worshipClient.getSongs();
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.headers['Authorization'], 'Bearer jwt-worship-token');
      expect(capturedRequest!.headers.containsKey('x-tenant-id'), isFalse);
      expect(capturedRequest!.headers.containsKey('x-user-role'), isFalse);

      final forgedRequest = http.Request(
        'GET',
        Uri.parse('$baseUrl/api/v1/worship/songs'),
      )..headers['x-tenant-id'] = 'forged-tenant';
      expect(
        () => authHttpClient.send(forgedRequest),
        throwsA(isA<ProhibitedHeaderException>()),
      );
      authService.dispose();
    });
  });
}
