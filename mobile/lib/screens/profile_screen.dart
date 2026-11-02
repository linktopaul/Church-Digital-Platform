import 'package:flutter/material.dart';
import '../auth/auth_session_manager.dart';
import '../models/member_models.dart';
import '../services/member_api_client.dart';

/// Screen for viewing and managing member profile, privacy rules, and church directory.
///
/// Guardrails:
/// - Fails closed: If [apiClient] is null, displays an explicit unauthenticated state.
/// - Privacy-first: Redacted fields are masked; updates strictly enforce server validation.
/// - Multi-tenant isolation: No cross-tenant data leakage; all requests use authenticated client.
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
  List<DirectoryMember> _directory = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';

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
    if (oldWidget.apiClient != widget.apiClient) {
      _myProfile = null;
      _directory = [];
      _errorMessage = null;
      if (widget.apiClient != null) {
        _loadData();
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final client = widget.apiClient;
    if (client == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profileFuture = client.getMyProfile();
      final directoryFuture = client.getDirectory();

      final results = await Future.wait([profileFuture, directoryFuture]);
      if (!mounted) return;

      setState(() {
        _myProfile = results[0] as MemberProfile;
        _directory = results[1] as List<DirectoryMember>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is MemberApiException ? e.message : 'Failed to load member profile.';
      });
    }
  }

  Future<void> _saveProfile(UpdateMemberProfileInput input) async {
    final client = widget.apiClient;
    if (client == null) return;

    setState(() => _isLoading = true);

    try {
      final updated = await client.updateMyProfile(input);
      if (!mounted) return;
      setState(() {
        _myProfile = updated;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
      // Reload directory to reflect updated privacy/names
      final dir = await client.getDirectory();
      if (mounted) {
        setState(() => _directory = dir);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is MemberApiException ? e.message : 'Failed to update profile.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _showEditProfileDialog() {
    final profile = _myProfile;
    if (profile == null) return;

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
                    const SizedBox(height: 12),
                    const Text(
                      'Privacy Opt-In Controls',
                      style: TextStyle(fontWeight: FontWeight.bold),
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
                        address: addressController.text.trim().isEmpty ? null : addressController.text.trim(),
                        dateOfBirth: profile.dateOfBirth,
                        anniversaryDate: profile.anniversaryDate,
                        directoryVisibility: selectedVisibility,
                        showEmail: showEmail,
                        showPhoneNumber: showPhone,
                        showAddress: showAddress,
                        showBirthday: showBirthday,
                      ),
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

  Widget _buildMyProfileTab() {
    final profile = _myProfile;
    if (profile == null) {
      if (_errorMessage != null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _loadData, child: const Text('Retry')),
            ],
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
                  onPressed: _showEditProfileDialog,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit Profile'),
                ),
              ),
              const SizedBox(width: 12),
              if (widget.authService != null)
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      await widget.authService?.signOut();
                    },
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
    final filtered = _directory.where((m) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return m.fullName.toLowerCase().contains(q) ||
          (m.email?.toLowerCase().contains(q) ?? false) ||
          (m.familyName?.toLowerCase().contains(q) ?? false);
    }).toList();

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
            onChanged: (val) {
              setState(() => _searchQuery = val.trim());
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: filtered.isEmpty
                ? const Center(child: Text('No members found in directory.'))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final member = filtered[index];
                      final initials = (member.firstName.isNotEmpty ? member.firstName[0] : '') +
                          (member.lastName.isNotEmpty ? member.lastName[0] : '');

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                            child: Text(initials.toUpperCase()),
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
                              if (member.email == null && member.phoneNumber == null)
                                const Text(
                                  'Contact details unlisted',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                            ],
                          ),
                          trailing: Chip(
                            label: Text(
                              member.directoryVisibility.label,
                              style: const TextStyle(fontSize: 10),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      );
                    },
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
