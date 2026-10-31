import 'package:flutter/material.dart';
import '../models/fellowship_models.dart';

class MessagesScreen extends StatefulWidget {
  final List<FellowshipGroupData>? initialGroups;

  const MessagesScreen({
    super.key,
    this.initialGroups,
  });

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late List<FellowshipGroupData> _groups;
  FellowshipCategory _selectedCategory = FellowshipCategory.all;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _groups = widget.initialGroups ??
        [
          FellowshipGroupData(
            id: '1',
            name: "Men's Fellowship Brotherhood",
            description:
                'Men gathering for spiritual growth, accountability, and community outreach.',
            category: FellowshipCategory.mensFellowship,
            leaderName: 'Elder John Thomas',
            meetingSchedule: 'Saturdays at 7:00 AM',
            location: 'Main Fellowship Hall',
            memberCount: 24,
            isUserMember: true,
            members: const ['Elder John Thomas', 'Brother Timothy', 'David Miller'],
            posts: [
              FellowshipPostData(
                id: 'p1',
                authorName: 'Elder John Thomas',
                title: 'Upcoming Men\'s Breakfast & Outreach',
                content:
                    'Join us this Saturday for breakfast followed by community service in the city park.',
                createdAt: DateTime.now().subtract(const Duration(hours: 4)),
              ),
            ],
          ),
          FellowshipGroupData(
            id: '2',
            name: 'Sunday School - Primary Department',
            description:
                'Interactive Bible lessons, crafts, and memory verses for children ages 6 to 10.',
            category: FellowshipCategory.sundaySchool,
            leaderName: 'Sister Mary Grace',
            meetingSchedule: 'Sundays at 9:00 AM',
            location: 'Education Wing, Room 102',
            memberCount: 18,
            isUserMember: false,
            members: const ['Sister Mary Grace', 'Sister Sarah', 'Deacon Paul'],
            posts: [
              FellowshipPostData(
                id: 'p2',
                authorName: 'Sister Mary Grace',
                title: 'Lesson Plan: The Good Samaritan',
                content:
                    'Please review the memory verse Luke 10:27 with your children before Sunday!',
                createdAt: DateTime.now().subtract(const Duration(days: 1)),
              ),
            ],
          ),
          FellowshipGroupData(
            id: '3',
            name: 'North District House Prayer',
            description:
                'Weekly home fellowship and intercessory prayer meeting in the North neighborhood.',
            category: FellowshipCategory.housePrayer,
            leaderName: 'Brother David & Ruth',
            meetingSchedule: 'Wednesdays at 7:30 PM',
            location: "David's Residence, 42 Elm Street",
            memberCount: 12,
            isUserMember: false,
            members: const ['Brother David', 'Ruth', 'Brother Mark'],
            posts: [
              FellowshipPostData(
                id: 'p3',
                authorName: 'Brother David',
                title: 'Prayer Focus for this Wednesday',
                content:
                    'We will be praying for healing and revival across our local community families.',
                createdAt: DateTime.now().subtract(const Duration(days: 2)),
              ),
            ],
          ),
        ];
  }

  void _openGroupDetail(FellowshipGroupData group) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FellowshipDetailScreen(
          group: group,
          onToggleMembership: (isMember) {
            setState(() {
              final index = _groups.indexWhere((g) => g.id == group.id);
              if (index != -1) {
                final current = _groups[index];
                _groups[index] = current.copyWith(
                  isUserMember: isMember,
                  memberCount: isMember
                      ? current.memberCount + 1
                      : (current.memberCount > 0 ? current.memberCount - 1 : 0),
                );
              }
            });
          },
          onAddPost: (post) {
            setState(() {
              final index = _groups.indexWhere((g) => g.id == group.id);
              if (index != -1) {
                final current = _groups[index];
                _groups[index] = current.copyWith(
                  posts: [post, ...current.posts],
                );
              }
            });
          },
        ),
      ),
    );
  }

  void _openCreateGroupDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final scheduleController = TextEditingController();
    final locationController = TextEditingController();
    FellowshipCategory selectedType = FellowshipCategory.mensFellowship;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Fellowship Space'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('createGroupNameField'),
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Space Name *'),
                ),
                TextField(
                  key: const Key('createGroupDescField'),
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                DropdownButtonFormField<FellowshipCategory>(
                  key: const Key('createGroupTypeDropdown'),
                  initialValue: selectedType,
                  decoration: const InputDecoration(labelText: 'Fellowship Type'),
                  items: const [
                    DropdownMenuItem(
                      value: FellowshipCategory.mensFellowship,
                      child: Text("Men's Fellowship"),
                    ),
                    DropdownMenuItem(
                      value: FellowshipCategory.sundaySchool,
                      child: Text('Sunday School'),
                    ),
                    DropdownMenuItem(
                      value: FellowshipCategory.housePrayer,
                      child: Text('House Prayer'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => selectedType = val);
                    }
                  },
                ),
                TextField(
                  key: const Key('createGroupScheduleField'),
                  controller: scheduleController,
                  decoration:
                      const InputDecoration(labelText: 'Meeting Schedule'),
                ),
                TextField(
                  key: const Key('createGroupLocationField'),
                  controller: locationController,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              key: const Key('saveGroupButton'),
              onPressed: () {
                if (nameController.text.trim().isEmpty) return;
                setState(() {
                  _groups.add(
                    FellowshipGroupData(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameController.text.trim(),
                      description: descriptionController.text.trim(),
                      category: selectedType,
                      leaderName: 'Current User',
                      meetingSchedule: scheduleController.text.trim().isEmpty
                          ? null
                          : scheduleController.text.trim(),
                      location: locationController.text.trim().isEmpty
                          ? null
                          : locationController.text.trim(),
                      memberCount: 1,
                      isUserMember: true,
                      members: const ['Current User'],
                      posts: const [],
                    ),
                  );
                });
                Navigator.of(context).pop();
              },
              child: const Text('Create Space'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(FellowshipCategory cat) {
    switch (cat) {
      case FellowshipCategory.mensFellowship:
        return Icons.group;
      case FellowshipCategory.sundaySchool:
        return Icons.school;
      case FellowshipCategory.housePrayer:
        return Icons.home;
      case FellowshipCategory.all:
        return Icons.groups;
    }
  }

  String _getCategoryLabel(FellowshipCategory cat) {
    switch (cat) {
      case FellowshipCategory.mensFellowship:
        return "Men's Fellowship";
      case FellowshipCategory.sundaySchool:
        return 'Sunday School';
      case FellowshipCategory.housePrayer:
        return 'House Prayer';
      case FellowshipCategory.all:
        return 'All Spaces';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredGroups = _groups.where((g) {
      if (_selectedCategory != FellowshipCategory.all &&
          g.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return g.name.toLowerCase().contains(q) ||
            g.description.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    return Scaffold(
      body: Column(
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  key: const Key('filterChipAll'),
                  label: const Text('All Spaces'),
                  selected: _selectedCategory == FellowshipCategory.all,
                  onSelected: (val) {
                    setState(() => _selectedCategory = FellowshipCategory.all);
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  key: const Key('filterChipMens'),
                  avatar: const Icon(Icons.group, size: 18),
                  label: const Text("Men's Fellowship"),
                  selected:
                      _selectedCategory == FellowshipCategory.mensFellowship,
                  onSelected: (val) {
                    setState(() => _selectedCategory =
                        FellowshipCategory.mensFellowship);
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  key: const Key('filterChipSundaySchool'),
                  avatar: const Icon(Icons.school, size: 18),
                  label: const Text('Sunday School'),
                  selected:
                      _selectedCategory == FellowshipCategory.sundaySchool,
                  onSelected: (val) {
                    setState(() =>
                        _selectedCategory = FellowshipCategory.sundaySchool);
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  key: const Key('filterChipHousePrayer'),
                  avatar: const Icon(Icons.home, size: 18),
                  label: const Text('House Prayer'),
                  selected:
                      _selectedCategory == FellowshipCategory.housePrayer,
                  onSelected: (val) {
                    setState(() =>
                        _selectedCategory = FellowshipCategory.housePrayer);
                  },
                ),
              ],
            ),
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              key: const Key('searchFellowshipField'),
              decoration: InputDecoration(
                hintText: 'Search fellowship spaces...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          // Group List
          Expanded(
            child: filteredGroups.isEmpty
                ? const Center(
                    child: Text(
                      'No fellowship spaces found.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    key: const Key('fellowshipListView'),
                    itemCount: filteredGroups.length,
                    itemBuilder: (context, index) {
                      final group = filteredGroups[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: ListTile(
                          key: Key('groupItem_${group.id}'),
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            child: Icon(
                              _getCategoryIcon(group.category),
                              color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            ),
                          ),
                          title: Text(
                            group.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getCategoryLabel(group.category),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                group.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              if (group.meetingSchedule != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time,
                                        size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      group.meetingSchedule!,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: group.isUserMember
                                      ? Colors.green.shade50
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  group.isUserMember ? 'Joined' : 'Join',
                                  style: TextStyle(
                                    color: group.isUserMember
                                        ? Colors.green.shade800
                                        : Colors.grey.shade700,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${group.memberCount} members',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                          onTap: () => _openGroupDetail(group),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('createFellowshipFab'),
        onPressed: _openCreateGroupDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Space'),
      ),
    );
  }
}

class _FellowshipDetailScreen extends StatefulWidget {
  final FellowshipGroupData group;
  final ValueChanged<bool> onToggleMembership;
  final ValueChanged<FellowshipPostData> onAddPost;

  const _FellowshipDetailScreen({
    required this.group,
    required this.onToggleMembership,
    required this.onAddPost,
  });

  @override
  State<_FellowshipDetailScreen> createState() =>
      _FellowshipDetailScreenState();
}

class _FellowshipDetailScreenState extends State<_FellowshipDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late bool _isMember;
  late List<FellowshipPostData> _posts;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _isMember = widget.group.isUserMember;
    _posts = List.from(widget.group.posts);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openCreatePostDialog() {
    final titleController = TextEditingController();
    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Post to Fellowship Space'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('postTitleField'),
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title *'),
            ),
            TextField(
              key: const Key('postContentField'),
              controller: contentController,
              decoration: const InputDecoration(labelText: 'Message *'),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const Key('submitPostButton'),
            onPressed: () {
              if (titleController.text.trim().isEmpty ||
                  contentController.text.trim().isEmpty) {
                return;
              }
              final newPost = FellowshipPostData(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                authorName: 'Current User',
                title: titleController.text.trim(),
                content: contentController.text.trim(),
                createdAt: DateTime.now(),
              );
              setState(() {
                _posts.insert(0, newPost);
              });
              widget.onAddPost(newPost);
              Navigator.of(context).pop();
            },
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          TextButton.icon(
            key: const Key('toggleMembershipButton'),
            onPressed: () {
              setState(() {
                _isMember = !_isMember;
              });
              widget.onToggleMembership(_isMember);
            },
            icon: Icon(
              _isMember ? Icons.check_circle : Icons.person_add,
              color: _isMember ? Colors.green : Colors.blue,
            ),
            label: Text(
              _isMember ? 'Joined' : 'Join',
              style: TextStyle(
                color: _isMember ? Colors.green : Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Conversations & Updates'),
            Tab(text: 'About & Members'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Posts / Conversations
          Column(
            children: [
              Expanded(
                child: _posts.isEmpty
                    ? const Center(
                        child: Text(
                          'No messages yet. Start the conversation!',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        key: const Key('postsListView'),
                        padding: const EdgeInsets.all(12),
                        itemCount: _posts.length,
                        itemBuilder: (context, index) {
                          final post = _posts[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        child: Text(
                                          post.authorName.isNotEmpty
                                              ? post.authorName[0]
                                              : '?',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        post.authorName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      const Spacer(),
                                      const Icon(Icons.schedule,
                                          size: 14, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Today',
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    post.title,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    post.content,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (_isMember)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ElevatedButton.icon(
                    key: const Key('addPostButton'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _openCreatePostDialog,
                    icon: const Icon(Icons.create),
                    label: const Text('Post Update or Prayer Note'),
                  ),
                ),
            ],
          ),

          // Tab 2: About & Members
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'About this Fellowship',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(widget.group.description),
              const Divider(height: 32),
              if (widget.group.leaderName != null) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person),
                  title: const Text('Fellowship Leader'),
                  subtitle: Text(widget.group.leaderName!),
                ),
              ],
              if (widget.group.meetingSchedule != null) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('Meeting Schedule'),
                  subtitle: Text(widget.group.meetingSchedule!),
                ),
              ],
              if (widget.group.location != null) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.place),
                  title: const Text('Meeting Location'),
                  subtitle: Text(widget.group.location!),
                ),
              ],
              const Divider(height: 32),
              Text(
                'Members (${widget.group.members.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              ...widget.group.members.map(
                (m) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text(m.isNotEmpty ? m[0] : '?'),
                  ),
                  title: Text(m),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
