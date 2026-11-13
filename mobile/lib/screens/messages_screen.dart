import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/fellowship_models.dart';
import '../services/fellowship_api_client.dart';
import '../theme/app_theme.dart';

class MessagesScreen extends StatefulWidget {
  final FellowshipApiClient? apiClient;
  final String? apiBaseUrl;
  final String Function()? getAuthToken;
  final String? currentUserId;
  final String? currentMemberName;

  const MessagesScreen({
    super.key,
    this.apiClient,
    this.apiBaseUrl,
    this.getAuthToken,
    this.currentUserId,
    this.currentMemberName,
  });

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  FellowshipApiClient? _apiClient;
  List<FellowshipGroupData> _groups = [];
  bool _isLoading = false;
  String? _errorMessage;
  int _loadGeneration = 0;
  int _sessionGeneration = 0;
  final ValueNotifier<int> _sessionGenerationNotifier = ValueNotifier<int>(0);

  FellowshipCategory _selectedCategory = FellowshipCategory.all;
  String _searchQuery = '';

  FellowshipApiClient? _resolveClient() {
    if (widget.apiClient != null) return widget.apiClient;
    if (widget.getAuthToken != null || widget.apiBaseUrl != null) {
      return HttpFellowshipApiClient(
        baseUrl: widget.apiBaseUrl,
        getAuthToken: widget.getAuthToken,
        currentUserId: widget.currentUserId,
        currentMemberName: widget.currentMemberName,
      );
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _apiClient = _resolveClient();
    if (_apiClient != null) {
      _loadGroups();
    }
  }

  @override
  void didUpdateWidget(covariant MessagesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl ||
        oldWidget.currentUserId != widget.currentUserId) {
      _apiClient = _resolveClient();
      _sessionGeneration++;
      _sessionGenerationNotifier.value = _sessionGeneration;
      _loadGeneration++;
      _groups = [];
      _errorMessage = null;
      _isLoading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final nav = Navigator.maybeOf(context);
        if (nav != null && nav.canPop()) {
          nav.popUntil((route) => route.isFirst);
        }
      });
      if (_apiClient != null) {
        _loadGroups();
      }
    }
  }

  @override
  void dispose() {
    _sessionGeneration++;
    _sessionGenerationNotifier.value = _sessionGeneration;
    _sessionGenerationNotifier.dispose();
    super.dispose();
  }

  String _sanitizeErrorMessage(dynamic e) {
    final str = e.toString().toLowerCase();
    if (str.contains('401') || str.contains('unauthorized')) {
      return 'Your session has expired. Please sign in again.';
    }
    if (str.contains('403') || str.contains('forbidden') || str.contains('access denied')) {
      return 'Access denied. You do not have permission to view fellowship spaces.';
    }
    return 'Failed to load fellowship spaces. Please check your connection.';
  }

  Future<void> _loadGroups() async {
    final client = _apiClient;
    if (client == null) return;

    final currentGen = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final fetched = await client.getFellowshipGroups(
        category: _selectedCategory != FellowshipCategory.all ? _selectedCategory : null,
      );
      if (!mounted || currentGen != _loadGeneration) return;
      setState(() {
        _groups = fetched;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || currentGen != _loadGeneration) return;
      setState(() {
        _errorMessage = _sanitizeErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  void _openGroupDetail(FellowshipGroupData group) {
    final client = _apiClient;
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FellowshipDetailScreen(
          group: group,
          apiClient: client,
          sessionGenerationListenable: _sessionGenerationNotifier,
          initialSessionGeneration: _sessionGeneration,
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
    final client = _apiClient;
    if (client == null) return;
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
                final capturedSession = _sessionGeneration;
                try {
                  final newGroup = await client.createFellowshipGroup(
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
                  if (!mounted || capturedSession != _sessionGeneration || _apiClient != client) {
                    return;
                  }
                  setState(() {
                    _groups.add(newGroup);
                  });
                  final nav = Navigator.maybeOf(context);
                  if (nav != null && nav.canPop()) {
                    nav.pop();
                  }
                } catch (e) {
                  if (!mounted || capturedSession != _sessionGeneration || _apiClient != client) {
                    return;
                  }
                  final errorMsg = _sanitizeMutationError(e, 'Failed to create space');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(errorMsg)),
                  );
                  final nav = Navigator.maybeOf(context);
                  if (nav != null && nav.canPop()) {
                    nav.pop();
                  }
                }
              },
              child: const Text('Create Space'),
            ),
          ],
        ),
      ),
    );
  }

  String _sanitizeMutationError(dynamic e, String defaultPrefix) {
    final str = e.toString().toLowerCase();
    if (str.contains('401') || str.contains('unauthorized')) {
      return 'Your session has expired. Please sign in again.';
    }
    if (str.contains('403') || str.contains('forbidden')) {
      return 'Access denied. You do not have permission for this action.';
    }
    return '$defaultPrefix. Please try again.';
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

  Widget _buildUnauthenticatedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Sign In Required',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Fellowship spaces and church group messaging require an active, authenticated member session.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Unable to Load Spaces',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'An error occurred while connecting to fellowship spaces.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadGroups,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.groups_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No Fellowship Spaces Found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No fellowship spaces match your search criteria.'
                  : 'There are currently no fellowship spaces available. Create one to get started!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_apiClient == null) {
      return Scaffold(
        body: _buildUnauthenticatedState(),
      );
    }

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
              decoration: const InputDecoration(
                hintText: 'Search fellowship spaces...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          // Group List / Loading / Error
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildErrorState()
                    : filteredGroups.isEmpty
                        ? RefreshIndicator(
                            onRefresh: _loadGroups,
                            child: CustomScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: _buildEmptyState(),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadGroups,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                              key: const Key('fellowshipListView'),
                              itemCount: filteredGroups.length,
                              itemBuilder: (context, index) {
                                final group = filteredGroups[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: ListTile(
                                    key: Key('groupItem_${group.id}'),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    leading: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: BasilicaColors.stone,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: BasilicaColors.borderSoft),
                                      ),
                                      child: Icon(
                                        _getCategoryIcon(group.category),
                                        color: BasilicaColors.burgundy,
                                      ),
                                    ),
                                    title: Text(
                                      group.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'serif',
                                        color: BasilicaColors.burgundy,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _getCategoryLabel(group.category),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontFamily: 'serif',
                                            color: BasilicaColors.burgundy.withAlpha(200),
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
                                              Expanded(
                                                child: Text(
                                                  group.meetingSchedule!,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey),
                                                ),
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
  final ValueListenable<int>? sessionGenerationListenable;
  final int initialSessionGeneration;

  const _FellowshipDetailScreen({
    required this.group,
    required this.apiClient,
    required this.onGroupUpdated,
    this.sessionGenerationListenable,
    this.initialSessionGeneration = 0,
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
  late int _sessionGeneration;

  bool get _isSessionValid =>
      widget.sessionGenerationListenable == null ||
      widget.sessionGenerationListenable!.value == _sessionGeneration;

  @override
  void initState() {
    super.initState();
    _sessionGeneration = widget.initialSessionGeneration;
    widget.sessionGenerationListenable?.addListener(_handleSessionChanged);
    _tabController = TabController(length: 2, vsync: this);
    _currentGroup = widget.group;
    _fetchDetail();
  }

  void _handleSessionChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    widget.sessionGenerationListenable?.removeListener(_handleSessionChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetail() async {
    final capturedSession = _sessionGeneration;
    setState(() => _isLoadingDetail = true);
    try {
      final detail = await widget.apiClient.getFellowshipGroupDetail(_currentGroup.id);
      if (!mounted || !_isSessionValid || capturedSession != _sessionGeneration) {
        return;
      }
      setState(() {
        _currentGroup = _currentGroup.copyWith(
          members: detail.members,
          posts: detail.posts,
          memberCount: detail.memberCount,
          isUserMember: detail.isUserMember,
          description: detail.description,
          leaderName: detail.leaderName ?? _currentGroup.leaderName,
          meetingSchedule: detail.meetingSchedule ?? _currentGroup.meetingSchedule,
          location: detail.location ?? _currentGroup.location,
        );
        _isLoadingDetail = false;
      });
      widget.onGroupUpdated(_currentGroup);
    } catch (_) {
      if (!mounted || !_isSessionValid) return;
      setState(() => _isLoadingDetail = false);
    }
  }

  Future<void> _toggleMembership() async {
    if (!_isSessionValid) return;
    final willJoin = !_currentGroup.isUserMember;
    try {
      final success = willJoin
          ? await widget.apiClient.joinFellowshipGroup(_currentGroup.id)
          : await widget.apiClient.leaveFellowshipGroup(_currentGroup.id);

      if (!success) {
        if (mounted && _isSessionValid) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(willJoin
                  ? 'Failed to join space. Please check permissions.'
                  : 'Failed to leave space.'),
            ),
          );
        }
        return;
      }

      if (!mounted || !_isSessionValid) return;
      setState(() {
        _currentGroup = _currentGroup.copyWith(
          isUserMember: willJoin,
          memberCount: willJoin
              ? _currentGroup.memberCount + 1
              : (_currentGroup.memberCount > 0 ? _currentGroup.memberCount - 1 : 0),
        );
      });
      widget.onGroupUpdated(_currentGroup);

      // Perform canonical reload after success
      await _fetchDetail();
    } catch (e) {
      if (!mounted || !_isSessionValid) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: $e')),
      );
    }
  }

  void _openCreatePostDialog() {
    if (!_isSessionValid) return;
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final capturedSession = _sessionGeneration;
    final client = widget.apiClient;

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
                final created = await client.createPost(
                  _currentGroup.id,
                  title: titleController.text.trim(),
                  content: contentController.text.trim(),
                );
                if (!mounted || !_isSessionValid || capturedSession != _sessionGeneration) {
                  return;
                }
                setState(() {
                  _currentGroup = _currentGroup.copyWith(
                    posts: [created, ..._currentGroup.posts],
                  );
                });
                widget.onGroupUpdated(_currentGroup);
                final nav = Navigator.maybeOf(context);
                if (nav != null && nav.canPop()) {
                  nav.pop();
                }
              } catch (e) {
                if (!mounted || !_isSessionValid || capturedSession != _sessionGeneration) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to post: $e')),
                );
                final nav = Navigator.maybeOf(context);
                if (nav != null && nav.canPop()) {
                  nav.pop();
                }
              }
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
                          ? RefreshIndicator(
                              onRefresh: _fetchDetail,
                              child: CustomScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                slivers: [
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: Center(
                                      child: Text(
                                        'No messages yet. Start the conversation!',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .outline),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchDetail,
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
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
                RefreshIndicator(
                  onRefresh: _fetchDetail,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                ),
              ],
            ),
    );
  }
}
