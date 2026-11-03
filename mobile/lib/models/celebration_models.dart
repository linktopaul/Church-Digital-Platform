/// Types of celebrations supported by the church platform.
enum CelebrationType {
  birthday,
  anniversary,
}

extension CelebrationTypeX on CelebrationType {
  String get displayName {
    switch (this) {
      case CelebrationType.birthday:
        return 'Birthday';
      case CelebrationType.anniversary:
        return 'Anniversary';
    }
  }

  static CelebrationType fromJson(dynamic value) {
    if (value == 1 || value == 'Anniversary' || value == 'anniversary') {
      return CelebrationType.anniversary;
    }
    return CelebrationType.birthday;
  }

  dynamic toJson() {
    switch (this) {
      case CelebrationType.birthday:
        return 0;
      case CelebrationType.anniversary:
        return 1;
    }
  }
}

/// Represents an individual member celebration (birthday or wedding anniversary).
class CelebrationEvent {
  final String memberId;
  final String memberName;
  final String? avatarUrl;
  final CelebrationType type;
  final DateTime date;
  final int? years;
  final String? phoneNumber;
  final String? whatsAppUrl;
  final bool canMessageDirectly;

  const CelebrationEvent({
    required this.memberId,
    required this.memberName,
    this.avatarUrl,
    required this.type,
    required this.date,
    this.years,
    this.phoneNumber,
    this.whatsAppUrl,
    this.canMessageDirectly = false,
  });

  factory CelebrationEvent.fromJson(Map<String, dynamic> json) {
    return CelebrationEvent(
      memberId: (json['memberId'] ?? json['id'] ?? '').toString(),
      memberName: (json['memberName'] ?? json['name'] ?? '').toString(),
      avatarUrl: json['avatarUrl'] as String?,
      type: CelebrationTypeX.fromJson(json['type']),
      date: json['date'] != null
          ? DateTime.parse(json['date'] as String)
          : DateTime.now(),
      years: json['years'] as int?,
      phoneNumber: json['phoneNumber'] as String?,
      whatsAppUrl: json['whatsAppUrl'] as String?,
      canMessageDirectly: json['canMessageDirectly'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'memberId': memberId,
      'memberName': memberName,
      'avatarUrl': avatarUrl,
      'type': type.toJson(),
      'date': date.toIso8601String(),
      'years': years,
      'phoneNumber': phoneNumber,
      'whatsAppUrl': whatsAppUrl,
      'canMessageDirectly': canMessageDirectly,
    };
  }

  /// Milestone description (e.g. "30th Birthday", "15th Anniversary", or "Birthday")
  String get milestoneLabel {
    if (years != null && years! > 0) {
      return '$years${_ordinalSuffix(years!)} ${type.displayName}';
    }
    return type.displayName;
  }

  static String _ordinalSuffix(int n) {
    if (n >= 11 && n <= 13) return 'th';
    switch (n % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }
}

/// Pre-approved scripture blessing templates for celebration greetings.
class BlessingTemplate {
  final CelebrationType type;
  final String title;
  final String template;
  final String defaultScripture;

  const BlessingTemplate({
    required this.type,
    required this.title,
    required this.template,
    required this.defaultScripture,
  });

  factory BlessingTemplate.fromJson(Map<String, dynamic> json) {
    return BlessingTemplate(
      type: CelebrationTypeX.fromJson(json['type']),
      title: (json['title'] ?? '').toString(),
      template: (json['template'] ?? '').toString(),
      defaultScripture: (json['defaultScripture'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.toJson(),
      'title': title,
      'template': template,
      'defaultScripture': defaultScripture,
    };
  }

  /// Formats the template greeting for a given member name.
  String formatGreeting(String memberName) {
    return template.replaceAll('{name}', memberName);
  }
}
