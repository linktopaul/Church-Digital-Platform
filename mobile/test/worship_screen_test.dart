import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/models/worship_models.dart';
import 'package:church_digital_platform_mobile/screens/worship_screen.dart';

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
      items: [
        const SetlistSongItem(
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

    // Enter search text
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

    // Tap on Amazing Grace
    await tester.tap(find.byKey(const Key('songItem_1')));
    await tester.pumpAndSettle();

    // Verify detail sheet shows title and chords initially
    expect(find.byKey(const Key('songDetailTitle')), findsOneWidget);
    expect(find.textContaining('[G] Amazing grace'), findsOneWidget);

    // Toggle to lyrics
    await tester.tap(find.text('Lyrics'));
    await tester.pumpAndSettle();

    // Verify lyrics text displayed
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

    // Switch to Sunday Setlists tab
    await tester.tap(find.text('Sunday Setlists'));
    await tester.pumpAndSettle();

    expect(find.text('Sunday Morning Service'), findsOneWidget);
    expect(find.text('1 songs'), findsOneWidget);

    // Tap on setlist to open detail screen
    await tester.tap(find.byKey(const Key('setlistItem_s1')));
    await tester.pumpAndSettle();

    expect(find.text('Setlist Order'), findsOneWidget);
    expect(find.text('Key Ab'), findsOneWidget);
    expect(find.textContaining('Acoustic intro only'), findsOneWidget);
  });
}
