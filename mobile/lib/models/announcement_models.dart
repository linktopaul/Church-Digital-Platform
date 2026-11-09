import 'package:flutter/foundation.dart';

/// Represents the priority of an announcement.
/// Matches backend enum: Routine = 0, Urgent = 1, Emergency = 2
enum AnnouncementPriority {
  routine,
  urgent,
  emergency;

  String get displayName {
    switch (this) {
      case AnnouncementPriority.routine:
        return 'Routine';
      case AnnouncementPriority.urgent:
        return 'Urgent';
      case AnnouncementPriority.emergency:
        return 'Emergency';
    }
  }

  static AnnouncementPriority fromJson(dynamic json) {
    if (json is int) {
      switch (json) {
        case 0:
          return AnnouncementPriority.routine;
        case 1:
          return AnnouncementPriority.urgent;
        case 2:
          return AnnouncementPriority.emergency;
        default:
          return AnnouncementPriority.routine;
      }
    }
    if (json is String) {
      switch (json.trim().toLowerCase()) {
        case 'urgent':
          return AnnouncementPriority.urgent;
        case 'emergency':
          return AnnouncementPriority.emergency;
        default:
          return AnnouncementPriority.routine;
      }
    }
    return AnnouncementPriority.routine;
  }

  dynamic toJson() => index;
}

/// Input model for publishing an announcement matching the backend CreateAnnouncementRequest contract.
@immutable
class CreateAnnouncementInput {
  final String title;
  final String content;
  final AnnouncementPriority priority;
  final DateTime? publishedAt;
  final DateTime? expiresAt;

  const CreateAnnouncementInput({
    required this.title,
    required this.content,
    this.priority = AnnouncementPriority.routine,
    this.publishedAt,
    this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
    'priority': priority.index,
    if (publishedAt != null) 'publishedAt': publishedAt!.toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreateAnnouncementInput &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          content == other.content &&
          priority == other.priority &&
          publishedAt == other.publishedAt &&
          expiresAt == other.expiresAt;

  @override
  int get hashCode =>
      title.hashCode ^
      content.hashCode ^
      priority.hashCode ^
      publishedAt.hashCode ^
      expiresAt.hashCode;
}

/// Response model for an announcement matching the backend AnnouncementResponse contract.
@immutable
class Announcement {
  final String id;
  final String churchId;
  final String authorId;
  final String title;
  final String content;
  final AnnouncementPriority priority;
  final DateTime publishedAt;
  final DateTime? expiresAt;

  const Announcement({
    required this.id,
    required this.churchId,
    required this.authorId,
    required this.title,
    required this.content,
    required this.priority,
    required this.publishedAt,
    this.expiresAt,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'] as String? ?? json['Id'] as String? ?? '',
      churchId: json['churchId'] as String? ?? json['ChurchId'] as String? ?? '',
      authorId: json['authorId'] as String? ?? json['AuthorId'] as String? ?? '',
      title: json['title'] as String? ?? json['Title'] as String? ?? '',
      content: json['content'] as String? ?? json['Content'] as String? ?? '',
      priority: AnnouncementPriority.fromJson(json['priority'] ?? json['Priority']),
      publishedAt: DateTime.parse(
        (json['publishedAt'] ?? json['PublishedAt'] ?? DateTime.now().toIso8601String()) as String,
      ),
      expiresAt: (json['expiresAt'] ?? json['ExpiresAt']) != null
          ? DateTime.parse((json['expiresAt'] ?? json['ExpiresAt']) as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'churchId': churchId,
    'authorId': authorId,
    'title': title,
    'content': content,
    'priority': priority.index,
    'publishedAt': publishedAt.toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
  };
}
