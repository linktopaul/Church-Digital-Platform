import 'package:flutter/foundation.dart';

@immutable
class SongItem {
  final String id;
  final String? churchId;
  final String title;
  final String? artist;
  final String? defaultKey;
  final int? tempoBpm;
  final String lyrics;
  final String chords;
  final DateTime? createdAt;

  const SongItem({
    required this.id,
    this.churchId,
    required this.title,
    this.artist,
    this.defaultKey,
    this.tempoBpm,
    required this.lyrics,
    required this.chords,
    this.createdAt,
  });

  factory SongItem.fromJson(Map<String, dynamic> json) {
    return SongItem(
      id: json['id']?.toString() ?? '',
      churchId: json['churchId']?.toString() ?? json['tenantId']?.toString(),
      title: json['title']?.toString() ?? '',
      artist: json['artist']?.toString(),
      defaultKey: json['defaultKey']?.toString(),
      tempoBpm: json['tempoBpm'] is int
          ? json['tempoBpm'] as int
          : int.tryParse(json['tempoBpm']?.toString() ?? ''),
      lyrics: json['lyrics']?.toString() ?? '',
      chords: json['chords']?.toString() ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (churchId != null) 'churchId': churchId,
      'title': title,
      'artist': artist,
      'defaultKey': defaultKey,
      'tempoBpm': tempoBpm,
      'lyrics': lyrics,
      'chords': chords,
      if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
    };
  }

  SongItem copyWith({
    String? id,
    String? churchId,
    String? title,
    String? artist,
    String? defaultKey,
    int? tempoBpm,
    String? lyrics,
    String? chords,
    DateTime? createdAt,
  }) {
    return SongItem(
      id: id ?? this.id,
      churchId: churchId ?? this.churchId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      defaultKey: defaultKey ?? this.defaultKey,
      tempoBpm: tempoBpm ?? this.tempoBpm,
      lyrics: lyrics ?? this.lyrics,
      chords: chords ?? this.chords,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          churchId == other.churchId &&
          title == other.title &&
          artist == other.artist &&
          defaultKey == other.defaultKey &&
          tempoBpm == other.tempoBpm &&
          lyrics == other.lyrics &&
          chords == other.chords &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        churchId,
        title,
        artist,
        defaultKey,
        tempoBpm,
        lyrics,
        chords,
        createdAt,
      );
}

@immutable
class SongInput {
  final String title;
  final String? artist;
  final String? defaultKey;
  final int? tempoBpm;
  final String lyrics;
  final String chords;

  const SongInput({
    required this.title,
    this.artist,
    this.defaultKey,
    this.tempoBpm,
    this.lyrics = '',
    this.chords = '',
  });

  factory SongInput.fromJson(Map<String, dynamic> json) {
    return SongInput(
      title: json['title']?.toString() ?? '',
      artist: json['artist']?.toString(),
      defaultKey: json['defaultKey']?.toString(),
      tempoBpm: json['tempoBpm'] is int
          ? json['tempoBpm'] as int
          : int.tryParse(json['tempoBpm']?.toString() ?? ''),
      lyrics: json['lyrics']?.toString() ?? '',
      chords: json['chords']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'artist': artist,
      'defaultKey': defaultKey,
      'tempoBpm': tempoBpm,
      'lyrics': lyrics,
      'chords': chords,
    };
  }
}

typedef CreateSongInput = SongInput;
typedef UpdateSongInput = SongInput;

@immutable
class SetlistSongItem {
  final String? id;
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
    this.id,
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

  String get effectiveKey =>
      keyOverride?.isNotEmpty == true ? keyOverride! : (defaultKey ?? 'C');

  factory SetlistSongItem.fromJson(Map<String, dynamic> json) {
    return SetlistSongItem(
      id: json['id']?.toString(),
      songId: json['songId']?.toString() ?? '',
      title: (json['songTitle'] ?? json['title'])?.toString() ?? '',
      artist: (json['songArtist'] ?? json['artist'])?.toString(),
      defaultKey: json['defaultKey']?.toString(),
      keyOverride: json['keyOverride']?.toString(),
      tempoBpm: json['tempoBpm'] is int
          ? json['tempoBpm'] as int
          : int.tryParse(json['tempoBpm']?.toString() ?? ''),
      lyrics: json['lyrics']?.toString() ?? '',
      chords: json['chords']?.toString() ?? '',
      order: json['order'] is int
          ? json['order'] as int
          : (int.tryParse(json['order']?.toString() ?? '') ?? 1),
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'songId': songId,
      'title': title,
      'songTitle': title,
      'artist': artist,
      'songArtist': artist,
      'defaultKey': defaultKey,
      'keyOverride': keyOverride,
      'tempoBpm': tempoBpm,
      'lyrics': lyrics,
      'chords': chords,
      'order': order,
      'notes': notes,
    };
  }

