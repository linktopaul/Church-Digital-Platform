enum FellowshipCategory {
  all,
  mensFellowship,
  sundaySchool,
  housePrayer,
}

class FellowshipGroupData {
  final String id;
  final String name;
  final String description;
  final FellowshipCategory category;
  final String? leaderName;
  final String? meetingSchedule;
  final String? location;
  final bool isPrivate;
  final int memberCount;
  final bool isUserMember;
  final List<FellowshipPostData> posts;
  final List<String> members;

  const FellowshipGroupData({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.leaderName,
    this.meetingSchedule,
    this.location,
    this.isPrivate = false,
    this.memberCount = 0,
    this.isUserMember = false,
    this.posts = const [],
    this.members = const [],
  });

  FellowshipGroupData copyWith({
    String? id,
    String? name,
    String? description,
    FellowshipCategory? category,
    String? leaderName,
    String? meetingSchedule,
    String? location,
    bool? isPrivate,
    int? memberCount,
    bool? isUserMember,
    List<FellowshipPostData>? posts,
    List<String>? members,
  }) {
    return FellowshipGroupData(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      leaderName: leaderName ?? this.leaderName,
      meetingSchedule: meetingSchedule ?? this.meetingSchedule,
      location: location ?? this.location,
      isPrivate: isPrivate ?? this.isPrivate,
      memberCount: memberCount ?? this.memberCount,
      isUserMember: isUserMember ?? this.isUserMember,
      posts: posts ?? this.posts,
      members: members ?? this.members,
    );
  }
}

class FellowshipPostData {
  final String id;
  final String authorName;
  final String title;
  final String content;
  final DateTime createdAt;

  const FellowshipPostData({
    required this.id,
    required this.authorName,
    required this.title,
    required this.content,
    required this.createdAt,
  });
}
