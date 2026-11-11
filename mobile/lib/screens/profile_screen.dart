import 'package:flutter/material.dart';
import '../auth/auth_session_manager.dart';
import '../models/member_models.dart';
import '../services/member_api_client.dart';

/// Screen for viewing and managing member profile, privacy rules, and church directory.
///
/// Guardrails:
/// - Fails closed: If [apiClient] is null, displays an explicit unauthenticated state.
/// - Privacy-first: Redacted fields are masked; updates strictly enforce server validation.
/// - Session isolation: Guard all asynchronous load/save completions with client identity, session generation,
///   and separate profile/directory generations to prevent cross-tenant and cross-tab race conditions.
class ProfileScreen extends StatefulWidget {
  final MemberApiClient? apiClient;
  final AuthService? authService;
  final bool isPastor;

  const ProfileScreen({
    super.key,
    this.apiClient,
    this.authService,
    this.isPastor = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  MemberProfile? _myProfile;
  FamilyData? _familyData;
  bool _isLoadingFamily = false;
  String? _familyErrorMessage;
  List<DirectoryMember> _directory = [];
  bool _isLoading = false;
  bool _isSavingProfile = false;
  bool _isLoadingMoreDirectory = false;
  bool _isSearchingOrRefreshingDirectory = false;
  bool _hasMoreDirectory = true;
  int _directoryPage = 1;
  static const int _pageSize = 50;
  String? _errorMessage;
  String _searchQuery = '';
  String _lastInputQuery = '';

  int _sessionGeneration = 0;
  int _profileMutationGeneration = 0;
  int _directoryLoadGeneration = 0;
  int _familyLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.apiClient != null) {
      _loadData();
    }
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient || oldWidget.authService != widget.authService) {
      _resetSessionState();
      if (widget.apiClient != null) {
        _loadData();
      }
    }
  }

  void _resetSessionState() {
    _sessionGeneration++;
    _directoryLoadGeneration++;
    _profileMutationGeneration++;
    _familyLoadGeneration++;
    _myProfile = null;
    _familyData = null;
    _isLoadingFamily = false;
    _familyErrorMessage = null;
    _directory = [];
    _directoryPage = 1;
    _hasMoreDirectory = true;
    _isLoadingMoreDirectory = false;
    _isSearchingOrRefreshingDirectory = false;
    _isSavingProfile = false;
    _searchQuery = '';
    _lastInputQuery = '';
    _errorMessage = null;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final client = widget.apiClient;
    if (client == null) return;

    final sessionGen = _sessionGeneration;
    final profileGen = _profileMutationGeneration;
    final dirGen = ++_directoryLoadGeneration;

    setState(() {
      _isLoading = true;
      _isLoadingMoreDirectory = false;
      _isSearchingOrRefreshingDirectory = true;
      _errorMessage = null;
    });

    final queryToFetch = _lastInputQuery;
    try {
      final profileFuture = client.getMyProfile();
      final directoryFuture = client.getDirectory(
        search: queryToFetch.isEmpty ? null : queryToFetch,
        page: 1,
        pageSize: _pageSize,
      );

      final results = await Future.wait([profileFuture, directoryFuture]);
      if (!mounted || sessionGen != _sessionGeneration || client != widget.apiClient) return;

      final fetchedProfile = results[0] as MemberProfile;
      final fetchedDir = results[1] as List<DirectoryMember>;

      if (profileGen == _profileMutationGeneration) {
        _myProfile = fetchedProfile;
        if (fetchedProfile.familyId != null && fetchedProfile.familyId!.isNotEmpty) {
          _loadFamily(fetchedProfile.familyId!);
        } else {
          _familyData = null;
          _familyErrorMessage = null;
        }
      }

      setState(() {
        if (dirGen == _directoryLoadGeneration) {
          _searchQuery = queryToFetch;
          _directory = fetchedDir;
          _hasMoreDirectory = fetchedDir.length >= _pageSize;
          _directoryPage = 1;
          _isSearchingOrRefreshingDirectory = false;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || sessionGen != _sessionGeneration || client != widget.apiClient) return;
      setState(() {
        _isLoading = false;
        if (dirGen == _directoryLoadGeneration) {
          _isSearchingOrRefreshingDirectory = false;
        }
        _errorMessage = e is MemberApiException ? e.message : 'Failed to load member profile.';
      });
    }
  }

  Future<void> _loadFamily(String familyId) async {
    final client = widget.apiClient;
    if (client == null) return;

    final sessionGen = _sessionGeneration;
    final famGen = ++_familyLoadGeneration;

    setState(() {
      _isLoadingFamily = true;
      _familyErrorMessage = null;
    });

    try {
      final family = await client.getFamily(familyId);
      if (!mounted || sessionGen != _sessionGeneration || famGen != _familyLoadGeneration || client != widget.apiClient) return;

      setState(() {
        _familyData = family;
        _isLoadingFamily = false;
        _familyErrorMessage = null;
      });
    } catch (e) {
      if (!mounted || sessionGen != _sessionGeneration || famGen != _familyLoadGeneration || client != widget.apiClient) return;
      setState(() {
        _isLoadingFamily = false;
        _familyErrorMessage = e is MemberApiException ? e.message : 'Failed to load family details.';
      });
    }
  }

  Future<void> _searchDirectory(String query) async {
    final client = widget.apiClient;
    if (client == null) return;

    final sessionGen = _sessionGeneration;
    final dirGen = ++_directoryLoadGeneration;
    final cleanQuery = query.trim();
    _lastInputQuery = cleanQuery;

    setState(() {
      _isLoadingMoreDirectory = false;
      _isSearchingOrRefreshingDirectory = true;
    });

    try {
      final fetchedDir = await client.getDirectory(
        search: cleanQuery.isEmpty ? null : cleanQuery,
        page: 1,
        pageSize: _pageSize,
      );
      if (!mounted || sessionGen != _sessionGeneration || dirGen != _directoryLoadGeneration || client != widget.apiClient) return;

      setState(() {
        _searchQuery = cleanQuery;
        _directory = fetchedDir;
        _directoryPage = 1;
        _hasMoreDirectory = fetchedDir.length >= _pageSize;
        _isSearchingOrRefreshingDirectory = false;
      });
    } catch (e) {
      if (!mounted || sessionGen != _sessionGeneration || dirGen != _directoryLoadGeneration || client != widget.apiClient) return;
      setState(() {
        _isSearchingOrRefreshingDirectory = false;
        _hasMoreDirectory = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is MemberApiException ? e.message : 'Directory search failed.')),
      );
    }
  }

  Future<void> _loadMoreDirectory() async {
    final client = widget.apiClient;
    if (client == null || _isLoadingMoreDirectory || _isSearchingOrRefreshingDirectory || !_hasMoreDirectory) return;

    final sessionGen = _sessionGeneration;
    final dirGen = _directoryLoadGeneration;
    setState(() => _isLoadingMoreDirectory = true);

    final nextPage = _directoryPage + 1;
    try {
      final moreMembers = await client.getDirectory(
        search: _searchQuery.isEmpty ? null : _searchQuery,
        page: nextPage,
        pageSize: _pageSize,
      );
      if (!mounted || sessionGen != _sessionGeneration || dirGen != _directoryLoadGeneration || client != widget.apiClient) return;

      setState(() {
        _directory.addAll(moreMembers);
        _directoryPage = nextPage;
        _hasMoreDirectory = moreMembers.length >= _pageSize;
        _isLoadingMoreDirectory = false;
      });
    } catch (e) {
      if (!mounted || sessionGen != _sessionGeneration || dirGen != _directoryLoadGeneration || client != widget.apiClient) return;
      setState(() => _isLoadingMoreDirectory = false);
    }
  }

  Future<void> _saveProfile(UpdateMemberProfileInput input, MemberApiClient boundClient) async {
    if (widget.apiClient != boundClient || widget.apiClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session changed. Profile changes discarded.')),
      );
      return;
    }

    final sessionGen = _sessionGeneration;
    final profileMutationGen = ++_profileMutationGeneration;

    setState(() {
      _isLoading = true;
      _isSavingProfile = true;
    });

    try {
      final updated = await boundClient.updateMyProfile(input);
      if (!mounted || sessionGen != _sessionGeneration || profileMutationGen != _profileMutationGeneration || boundClient != widget.apiClient) return;

      setState(() {
        _myProfile = updated;
        _isLoading = false;
        _isSavingProfile = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );

      // If family association is present, reload family details as well
      if (updated.familyId != null && updated.familyId!.isNotEmpty) {
        _loadFamily(updated.familyId!);
      } else {
        setState(() {
          _familyData = null;
          _familyErrorMessage = null;
        });
      }

      // Trigger directory reload under directory generation guard
      final dirGen = ++_directoryLoadGeneration;
      setState(() {
        _isLoadingMoreDirectory = false;
        _isSearchingOrRefreshingDirectory = true;
      });

      final queryToFetch = _lastInputQuery;
      try {
        final dir = await boundClient.getDirectory(
          search: queryToFetch.isEmpty ? null : queryToFetch,
          page: 1,
          pageSize: _pageSize,
        );
        if (mounted && sessionGen == _sessionGeneration && dirGen == _directoryLoadGeneration && boundClient == widget.apiClient) {
          setState(() {
            _searchQuery = queryToFetch;
            _directory = dir;
            _directoryPage = 1;
            _hasMoreDirectory = dir.length >= _pageSize;
            _isSearchingOrRefreshingDirectory = false;
          });
        }
      } catch (_) {
        if (mounted && sessionGen == _sessionGeneration && dirGen == _directoryLoadGeneration && boundClient == widget.apiClient) {
          setState(() {
            _isSearchingOrRefreshingDirectory = false;
          });
        }
      }
    } catch (e) {
      if (!mounted || sessionGen != _sessionGeneration || profileMutationGen != _profileMutationGeneration || boundClient != widget.apiClient) return;
      setState(() {
        _isLoading = false;
        _isSavingProfile = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is MemberApiException ? e.message : 'Failed to update profile.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _showEditProfileDialog() {
    if (_isSavingProfile) return;
    final profile = _myProfile;
    final dialogClient = widget.apiClient;
    final dialogSessionGen = _sessionGeneration;
    if (profile == null || dialogClient == null) return;

    final firstNameController = TextEditingController(text: profile.firstName);
    final lastNameController = TextEditingController(text: profile.lastName);
    final phoneController = TextEditingController(text: profile.phoneNumber ?? '');
    final addressController = TextEditingController(text: profile.address ?? '');

    DirectoryVisibility selectedVisibility = profile.directoryVisibility;
    bool showEmail = profile.showEmail;
    bool showPhone = profile.showPhoneNumber;
    bool showAddress = profile.showAddress;
    bool showBirthday = profile.showBirthday;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Profile & Privacy'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: firstNameController,
                      decoration: const InputDecoration(labelText: 'First Name *'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: lastNameController,
                      decoration: const InputDecoration(labelText: 'Last Name *'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(labelText: 'Phone Number'),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: addressController,
                      decoration: const InputDecoration(labelText: 'Address'),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Directory Visibility',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Controls who can see your name in the church member directory.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    DropdownButton<DirectoryVisibility>(
                      value: selectedVisibility,
                      isExpanded: true,
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedVisibility = val);
                        }
                      },
                      items: DirectoryVisibility.values.map((v) {
                        return DropdownMenuItem(
                          value: v,
                          child: Text(v.label),
                        );
                      }).toList(),
                    ),
                    if (selectedVisibility == DirectoryVisibility.private)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          'Your profile will be hidden from the member directory list.',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'Privacy Opt-In Controls',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'By default, all contact details are hidden until you choose to share them.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    SwitchListTile(
                      title: const Text('Show Email in Directory'),
                      value: showEmail,
                      onChanged: (val) => setDialogState(() => showEmail = val),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      title: const Text('Show Phone in Directory'),
                      value: showPhone,
                      onChanged: (val) => setDialogState(() => showPhone = val),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      title: const Text('Show Address in Directory'),
                      value: showAddress,
                      onChanged: (val) => setDialogState(() => showAddress = val),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      title: const Text('Show Birthday in Directory'),
                      value: showBirthday,
                      onChanged: (val) => setDialogState(() => showBirthday = val),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    // Check dialog was opened for the current session
                    if (widget.apiClient != dialogClient || _sessionGeneration != dialogSessionGen) {
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Session changed. Profile changes discarded.')),
                      );
                      return;
                    }

                    final first = firstNameController.text.trim();
                    final last = lastNameController.text.trim();
                    if (first.isEmpty || last.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('First and last name are required.')),
                      );
                      return;
                    }
                    Navigator.of(ctx).pop();
                    _saveProfile(
                      UpdateMemberProfileInput(
                        firstName: first,
                        lastName: last,
                        phoneNumber: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                        avatarUrl: profile.avatarUrl,
                        address: addressController.text.trim().isEmpty ? null : addressController.text.trim(),
                        dateOfBirth: profile.dateOfBirth,
                        anniversaryDate: profile.anniversaryDate,
                        directoryVisibility: selectedVisibility,
                        showEmail: showEmail,
                        showPhoneNumber: showPhone,
                        showAddress: showAddress,
                        showBirthday: showBirthday,
                      ),
                      dialogClient,
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmAndSignOut() async {
    final auth = widget.authService;
    if (auth == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text(
          'Are you sure you want to sign out? Your cached profile and church directory access will be cleared from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Clear sensitive profile/family/directory state immediately
      setState(() {
        _resetSessionState();
      });
      await auth.signOut();
    }
  }

  Widget _buildUnauthenticatedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_circle_outlined,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Sign In Required',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please sign in with your church member account to access your profile, family connections, and church directory.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Use OIDC Sign-In configured by your church administrator.')),
                );
              },
              icon: const Icon(Icons.login),
              label: const Text('Sign In'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFamilyCard(MemberProfile profile) {
    if (_isLoadingFamily && _familyData == null) {
      return Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: const [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Loading family unit...'),
            ],
          ),
        ),
      );
    }

    if (_familyErrorMessage != null && _familyData == null) {
      return Card(
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _familyErrorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  if (profile.familyId != null) {
                    _loadFamily(profile.familyId!);
                  }
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry Family'),
              ),
            ],
          ),
        ),
      );
    }

    final family = _familyData;
    final familyName = family?.familyName ?? profile.familyName ?? 'Family';
    final members = family?.members ?? [];

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.family_restroom, size: 20),
                const SizedBox(width: 8),
                Text(
                  familyName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            if (members.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('No other family members listed.', style: TextStyle(color: Colors.grey)),
              )
            else
              ...members.map((m) {
                final isCurrentMember = m.id == profile.id;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      m.fullName.isNotEmpty ? m.fullName[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        m.fullName,
                        style: TextStyle(
                          fontWeight: isCurrentMember ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (isCurrentMember) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('You', style: TextStyle(fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${m.familyRole.label}${m.email != null ? ' • ${m.email}' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildMyProfileTab() {
    final profile = _myProfile;
    if (profile == null) {
      if (_errorMessage != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _errorMessage!.contains('Authentication') || _errorMessage!.contains('401')
                      ? Icons.lock_outline
                      : Icons.error_outline,
                  color: Colors.red,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      }
      return const Center(child: Text('No profile found.'));
    }

    final initials = (profile.firstName.isNotEmpty ? profile.firstName[0] : '') +
        (profile.lastName.isNotEmpty ? profile.lastName[0] : '');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              initials.toUpperCase(),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            profile.fullName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            profile.email,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          if (profile.familyName != null) ...[
            const SizedBox(height: 8),
            Chip(
              avatar: const Icon(Icons.family_restroom, size: 16),
              label: Text('${profile.familyName} (${profile.familyRole.label})'),
            ),
          ],
          const SizedBox(height: 16),
          if (profile.familyId != null && profile.familyId!.isNotEmpty) ...[
            _buildFamilyCard(profile),
            const SizedBox(height: 12),
          ],
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Contact & Personal Details',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.phone_outlined),
                    title: const Text('Phone Number'),
                    subtitle: Text(profile.phoneNumber ?? 'Not provided'),
                  ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined),
                    title: const Text('Address'),
                    subtitle: Text(profile.address ?? 'Not provided'),
                  ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.cake_outlined),
                    title: const Text('Birthday'),
                    subtitle: Text(
                      profile.dateOfBirth != null
                          ? '${profile.dateOfBirth!.year}-${profile.dateOfBirth!.month.toString().padLeft(2, '0')}-${profile.dateOfBirth!.day.toString().padLeft(2, '0')}'
                          : 'Not provided',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Privacy Settings',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.visibility_outlined),
                    title: const Text('Directory Visibility'),
                    subtitle: Text(profile.directoryVisibility.label),
                  ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Contact Details Sharing'),
                    subtitle: Text(
                      [
                        if (profile.showEmail) 'Email',
                        if (profile.showPhoneNumber) 'Phone',
                        if (profile.showAddress) 'Address',
                        if (profile.showBirthday) 'Birthday',
                      ].isEmpty
                          ? 'All contact details hidden (Private)'
                          : 'Visible in Directory: ${[
                              if (profile.showEmail) 'Email',
                              if (profile.showPhoneNumber) 'Phone',
                              if (profile.showAddress) 'Address',
                              if (profile.showBirthday) 'Birthday',
                            ].join(', ')}',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSavingProfile ? null : _showEditProfileDialog,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Profile'),
                ),
              ),
              const SizedBox(width: 12),
              if (widget.authService != null)
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _confirmAndSignOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign Out'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search members by name or family...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onSubmitted: (val) {
              final trimmed = val.trim();
              _lastInputQuery = trimmed;
              _searchDirectory(trimmed);
            },
            onChanged: (val) {
              final trimmed = val.trim();
              if (trimmed != _lastInputQuery) {
                _lastInputQuery = trimmed;
                _searchDirectory(trimmed);
              }
            },
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (scrollInfo) {
              if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200 &&
                  !_isLoadingMoreDirectory &&
                  !_isSearchingOrRefreshingDirectory &&
                  _hasMoreDirectory) {
                _loadMoreDirectory();
              }
              return false;
            },
            child: RefreshIndicator(
              onRefresh: _loadData,
              child: _directory.isEmpty
                  ? const Center(child: Text('No members found in directory.'))
                  : ListView.builder(
                      itemCount: _directory.length + (_isLoadingMoreDirectory ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _directory.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final member = _directory[index];
                        final initial = member.fullName.isNotEmpty
                            ? member.fullName[0].toUpperCase()
                            : '?';

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                              child: Text(initial),
                            ),
                            title: Text(
                              member.fullName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (member.familyName != null)
                                  Text(
                                    '${member.familyName} (${member.familyRole.label})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                if (member.email != null && member.email!.isNotEmpty)
                                  Text('Email: ${member.email}', style: const TextStyle(fontSize: 12)),
                                if (member.phoneNumber != null && member.phoneNumber!.isNotEmpty)
                                  Text('Phone: ${member.phoneNumber}', style: const TextStyle(fontSize: 12)),
                                if (member.birthdayNotice != null && member.birthdayNotice!.isNotEmpty)
                                  Text('Birthday: ${member.birthdayNotice}', style: const TextStyle(fontSize: 12)),
                                if (member.email == null && member.phoneNumber == null)
                                  const Text(
                                    'Contact details unlisted',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                              ],
                            ),
                            trailing: member.directoryVisibility != null
                                ? Chip(
                                    label: Text(
                                      member.directoryVisibility!.label,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    padding: EdgeInsets.zero,
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.apiClient == null) {
      return _buildUnauthenticatedView();
    }

    if (_isLoading && _myProfile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'My Profile', icon: Icon(Icons.person, size: 20)),
            Tab(text: 'Directory', icon: Icon(Icons.people, size: 20)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMyProfileTab(),
          _buildDirectoryTab(),
        ],
      ),
    );
  }
}
