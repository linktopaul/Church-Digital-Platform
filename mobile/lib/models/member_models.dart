import 'package:flutter/foundation.dart';

/// Privacy visibility setting for a church member's directory profile.
enum DirectoryVisibility {
  /// Profile is hidden from the general member directory (fail-closed default).
  private(0),

  /// Profile is visible to authenticated church members.
  publicToMembers(1),

  /// Profile is only visible to church leaders (Pastors and Admins).
  leadersOnly(2);

  final int value;
  const DirectoryVisibility(this.value);

  static DirectoryVisibility fromValue(dynamic value) {
    if (value is int) {
      switch (value) {
        case 1:
          return DirectoryVisibility.publicToMembers;
        case 2:
          return DirectoryVisibility.leadersOnly;
        case 0:
        default:
          return DirectoryVisibility.private;
      }
    }
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'publictomembers':
        case 'public':
          return DirectoryVisibility.publicToMembers;
        case 'leadersonly':
          return DirectoryVisibility.leadersOnly;
        case 'private':
        default:
          return DirectoryVisibility.private;
      }
    }
    return DirectoryVisibility.private;
  }

  String get label {
    switch (this) {
      case DirectoryVisibility.publicToMembers:
        return 'Public to Members';
      case DirectoryVisibility.leadersOnly:
        return 'Leaders Only';
      case DirectoryVisibility.private:
        return 'Private';
    }
  }
}

/// Role within a family unit.
enum FamilyRole {
  individual(0),
  headOfHousehold(1),
  spouse(2),
  child(3),
  other(4);

  final int value;
  const FamilyRole(this.value);

  static FamilyRole fromValue(dynamic value) {
    if (value is int) {
      switch (value) {
        case 1:
          return FamilyRole.headOfHousehold;
        case 2:
          return FamilyRole.spouse;
        case 3:
          return FamilyRole.child;
        case 4:
          return FamilyRole.other;
        case 0:
        default:
          return FamilyRole.individual;
      }
    }
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'headofhousehold':
          return FamilyRole.headOfHousehold;
        case 'spouse':
          return FamilyRole.spouse;
        case 'child':
          return FamilyRole.child;
        case 'other':
          return FamilyRole.other;
        case 'individual':
        default:
          return FamilyRole.individual;
      }
    }
    return FamilyRole.individual;
  }

  String get label {
    switch (this) {
      case FamilyRole.headOfHousehold:
        return 'Head of Household';
      case FamilyRole.spouse:
        return 'Spouse';
      case FamilyRole.child:
        return 'Child';
      case FamilyRole.other:
        return 'Other';
      case FamilyRole.individual:
        return 'Individual';
    }
  }
}

/// Full member profile data returned from /api/v1/members/me.
@immutable
class MemberProfile {
  final String id;
  final String tenantId;
  final String firstName;
  final String lastName;
  final String email;
  final String? phoneNumber;
  final String? avatarUrl;
  final String? address;
  final DateTime? dateOfBirth;
  final DateTime? anniversaryDate;
  final DirectoryVisibility directoryVisibility;
  final bool showEmail;
  final bool showPhoneNumber;
  final bool showAddress;
  final bool showBirthday;
  final String? familyId;
  final String? familyName;
  final FamilyRole familyRole;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const MemberProfile({
    required this.id,
    required this.tenantId,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phoneNumber,
    this.avatarUrl,
    this.address,
    this.dateOfBirth,
    this.anniversaryDate,
    this.directoryVisibility = DirectoryVisibility.private,
    this.showEmail = false,
    this.showPhoneNumber = false,
    this.showAddress = false,
    this.showBirthday = false,
    this.familyId,
    this.familyName,
    this.familyRole = FamilyRole.individual,
    this.createdAt,
    this.updatedAt,
  });

  String get fullName => '$firstName $lastName'.trim();

  factory MemberProfile.fromJson(Map<String, dynamic> json) {
    return MemberProfile(
      id: json['id'] as String? ?? '',
      tenantId: json['tenantId'] as String? ?? '',
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      address: json['address'] as String?,
      dateOfBirth: json['dateOfBirth'] != null ? DateTime.tryParse(json['dateOfBirth'] as String) : null,
      anniversaryDate: json['anniversaryDate'] != null ? DateTime.tryParse(json['anniversaryDate'] as String) : null,
      directoryVisibility: DirectoryVisibility.fromValue(json['directoryVisibility']),
      showEmail: json['showEmail'] as bool? ?? false,
      showPhoneNumber: json['showPhoneNumber'] as bool? ?? false,
      showAddress: json['showAddress'] as bool? ?? false,
      showBirthday: json['showBirthDayAndMonth'] as bool? ?? json['showBirthday'] as bool? ?? false,
      familyId: json['familyId'] as String?,
      familyName: json['familyName'] as String?,
      familyRole: FamilyRole.fromValue(json['familyRole']),
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'] as String) : null,
    );
  }

