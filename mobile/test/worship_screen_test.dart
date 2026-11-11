import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/models/worship_models.dart';
import 'package:church_digital_platform_mobile/screens/worship_screen.dart';
import 'package:church_digital_platform_mobile/services/worship_api_client.dart';

class FakeWorshipApiClient implements WorshipApiClient {
  List<SongItem> songs;
  List<SetlistItemData> setlists;
  WorshipApiException? getSongsError;
  WorshipApiException? getSetlistsError;
  WorshipApiException? getSetlistDetailError;
  SetlistInput? lastUpdatedInput;
  SongInput? lastUpdatedSongInput;
  WorshipApiException? mutationError;

  int getSongsCalls = 0;
  int getSetlistsCalls = 0;
  int createSongCalls = 0;
  int updateSongCalls = 0;
  int deleteSongCalls = 0;
  int createSetlistCalls = 0;
  int updateSetlistCalls = 0;
  int deleteSetlistCalls = 0;

  FakeWorshipApiClient({
    List<SongItem>? songs,
    List<SetlistItemData>? setlists,
    this.getSongsError,
    this.getSetlistsError,
    this.getSetlistDetailError,
    this.mutationError,
  })  : songs = List<SongItem>.from(songs ?? const []),
        setlists = List<SetlistItemData>.from(setlists ?? const []);

  @override
  Future<List<SongItem>> getSongs() async {
    getSongsCalls++;
    if (getSongsError != null) throw getSongsError!;
    return List<SongItem>.from(songs);
  }

  @override
  Future<SongItem> getSong(String id) async {
    if (getSongsError != null) throw getSongsError!;
    return songs.firstWhere(
      (s) => s.id == id,
      orElse: () => throw const WorshipApiException(
        'Song not found.',
        statusCode: 404,
      ),
    );
  }

  @override
  Future<SongItem> createSong(SongInput input) async {
    createSongCalls++;
    if (mutationError != null) throw mutationError!;
    final created = SongItem(
      id: 'song-${songs.length + 10}',
      title: input.title,
      artist: input.artist,
      defaultKey: input.defaultKey,
      tempoBpm: input.tempoBpm,
      lyrics: input.lyrics,
      chords: input.chords,
    );
    songs.add(created);
    return created;
  }

