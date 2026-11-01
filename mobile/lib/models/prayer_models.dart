import 'package:flutter/foundation.dart';

/// Represents the status of a prayer request.
/// Matches backend enum: Submitted = 0, Praying = 1, Answered = 2
enum PrayerRequestStatus {
  submitted,
  praying,
  answered;

  static PrayerRequestStatus fromJson(dynamic json) {
    if (json is int) {
      switch (json) {
        case 0:
          return PrayerRequestStatus.submitted;
        case 1:
          return PrayerRequestStatus.praying;
        case 2:
          return PrayerRequestStatus.answered;
        default:
          return PrayerRequestStatus.submitted;
      }
    }
    final str = json?.toString().toLowerCase().trim() ?? '';
    switch (str) {
      case 'submitted':
      case '0':
        return PrayerRequestStatus.submitted;
      case 'praying':
      case '1':
        return PrayerRequestStatus.praying;
      case 'answered':
      case '2':
        return PrayerRequestStatus.answered;
      default:
        return PrayerRequestStatus.submitted;
    }
  }

  /// Converts to the int representation expected by backend JSON serialization.
  int toJson() {
    switch (this) {
      case PrayerRequestStatus.submitted:
        return 0;
      case PrayerRequestStatus.praying:
        return 1;
      case PrayerRequestStatus.answered:
        return 2;
    }
  }

  String get displayName {
    switch (this) {
      case PrayerRequestStatus.submitted:
        return 'Submitted';
      case PrayerRequestStatus.praying:
        return 'Praying';
      case PrayerRequestStatus.answered:
        return 'Answered';
    }
  }
}

/// Confidential prayer request model.
///
/// Guardrail: toString() redacts confidential prayer content to prevent
/// inadvertent leaks into console logs or crash reporting.
@immutable
class PrayerRequestData {
  final String id;
  final String churchId;
  final String memberId;
  final String content;
  final PrayerRequestStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PrayerRequestData({
    required this.id,
    required this.churchId,
    required this.memberId,
    required this.content,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PrayerRequestData.fromJson(Map<String, dynamic> json) {
    return PrayerRequestData(
      id: json['id']?.toString() ?? '',
      churchId: json['churchId']?.toString() ?? json['tenantId']?.toString() ?? '',
      memberId: json['memberId']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      status: PrayerRequestStatus.fromJson(json['status']),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'churchId': churchId,
      'memberId': memberId,
      'content': content,
      'status': status.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  PrayerRequestData copyWith({
    String? id,
    String? churchId,
    String? memberId,
    String? content,
    PrayerRequestStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PrayerRequestData(
      id: id ?? this.id,
      churchId: churchId ?? this.churchId,
      memberId: memberId ?? this.memberId,
      content: content ?? this.content,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrayerRequestData &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          churchId == other.churchId &&
          memberId == other.memberId &&
          content == other.content &&
          status == other.status &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      churchId.hashCode ^
      memberId.hashCode ^
      content.hashCode ^
      status.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() {
    // Redact content for privacy guardrails per AGENTS.md
    return 'PrayerRequestData(id: $id, churchId: $churchId, memberId: $memberId, status: $status, content: [CONFIDENTIAL], createdAt: $createdAt, updatedAt: $updatedAt)';
  }
}

/// Input payload for creating a confidential prayer request.
class CreatePrayerRequestInput {
  final String content;

  const CreatePrayerRequestInput({
    required this.content,
  });

  Map<String, dynamic> toJson() {
    return {
      'content': content,
    };
  }
}

/// Input payload for updating a prayer request's status (Pastor only).
class UpdatePrayerRequestStatusInput {
  final PrayerRequestStatus status;

  const UpdatePrayerRequestStatusInput({
    required this.status,
  });

  Map<String, dynamic> toJson() {
    return {
      'status': status.toJson(),
    };
  }
}