  MemberProfile copyWith({
    String? id,
    String? tenantId,
    String? firstName,
    String? lastName,
    String? email,
    String? phoneNumber,
    String? avatarUrl,
    String? address,
    DateTime? dateOfBirth,
    DateTime? anniversaryDate,
    DirectoryVisibility? directoryVisibility,
    bool? showEmail,
    bool? showPhoneNumber,
    bool? showAddress,
    bool? showBirthday,
    String? familyId,
    String? familyName,
    FamilyRole? familyRole,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MemberProfile(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      address: address ?? this.address,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      anniversaryDate: anniversaryDate ?? this.anniversaryDate,
      directoryVisibility: directoryVisibility ?? this.directoryVisibility,
      showEmail: showEmail ?? this.showEmail,
      showPhoneNumber: showPhoneNumber ?? this.showPhoneNumber,
      showAddress: showAddress ?? this.showAddress,
      showBirthday: showBirthday ?? this.showBirthday,
      familyId: familyId ?? this.familyId,
      familyName: familyName ?? this.familyName,
      familyRole: familyRole ?? this.familyRole,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Directory member response returned from /api/v1/members.
@immutable
class DirectoryMember {
  final String id;
  final String fullName;
  final String? avatarUrl;
  final String? email;
  final String? phoneNumber;
  final String? address;
  final String? birthdayNotice;
  final DirectoryVisibility directoryVisibility;
  final String? familyId;
  final String? familyName;
  final FamilyRole familyRole;

  const DirectoryMember({
    required this.id,
    required this.fullName,
    this.avatarUrl,
    this.email,
    this.phoneNumber,
    this.address,
    this.birthdayNotice,
    this.directoryVisibility = DirectoryVisibility.private,
    this.familyId,
    this.familyName,
    this.familyRole = FamilyRole.individual,
  });

  factory DirectoryMember.fromJson(Map<String, dynamic> json) {
    String computedFullName = json['fullName'] as String? ?? '';
    if (computedFullName.isEmpty) {
      final first = json['firstName'] as String? ?? '';
      final last = json['lastName'] as String? ?? '';
      computedFullName = '$first $last'.trim();
    }
    if (computedFullName.isEmpty) {
      computedFullName = 'Church Member';
    }

    return DirectoryMember(
      id: json['id'] as String? ?? '',
      fullName: computedFullName,
      avatarUrl: json['avatarUrl'] as String?,
      email: json['email'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      address: json['address'] as String?,
      birthdayNotice: json['birthdayNotice'] as String?,
      directoryVisibility: DirectoryVisibility.fromValue(json['directoryVisibility']),
      familyId: json['familyId'] as String?,
      familyName: json['familyName'] as String?,
      familyRole: FamilyRole.fromValue(json['familyRole']),
    );
  }
}

/// Family unit response returned from /api/v1/members/families/{id}.
@immutable
class FamilyData {
  final String id;
  final String tenantId;
  final String familyName;
  final List<DirectoryMember> members;

  const FamilyData({
    required this.id,
    required this.tenantId,
    required this.familyName,
    this.members = const [],
  });

  factory FamilyData.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'];
    final membersList = <DirectoryMember>[];
    if (rawMembers is List) {
      for (final item in rawMembers) {
        if (item is Map<String, dynamic>) {
          membersList.add(DirectoryMember.fromJson(item));
        }
      }
    }
    return FamilyData(
      id: json['id'] as String? ?? '',
      tenantId: json['tenantId'] as String? ?? '',
      familyName: json['familyName'] as String? ?? '',
      members: membersList,
    );
  }
}

/// Request payload for updating the current member's profile.
class UpdateMemberProfileInput {
  final String firstName;
  final String lastName;
  final String? phoneNumber;
  final String? avatarUrl;
  final String? address;
  final DateTime? dateOfBirth;
  final DateTime? anniversaryDate;
  final DirectoryVisibility directoryVisibility;
  final bool showEmail;
  final bool showPhoneNumber;
  final bool showAddress;
  final bool showBirthday;

  const UpdateMemberProfileInput({
    required this.firstName,
    required this.lastName,
    this.phoneNumber,
    this.avatarUrl,
    this.address,
    this.dateOfBirth,
    this.anniversaryDate,
    this.directoryVisibility = DirectoryVisibility.private,
    this.showEmail = false,
    this.showPhoneNumber = false,
    this.showAddress = false,
    this.showBirthday = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'phoneNumber': phoneNumber,
      'avatarUrl': avatarUrl,
      'address': address,
      'dateOfBirth': dateOfBirth?.toUtc().toIso8601String(),
      'anniversaryDate': anniversaryDate?.toUtc().toIso8601String(),
      'directoryVisibility': directoryVisibility.value,
      'showEmail': showEmail,
      'showPhoneNumber': showPhoneNumber,
      'showAddress': showAddress,
      'showBirthDayAndMonth': showBirthday,
      'showBirthday': showBirthday,
    };
  }
}
