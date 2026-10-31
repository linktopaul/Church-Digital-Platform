class SongItem {
  final String id;
  final String title;
  final String? artist;
  final String? defaultKey;
  final int? tempoBpm;
  final String lyrics;
  final String chords;

  const SongItem({
    required this.id,
    required this.title,
    this.artist,
    this.defaultKey,
    this.tempoBpm,
    required this.lyrics,
    required this.chords,
  });
}

class SetlistSongItem {
  final String songId;
  final String title;
  final String? artist;
  final String? defaultKey;
  final String? keyOverride;
  final int? tempoBpm;
  final String lyrics;
  final String chords;
  final int order;
  final String? notes;

  const SetlistSongItem({
    required this.songId,
    required this.title,
    this.artist,
    this.defaultKey,
    this.keyOverride,
    this.tempoBpm,
    required this.lyrics,
    required this.chords,
    required this.order,
    this.notes,
  });

  String get effectiveKey => keyOverride?.isNotEmpty == true ? keyOverride! : (defaultKey ?? 'C');
}

class SetlistItemData {
  final String id;
  final String title;
  final DateTime serviceDate;
  final String? notes;
  final List<SetlistSongItem> items;

  const SetlistItemData({
    required this.id,
    required this.title,
    required this.serviceDate,
    this.notes,
    required this.items,
  });
}