  SetlistSongItem copyWith({
    String? id,
    String? songId,
    String? title,
    String? artist,
    String? defaultKey,
    String? keyOverride,
    int? tempoBpm,
    String? lyrics,
    String? chords,
    int? order,
    String? notes,
  }) {
    return SetlistSongItem(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      defaultKey: defaultKey ?? this.defaultKey,
      keyOverride: keyOverride ?? this.keyOverride,
      tempoBpm: tempoBpm ?? this.tempoBpm,
      lyrics: lyrics ?? this.lyrics,
      chords: chords ?? this.chords,
      order: order ?? this.order,
      notes: notes ?? this.notes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetlistSongItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          songId == other.songId &&
          title == other.title &&
          artist == other.artist &&
          defaultKey == other.defaultKey &&
          keyOverride == other.keyOverride &&
          tempoBpm == other.tempoBpm &&
          lyrics == other.lyrics &&
          chords == other.chords &&
          order == other.order &&
          notes == other.notes;

  @override
  int get hashCode => Object.hash(
        id,
        songId,
        title,
        artist,
        defaultKey,
        keyOverride,
        tempoBpm,
        lyrics,
        chords,
        order,
        notes,
      );
}

@immutable
class SetlistSongInput {
  final String songId;
  final int order;
  final String? keyOverride;
  final String? notes;

  const SetlistSongInput({
    required this.songId,
    required this.order,
    this.keyOverride,
    this.notes,
  });

  factory SetlistSongInput.fromJson(Map<String, dynamic> json) {
    return SetlistSongInput(
      songId: json['songId']?.toString() ?? '',
      order: json['order'] is int
          ? json['order'] as int
          : (int.tryParse(json['order']?.toString() ?? '') ?? 1),
      keyOverride: json['keyOverride']?.toString(),
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'songId': songId,
      'order': order,
      'keyOverride': keyOverride,
      'notes': notes,
    };
  }
}

typedef CreateSetlistItemInput = SetlistSongInput;

@immutable
class SetlistItemData {
  final String id;
  final String? churchId;
  final String title;
  final DateTime serviceDate;
  final String? notes;
  final List<SetlistSongItem> items;
  final int? itemCount;
  final DateTime? createdAt;

  const SetlistItemData({
    required this.id,
    this.churchId,
    required this.title,
    required this.serviceDate,
    this.notes,
    this.items = const [],
    this.itemCount,
    this.createdAt,
  });

  int get effectiveItemCount =>
      items.isNotEmpty ? items.length : (itemCount ?? 0);

  factory SetlistItemData.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final parsedItems = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((item) =>
                SetlistSongItem.fromJson(Map<String, dynamic>.from(item)))
            .toList()
        : <SetlistSongItem>[];
    final parsedCount = json['itemCount'] is int
        ? json['itemCount'] as int
        : int.tryParse(json['itemCount']?.toString() ?? '');

    return SetlistItemData(
      id: json['id']?.toString() ?? '',
      churchId: json['churchId']?.toString() ?? json['tenantId']?.toString(),
      title: json['title']?.toString() ?? '',
      serviceDate:
          DateTime.tryParse(json['serviceDate']?.toString() ?? '') ??
              DateTime.utc(2026, 1, 1),
      notes: json['notes']?.toString(),
      items: parsedItems,
      itemCount: parsedCount ?? parsedItems.length,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (churchId != null) 'churchId': churchId,
      'title': title,
      'serviceDate': serviceDate.toUtc().toIso8601String(),
      'notes': notes,
      'itemCount': effectiveItemCount,
      'items': items.map((i) => i.toJson()).toList(),
      if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
    };
  }

  SetlistItemData copyWith({
    String? id,
    String? churchId,
    String? title,
    DateTime? serviceDate,
    String? notes,
    List<SetlistSongItem>? items,
    int? itemCount,
    DateTime? createdAt,
  }) {
    return SetlistItemData(
      id: id ?? this.id,
      churchId: churchId ?? this.churchId,
      title: title ?? this.title,
      serviceDate: serviceDate ?? this.serviceDate,
      notes: notes ?? this.notes,
      items: items ?? this.items,
      itemCount: itemCount ?? this.itemCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetlistItemData &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          churchId == other.churchId &&
          title == other.title &&
          serviceDate == other.serviceDate &&
          notes == other.notes &&
          listEquals(items, other.items) &&
          effectiveItemCount == other.effectiveItemCount &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        churchId,
        title,
        serviceDate,
        notes,
        Object.hashAll(items),
        effectiveItemCount,
        createdAt,
      );
}

@immutable
class SetlistInput {
  final String title;
  final DateTime serviceDate;
  final String? notes;
  final List<SetlistSongInput> items;

  const SetlistInput({
    required this.title,
    required this.serviceDate,
    this.notes,
    this.items = const [],
  });

  static DateTime parseUtcCalendarDate(String raw, DateTime fallback) {
    final trimmed = raw.trim();
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(trimmed);
    if (match != null) {
      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      final candidate = DateTime.utc(year, month, day);
      if (candidate.year == year &&
          candidate.month == month &&
          candidate.day == day) {
        return candidate;
      }
      return DateTime.utc(fallback.year, fallback.month, fallback.day);
    }
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) {
      return DateTime.utc(fallback.year, fallback.month, fallback.day);
    }
    return parsed.isUtc
        ? parsed
        : DateTime.utc(
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
            parsed.second,
            parsed.millisecond,
            parsed.microsecond,
          );
  }

  factory SetlistInput.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return SetlistInput(
      title: json['title']?.toString() ?? '',
      serviceDate:
          DateTime.tryParse(json['serviceDate']?.toString() ?? '') ??
              DateTime.utc(2026, 1, 1),
      notes: json['notes']?.toString(),
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((i) =>
                  SetlistSongInput.fromJson(Map<String, dynamic>.from(i)))
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    final utcDate = serviceDate.isUtc
        ? serviceDate
        : DateTime.utc(
            serviceDate.year,
            serviceDate.month,
            serviceDate.day,
            serviceDate.hour,
            serviceDate.minute,
            serviceDate.second,
            serviceDate.millisecond,
            serviceDate.microsecond,
          );
    return {
      'title': title,
      'serviceDate': utcDate.toIso8601String(),
      'notes': notes,
      'items': items.map((i) => i.toJson()).toList(),
    };
  }
}

typedef CreateSetlistInput = SetlistInput;
typedef UpdateSetlistInput = SetlistInput;
