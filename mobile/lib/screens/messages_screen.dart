import 'package:flutter/material.dart';
import '../models/fellowship_models.dart';
import '../services/fellowship_api_client.dart';

class MessagesScreen extends StatefulWidget {
  final FellowshipApiClient? apiClient;

  const MessagesScreen({
    super.key,
    this.apiClient,
  });

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late final FellowshipApiClient _apiClient;
  List<FellowshipGroupData> _groups = [];
  bool _isLoading = false;
  String? _errorMessage;

  FellowshipCategory _selectedCategory = FellowshipCategory.all;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? HttpFellowshipApiClient();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final fetched = await _apiClient.getFellowshipGroups(
        category: _selectedCategory != FellowshipCategory.all ? _selectedCategory : null,
      );
      setState(() {
        _groups = fetched;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _openGroupDetail(FellowshipGroupData group) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FellowshipDetailScreen(
          group: group,
          apiClient: _apiClient,
          onGroupUpdated: (updated) {
            setState(() {
              final index = _groups.indexWhere((g) => g.id == updated.id);
              if (index != -1) {
                _groups[index] = updated;
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
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                try {
                  final newGroup = await _apiClient.createFellowshipGroup(
                    name: nameController.text.trim(),
                    description: descriptionController.text.trim().isEmpty
                        ? null
                        : descriptionController.text.trim(),
                    category: selectedType,
                    meetingSchedule: scheduleController.text.trim().isEmpty
                        ? null
                        : scheduleController.text.trim(),
                    location: locationController.text.trim().isEmpty
                        ? null
                        : locationController.text.trim(),
                  );
                  setState(() {
                    _groups.add(newGroup);
                  });
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create space: $e')),
                  );
                }
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
                    _loadGroups();
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
                    _loadGroups();
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
                    _loadGroups();
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
                    _loadGroups();
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

          // Group List / Loading / Error
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _loadGroups,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : filteredGroups.isEmpty
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
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _getCategoryLabel(group.category),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
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
                                                  fontSize: 12,
                                                  color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: group.isUserMember
                                              ? Colors.green.shade50
                                              : Colors.grey.shade100,
                                          borderRadius:
                                              BorderRadius.circular(12),
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
  final FellowshipApiClient apiClient;
  final ValueChanged<FellowshipGroupData> onGroupUpdated;

  const _FellowshipDetailScreen({
    required this.group,
    required this.apiClient,
    required this.onGroupUpdated,
  });

  @override
  State<_FellowshipDetailScreen> createState() =>
      _FellowshipDetailScreenState();
}

class _FellowshipDetailScreenState extends State<_FellowshipDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late FellowshipGroupData _currentGroup;
  bool _isLoadingDetail = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _currentGroup = widget.group;
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    setState(() => _isLoadingDetail = true);
    try {
      final detail = await widget.apiClient.getFellowshipGroupDetail(_currentGroup.id);
      setState(() {
        _currentGroup = _currentGroup.copyWith(
          members: detail.members,
          posts: detail.posts,
          memberCount: detail.memberCount > 0 ? detail.memberCount : _currentGroup.memberCount,
          description: detail.description,
          leaderName: detail.leaderName ?? _currentGroup.leaderName,
          meetingSchedule: detail.meetingSchedule ?? _currentGroup.meetingSchedule,
          location: detail.location ?? _currentGroup.location,
        );
        _isLoadingDetail = false;
      });
      widget.onGroupUpdated(_currentGroup);
    } catch (_) {
      setState(() => _isLoadingDetail = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _toggleMembership() async {
    final willJoin = !_currentGroup.isUserMember;
    try {
      if (willJoin) {
        await widget.apiClient.joinFellowshipGroup(_currentGroup.id);
      } else {
        await widget.apiClient.leaveFellowshipGroup(_currentGroup.id);
      }
      setState(() {
        _currentGroup = _currentGroup.copyWith(
          isUserMember: willJoin,
          memberCount: willJoin
              ? _currentGroup.memberCount + 1
              : (_currentGroup.memberCount > 0 ? _currentGroup.memberCount - 1 : 0),
        );
      });
      widget.onGroupUpdated(_currentGroup);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: $e')),
      );
    }
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
            onPressed: () async {
              if (titleController.text.trim().isEmpty ||
                  contentController.text.trim().isEmpty) {
                return;
              }
              try {
                final created = await widget.apiClient.createPost(
                  _currentGroup.id,
                  title: titleController.text.trim(),
                  content: contentController.text.trim(),
                );
                setState(() {
                  _currentGroup = _currentGroup.copyWith(
                    posts: [created, ..._currentGroup.posts],
                  );
                });
                widget.onGroupUpdated(_currentGroup);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to post: $e')),
                );
              }
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
        title: Text(_currentGroup.name),
        actions: [
          TextButton.icon(
            key: const Key('toggleMembershipButton'),
            onPressed: _toggleMembership,
            icon: Icon(
              _currentGroup.isUserMember ? Icons.check_circle : Icons.person_add,
              color: _currentGroup.isUserMember ? Colors.green : Colors.blue,
            ),
            label: Text(
              _currentGroup.isUserMember ? 'Joined' : 'Join',
              style: TextStyle(
                color: _currentGroup.isUserMember ? Colors.green : Colors.blue,
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
      body: _isLoadingDetail
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Posts / Conversations
                Column(
                  children: [
                    Expanded(
                      child: _currentGroup.posts.isEmpty
                          ? const Center(
                              child: Text(
                                'No messages yet. Start the conversation!',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              key: const Key('postsListView'),
                              padding: const EdgeInsets.all(12),
                              itemCount: _currentGroup.posts.length,
                              itemBuilder: (context, index) {
                                final post = _currentGroup.posts[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                              'Recent',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey),
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
                                          style:
                                              const TextStyle(fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    if (_currentGroup.isUserMember)
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
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(_currentGroup.description),
                    const Divider(height: 32),
                    if (_currentGroup.leaderName != null) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person),
                        title: const Text('Fellowship Leader'),
                        subtitle: Text(_currentGroup.leaderName!),
                      ),
                    ],
                    if (_currentGroup.meetingSchedule != null) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_today),
                        title: const Text('Meeting Schedule'),
                        subtitle: Text(_currentGroup.meetingSchedule!),
                      ),
                    ],
                    if (_currentGroup.location != null) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.place),
                        title: const Text('Meeting Location'),
                        subtitle: Text(_currentGroup.location!),
                      ),
                    ],
                    const Divider(height: 32),
                    Text(
                      'Members (${_currentGroup.members.length})',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 8),
                    ..._currentGroup.members.map(
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