  @override
  Future<SongItem> updateSong(String id, SongInput input) async {
    updateSongCalls++;
    lastUpdatedSongInput = input;
    if (mutationError != null) throw mutationError!;
    final index = songs.indexWhere((s) => s.id == id);
    if (index == -1) {
      throw const WorshipApiException('Song not found.', statusCode: 404);
    }
    final updated = songs[index].copyWith(
      title: input.title,
      artist: input.artist,
      defaultKey: input.defaultKey,
      tempoBpm: input.tempoBpm,
      lyrics: input.lyrics,
      chords: input.chords,
    );
    songs[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteSong(String id) async {
    deleteSongCalls++;
    if (mutationError != null) throw mutationError!;
    songs.removeWhere((s) => s.id == id);
  }

  @override
  Future<List<SetlistItemData>> getSetlists() async {
    getSetlistsCalls++;
    if (getSetlistsError != null) throw getSetlistsError!;
    return List<SetlistItemData>.from(setlists);
  }

  @override
  Future<SetlistItemData> getSetlist(String id) async {
    if (getSetlistDetailError != null) throw getSetlistDetailError!;
    if (getSetlistsError != null) throw getSetlistsError!;
    return setlists.firstWhere(
      (s) => s.id == id,
      orElse: () => throw const WorshipApiException(
        'Setlist not found.',
        statusCode: 404,
      ),
    );
  }

  @override
  Future<SetlistItemData> createSetlist(SetlistInput input) async {
    createSetlistCalls++;
    if (mutationError != null) throw mutationError!;
    final mappedItems = input.items.map((itemInput) {
      final matchingSong = songs.firstWhere(
        (s) => s.id == itemInput.songId,
        orElse: () => SongItem(
          id: itemInput.songId,
          title: 'Song ${itemInput.songId}',
          lyrics: '',
          chords: '',
        ),
      );
      return SetlistSongItem(
        songId: matchingSong.id,
        title: matchingSong.title,
        artist: matchingSong.artist,
        defaultKey: matchingSong.defaultKey,
        keyOverride: itemInput.keyOverride,
        tempoBpm: matchingSong.tempoBpm,
        lyrics: matchingSong.lyrics,
        chords: matchingSong.chords,
        order: itemInput.order,
        notes: itemInput.notes,
      );
    }).toList();

    final created = SetlistItemData(
      id: 'setlist-${setlists.length + 10}',
      title: input.title,
      serviceDate: input.serviceDate,
      notes: input.notes,
      items: mappedItems,
    );
    setlists.insert(0, created);
    return created;
  }

  @override
  Future<SetlistItemData> updateSetlist(String id, SetlistInput input) async {
    updateSetlistCalls++;
    lastUpdatedInput = input;
    if (mutationError != null) throw mutationError!;
    final idx = setlists.indexWhere((s) => s.id == id);
    if (idx == -1) {
      throw const WorshipApiException('Setlist not found.', statusCode: 404);
    }
    final updated = setlists[idx].copyWith(
      title: input.title,
      serviceDate: input.serviceDate,
      notes: input.notes,
    );
    setlists[idx] = updated;
    return updated;
  }

  @override
  Future<void> deleteSetlist(String id) async {
    deleteSetlistCalls++;
    if (mutationError != null) throw mutationError!;
    setlists.removeWhere((s) => s.id == id);
  }
}

void main() {
  final sampleSongs = [
    const SongItem(
      id: '1',
      title: 'Amazing Grace',
      artist: 'John Newton',
      defaultKey: 'G',
      tempoBpm: 72,
      lyrics: 'Amazing grace how sweet the sound',
      chords: '[G] Amazing grace how [C] sweet the [G] sound',
    ),
    const SongItem(
      id: '2',
      title: 'Way Maker',
      artist: 'Sinach',
      defaultKey: 'E',
      tempoBpm: 68,
      lyrics: 'You are here, moving in our midst',
      chords: '[E] You are here, moving [B] in our midst',
    ),
  ];

  final sampleSetlists = [
    SetlistItemData(
      id: 's1',
      title: 'Sunday Morning Service',
      serviceDate: DateTime(2026, 11, 8),
      notes: 'Communion Sunday',
      items: const [
        SetlistSongItem(
          songId: '1',
          title: 'Amazing Grace',
          artist: 'John Newton',
          defaultKey: 'G',
          keyOverride: 'Ab',
          tempoBpm: 72,
          lyrics: 'Amazing grace how sweet the sound',
          chords: '[Ab] Amazing grace how [Db] sweet the [Ab] sound',
          order: 1,
          notes: 'Acoustic intro only',
        ),
      ],
    ),
  ];

  testWidgets('WorshipScreen displays tabs for Song Library and Sunday Setlists',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorshipScreen(
          initialSongs: sampleSongs,
          initialSetlists: sampleSetlists,
        ),
      ),
    );

    expect(find.text('Song Library'), findsOneWidget);
    expect(find.text('Sunday Setlists'), findsOneWidget);
    expect(find.text('Amazing Grace'), findsOneWidget);
    expect(find.text('Way Maker'), findsOneWidget);
  });

  testWidgets('Searching songs filters the song library', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorshipScreen(
          initialSongs: sampleSongs,
          initialSetlists: sampleSetlists,
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('songSearchField')), 'Way');
    await tester.pumpAndSettle();

    expect(find.text('Way Maker'), findsOneWidget);
    expect(find.text('Amazing Grace'), findsNothing);
  });

  testWidgets('Tapping song opens detail sheet with chords and lyrics toggle',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorshipScreen(
          initialSongs: sampleSongs,
          initialSetlists: sampleSetlists,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('songItem_1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('songDetailTitle')), findsOneWidget);
    expect(find.textContaining('[G] Amazing grace'), findsOneWidget);

    await tester.tap(find.text('Lyrics'));
    await tester.pumpAndSettle();

    expect(find.text('Amazing grace how sweet the sound'), findsOneWidget);
  });

  testWidgets('Switching to Sunday Setlists tab shows service setlists and detail',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorshipScreen(
          initialSongs: sampleSongs,
          initialSetlists: sampleSetlists,
        ),
      ),
    );

    await tester.tap(find.text('Sunday Setlists'));
    await tester.pumpAndSettle();

    expect(find.text('Sunday Morning Service'), findsOneWidget);
    expect(find.text('1 songs'), findsOneWidget);

    await tester.tap(find.byKey(const Key('setlistItem_s1')));
    await tester.pumpAndSettle();

    expect(find.text('Setlist Order'), findsOneWidget);
    expect(find.text('Key Ab'), findsOneWidget);
    expect(find.textContaining('Acoustic intro only'), findsOneWidget);
  });

  testWidgets('Does not fall back to fake demo setlists when apiClient is provided',
      (tester) async {
    final client = FakeWorshipApiClient(songs: [], setlists: []);

    await tester.pumpWidget(
      MaterialApp(
        home: WorshipScreen(apiClient: client),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No songs found.'), findsOneWidget);

    await tester.tap(find.text('Sunday Setlists'));
    await tester.pumpAndSettle();

    expect(find.text('No setlists available yet.'), findsOneWidget);
    expect(find.text('Youth Revival Night'), findsNothing);
    expect(find.text('Sunday Morning Worship'), findsNothing);
  });

  testWidgets('Role gating hides create/edit/delete controls when canManageWorship is false',
      (tester) async {
    final client = FakeWorshipApiClient(
      songs: sampleSongs,
      setlists: sampleSetlists,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorshipScreen(
          apiClient: client,
          canManageWorship: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('addSongFab')), findsNothing);
    expect(find.byKey(const Key('editSongButton_1')), findsNothing);
    expect(find.byKey(const Key('deleteSongButton_1')), findsNothing);

    await tester.tap(find.text('Sunday Setlists'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('addSetlistFab')), findsNothing);
    expect(find.byKey(const Key('editSetlistButton_s1')), findsNothing);
    expect(find.byKey(const Key('deleteSetlistButton_s1')), findsNothing);
  });

  testWidgets('Authorized manager (canManageWorship: true) can create, edit, and delete songs',
      (tester) async {
    final client = FakeWorshipApiClient(
      songs: [sampleSongs.first],
      setlists: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorshipScreen(
          apiClient: client,
          canManageWorship: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('addSongFab')), findsOneWidget);

    // 1. Create Song
    await tester.tap(find.byKey(const Key('addSongFab')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('addSongTitleField')), 'Holy Forever');
    await tester.enterText(find.byKey(const Key('addSongArtistField')), 'Chris Tomlin');
    await tester.enterText(find.byKey(const Key('addSongLyricsField')), 'A thousand generations');
    await tester.enterText(find.byKey(const Key('addSongChordsField')), '[G] A thousand');
    await tester.tap(find.byKey(const Key('saveSongButton')));
    await tester.pumpAndSettle();

    expect(client.createSongCalls, 1);
    expect(find.text('Holy Forever'), findsOneWidget);

    // 2. Edit Song
    await tester.tap(find.byKey(const Key('editSongButton_1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('addSongTitleField')), 'Amazing Grace (Hymn)');
    await tester.tap(find.byKey(const Key('saveSongButton')));
    await tester.pumpAndSettle();

    expect(client.updateSongCalls, 1);
    expect(find.text('Amazing Grace (Hymn)'), findsOneWidget);

    // 3. Delete Song
    await tester.tap(find.byKey(const Key('deleteSongButton_1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirmDeleteSongButton')));
    await tester.pumpAndSettle();

    expect(client.deleteSongCalls, 1);
    expect(find.text('Amazing Grace (Hymn)'), findsNothing);
  });

  testWidgets('Authorized manager (canManageWorship: true) can create, edit, and delete setlists',
      (tester) async {
    final client = FakeWorshipApiClient(
      songs: sampleSongs,
      setlists: List<SetlistItemData>.from(sampleSetlists),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorshipScreen(
          apiClient: client,
          canManageWorship: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Sunday Setlists tab
    await tester.tap(find.text('Sunday Setlists'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('addSetlistFab')), findsOneWidget);

    // 1. Create Setlist
    await tester.tap(find.byKey(const Key('addSetlistFab')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('setlistTitleField')), 'Evening Revival');
    await tester.enterText(find.byKey(const Key('setlistDateField')), '2026-11-22');
    await tester.enterText(find.byKey(const Key('setlistNotesField')), 'Acoustic opening');
    await tester.tap(find.byKey(const Key('selectSetlistSong_1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('saveSetlistButton')));
    await tester.pumpAndSettle();

    expect(client.createSetlistCalls, 1);
    expect(find.text('Evening Revival'), findsOneWidget);

    // 2. Edit Setlist
    await tester.tap(find.byKey(const Key('editSetlistButton_s1')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('setlistTitleField')),
      'Sunday Morning Service (Updated)',
    );
    await tester.tap(find.byKey(const Key('saveSetlistButton')));
    await tester.pumpAndSettle();

    expect(client.updateSetlistCalls, 1);
    expect(find.text('Sunday Morning Service (Updated)'), findsOneWidget);

    // 3. Delete Setlist
    await tester.tap(find.byKey(const Key('deleteSetlistButton_s1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('confirmDeleteSetlistButton')));
    await tester.pumpAndSettle();

    expect(client.deleteSetlistCalls, 1);
    expect(find.text('Sunday Morning Service (Updated)'), findsNothing);
  });

  testWidgets('Surfaces clean 401/403/network errors with retry on songs and setlists',
      (tester) async {
    final client = FakeWorshipApiClient(
      songs: sampleSongs,
      setlists: sampleSetlists,
      getSongsError: const WorshipApiException(
        'Authentication required. Please sign in.',
        statusCode: 401,
      ),
      getSetlistsError: const WorshipApiException(
        'Network connection error. Please check your internet connection.',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorshipScreen(
          apiClient: client,
          canManageWorship: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load the worship library.'), findsOneWidget);
    expect(find.text('Authentication required. Please sign in.'), findsOneWidget);

    // Retry Songs after error clears
    client.getSongsError = null;
    await tester.tap(find.byKey(const Key('retrySongsButton')));
    await tester.pumpAndSettle();

    expect(find.text('Amazing Grace'), findsOneWidget);

    // Switch to Sunday Setlists tab and verify error + retry
    await tester.tap(find.text('Sunday Setlists'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load service setlists.'), findsOneWidget);
    expect(
      find.text('Network connection error. Please check your internet connection.'),
      findsOneWidget,
    );

    client.getSetlistsError = null;
    await tester.tap(find.byKey(const Key('retrySetlistsButton')));
    await tester.pumpAndSettle();

    expect(find.text('Sunday Morning Service'), findsOneWidget);

    // Verify 403 error surfaced cleanly on song mutation
    await tester.tap(find.text('Song Library'));
    await tester.pumpAndSettle();

    client.mutationError = const WorshipApiException(
      'Access denied. You do not have permission for this worship action.',
      statusCode: 403,
    );

    await tester.tap(find.byKey(const Key('addSongFab')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('addSongTitleField')), 'Unauthorized Song');
    await tester.tap(find.byKey(const Key('saveSongButton')));
    await tester.pumpAndSettle();

    expect(
      find.text('Access denied. You do not have permission for this worship action.'),
      findsWidgets,
    );
  });

  testWidgets('Editing setlist from list loads detail items before allowing save and blocks save on fetch failure',
      (tester) async {
    final summarySetlist = SetlistItemData(
      id: 's-summary',
      title: 'Summary Setlist',
      serviceDate: DateTime.utc(2026, 11, 29),
      notes: 'Original notes',
      itemCount: 1,
      items: const [],
    );
    final detailedSetlist = SetlistItemData(
      id: 's-summary',
      title: 'Summary Setlist',
      serviceDate: DateTime.utc(2026, 11, 29),
      notes: 'Original notes',
      itemCount: 1,
      items: [
        SetlistSongItem(
          songId: '1',
          title: 'Amazing Grace',
          lyrics: 'Amazing grace how sweet the sound',
          chords: '[G] Amazing [C] grace',
          keyOverride: 'A',
          order: 1,
          notes: 'Acoustic intro',
        ),
      ],
    );

    final client = _DetailSplitWorshipClient(
      songs: sampleSongs,
      summarySetlist: summarySetlist,
      detailedSetlist: detailedSetlist,
      getSetlistDetailError: const WorshipApiException('Failed loading setlist items.'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorshipScreen(
          apiClient: client,
          canManageWorship: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sunday Setlists'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('editSetlistButton_s-summary')));
    await tester.pumpAndSettle();

    expect(find.text('Failed loading setlist items.'), findsOneWidget);
    final saveBtnBlocked = tester.widget<ElevatedButton>(
      find.byKey(const Key('saveSetlistButton')),
    );
    expect(saveBtnBlocked.onPressed, isNull);

    // Fix error, retry loading setlist details, then edit title only
    client.getSetlistDetailError = null;
    await tester.tap(find.byKey(const Key('retrySetlistDetailButton')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('setlistTitleField')),
      'Summary Setlist (Renamed)',
    );
    await tester.tap(find.byKey(const Key('saveSetlistButton')));
    await tester.pumpAndSettle();

    expect(client.updateSetlistCalls, 1);
    expect(client.lastUpdatedInput, isNotNull);
    expect(client.lastUpdatedInput!.items.length, 1);
    expect(client.lastUpdatedInput!.items.first.songId, '1');
    expect(client.lastUpdatedInput!.items.first.keyOverride, 'A');
    expect(client.lastUpdatedInput!.items.first.notes, 'Acoustic intro');
  });

  testWidgets('Editing canonical song from a setlist override preserves library defaultKey', (tester) async {
    final overrideSetlist = SetlistItemData(
      id: 's-override',
      title: 'Sunday Override Service',
      serviceDate: DateTime.utc(2026, 11, 22),
      items: [
        SetlistSongItem(
          songId: '1',
          title: 'Amazing Grace',
          artist: 'John Newton',
          defaultKey: 'G',
          keyOverride: 'A',
          tempoBpm: 72,
          lyrics: 'Amazing grace how sweet the sound',
          chords: '[A] Amazing [D] grace',
          order: 1,
          notes: 'Modulate up',
        ),
      ],
    );
    final client = FakeWorshipApiClient(
      songs: sampleSongs,
      setlists: [overrideSetlist],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorshipScreen(
          apiClient: client,
          canManageWorship: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sunday Setlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sunday Override Service'));
    await tester.pumpAndSettle();

    // Performance view shows override key A
    expect(find.text('Key A'), findsOneWidget);
    await tester.tap(find.text('Amazing Grace'));
    await tester.pumpAndSettle();

    expect(find.text('Key: A'), findsOneWidget);
    await tester.tap(find.byKey(const Key('editSongDetailButton')));
    await tester.pumpAndSettle();

    // Edit form must prefill canonical library defaultKey ('G'), not 'A'
    final keyField = tester.widget<TextField>(find.byKey(const Key('addSongKeyField')));
    expect(keyField.controller?.text, 'G');

    await tester.enterText(find.byKey(const Key('addSongTitleField')), 'Amazing Grace (Hymnal)');
    await tester.tap(find.byKey(const Key('saveSongButton')));
    await tester.pumpAndSettle();

    expect(client.updateSongCalls, 1);
    expect(client.lastUpdatedSongInput!.defaultKey, 'G');
  });

  testWidgets('Editing setlist preserves distinct metadata across repeated song occurrences', (tester) async {
    final repeatedSetlist = SetlistItemData(
      id: 's-repeat',
      title: 'Repeated Song Service',
      serviceDate: DateTime.utc(2026, 11, 29),
      itemCount: 2,
      items: const [],
    );
    final repeatedDetail = SetlistItemData(
      id: 's-repeat',
      title: 'Repeated Song Service',
      serviceDate: DateTime.utc(2026, 11, 29),
      itemCount: 2,
      items: [
        SetlistSongItem(
          songId: '1',
          title: 'Amazing Grace',
          defaultKey: 'G',
          keyOverride: 'A',
          lyrics: 'Verse 1',
          chords: '[A]',
          order: 1,
          notes: 'Opening',
        ),
        SetlistSongItem(
          songId: '1',
          title: 'Amazing Grace',
          defaultKey: 'G',
          keyOverride: 'C',
          lyrics: 'Chorus reprise',
          chords: '[C]',
          order: 2,
          notes: 'Benediction reprise',
        ),
      ],
    );
    final client = _DetailSplitWorshipClient(
      songs: sampleSongs,
      summarySetlist: repeatedSetlist,
      detailedSetlist: repeatedDetail,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorshipScreen(
          apiClient: client,
          canManageWorship: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sunday Setlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editSetlistButton_s-repeat')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('setlistTitleField')), 'Repeated Song Service v2');
    await tester.tap(find.byKey(const Key('saveSetlistButton')));
    await tester.pumpAndSettle();

    expect(client.lastUpdatedInput, isNotNull);
    expect(client.lastUpdatedInput!.items.length, 2);
    expect(client.lastUpdatedInput!.items[0].keyOverride, 'A');
    expect(client.lastUpdatedInput!.items[0].notes, 'Opening');
    expect(client.lastUpdatedInput!.items[1].keyOverride, 'C');
    expect(client.lastUpdatedInput!.items[1].notes, 'Benediction reprise');
  });

  testWidgets('Editing song preserves absent defaultKey and tempoBpm as null', (tester) async {
    final minimalSong = SongItem(
      id: 'song-min',
      title: 'Chorus Only',
      artist: null,
      defaultKey: null,
      tempoBpm: null,
      lyrics: 'Hallelujah',
      chords: '',
    );
    final client = FakeWorshipApiClient(
      songs: [minimalSong],
      setlists: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorshipScreen(
          apiClient: client,
          canManageWorship: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chorus Only'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editSongDetailButton')));
    await tester.pumpAndSettle();

    final keyField = tester.widget<TextField>(find.byKey(const Key('addSongKeyField')));
    final tempoField = tester.widget<TextField>(find.byKey(const Key('addSongTempoField')));
    expect(keyField.controller?.text, isEmpty);
    expect(tempoField.controller?.text, isEmpty);

    await tester.enterText(find.byKey(const Key('addSongTitleField')), 'Chorus Updated');
    await tester.tap(find.byKey(const Key('saveSongButton')));
    await tester.pumpAndSettle();

    expect(client.updateSongCalls, 1);
    expect(client.lastUpdatedSongInput!.defaultKey, isNull);
    expect(client.lastUpdatedSongInput!.tempoBpm, isNull);
  });

  testWidgets('Creating song while initial fetch is pending reloads full library', (tester) async {
    final firstLoadCompleter = Completer<List<SongItem>>();
    final client = _DeferredFirstLoadWorshipClient(
      firstLoadCompleter: firstLoadCompleter,
      libraryAfterCreate: sampleSongs,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorshipScreen(
          apiClient: client,
          canManageWorship: true,
        ),
      ),
    );
    await tester.pump();

    // Open Add Song while initial getSongs() is still pending
    await tester.tap(find.byKey(const Key('addSongFab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byKey(const Key('addSongTitleField')), 'New Praise Song');
    await tester.tap(find.byKey(const Key('saveSongButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Release stale initial fetch; second reload should populate existing library + created song
    firstLoadCompleter.complete(const []);
    await tester.pumpAndSettle();

    expect(client.getSongsCalls, greaterThanOrEqualTo(2));
    expect(find.text('New Praise Song'), findsOneWidget);
    expect(find.text('Amazing Grace'), findsOneWidget);
  });
}

class _DeferredFirstLoadWorshipClient extends FakeWorshipApiClient {
  final Completer<List<SongItem>> firstLoadCompleter;

  _DeferredFirstLoadWorshipClient({
    required this.firstLoadCompleter,
    required List<SongItem> libraryAfterCreate,
  }) : super(songs: libraryAfterCreate, setlists: const []);

  @override
  Future<List<SongItem>> getSongs() async {
    getSongsCalls++;
    if (getSongsCalls == 1) {
      return firstLoadCompleter.future;
    }
    return List<SongItem>.from(songs);
  }
}

class _DetailSplitWorshipClient extends FakeWorshipApiClient {
  final SetlistItemData summarySetlist;
  final SetlistItemData detailedSetlist;

  _DetailSplitWorshipClient({
    required super.songs,
    required this.summarySetlist,
    required this.detailedSetlist,
    super.getSetlistDetailError,
  }) : super(setlists: [detailedSetlist]);

  @override
  Future<List<SetlistItemData>> getSetlists() async {
    getSetlistsCalls++;
    return [summarySetlist];
  }

  @override
  Future<SetlistItemData> getSetlist(String id) async {
    if (getSetlistDetailError != null) throw getSetlistDetailError!;
    return detailedSetlist;
  }
}
