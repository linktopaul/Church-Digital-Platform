import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/announcement_models.dart';
import '../services/announcement_api_client.dart';
import '../services/celebration_api_client.dart';
import '../services/offering_api_client.dart';
import 'announcement_composer_screen.dart';
import 'celebrations_screen.dart';
import 'offerings_screen.dart';
import 'placeholder_screen.dart';

class HomeScreen extends StatefulWidget {
  final AnnouncementApiClient? announcementClient;
  final CelebrationApiClient? celebrationClient;
  final OfferingApiClient? offeringClient;
  final bool isPastor;
  final bool isAdmin;
  final bool canManageOfferings;
  final Future<bool> Function(String url)? onLaunchUrl;

  const HomeScreen({
    super.key,
    this.announcementClient,
    this.celebrationClient,
    this.offeringClient,
    this.isPastor = false,
    this.isAdmin = false,
    this.canManageOfferings = false,
    this.onLaunchUrl,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Announcement> _announcements = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAnnouncements();
  }

  Future<void> _fetchAnnouncements() async {
    if (widget.announcementClient == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final announcements = await widget.announcementClient!.getAnnouncements();
      if (mounted) {
        setState(() {
          _announcements = announcements;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handlePublish(CreateAnnouncementInput input) async {
    if (widget.announcementClient == null) return;
    await widget.announcementClient!.publishAnnouncement(input);
  }

  void _openComposer() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => AnnouncementComposerScreen(
          onSubmit: _handlePublish,
        ),
      ),
    );

    if (result == true) {
      _fetchAnnouncements();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.announcementClient == null && widget.celebrationClient == null && widget.offeringClient == null) {
      return const PlaceholderScreen(
        title: 'Welcome',
        description: 'Church announcements and updates will appear here.',
        icon: Icons.home_outlined,
      );
    }

    final bool canPublish = widget.isPastor || widget.isAdmin;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _fetchAnnouncements,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.home, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Welcome to Church Digital Platform',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('Church announcements and updates will appear here.'),
                  ],
                ),
              ),
            ),
            if (widget.celebrationClient != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer.withAlpha(80),
                elevation: 1,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.purple,
                    child: Icon(Icons.cake, color: Colors.white),
                  ),
                  title: const Text(
                    'Celebrations & Blessings',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Celebrate member birthdays and anniversaries with scripture blessings.',
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => CelebrationsScreen(
                          apiClient: widget.celebrationClient!,
                          isPastor: widget.isPastor,
                          onLaunchUrl: widget.onLaunchUrl,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (widget.offeringClient != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer.withAlpha(80),
                elevation: 1,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.teal,
                    child: Icon(Icons.volunteer_activism, color: Colors.white),
                  ),
                  title: const Text(
                    'Digital Offerings & Giving',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Support the church ministry with secure UPI giving and instant receipts.',
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => OfferingsScreen(
                          apiClient: widget.offeringClient!,
                          isPastor: widget.isPastor,
                          canManageOfferings: widget.canManageOfferings || widget.isPastor,
                          onLaunchUrl: widget.onLaunchUrl,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (widget.announcementClient != null) ...[
              const SizedBox(height: 24),
              Text(
                'Announcements',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (_isLoading && _announcements.isEmpty)
                const Center(child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ))
              else if (_error != null && _announcements.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _fetchAnnouncements,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_announcements.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text('No announcements yet.'),
                  ),
                )
              else
                ..._announcements.map((announcement) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  announcement.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                              if (announcement.priority != AnnouncementPriority.routine) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: announcement.priority == AnnouncementPriority.emergency
                                      ? Colors.red.shade100
                                      : Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    announcement.priority.displayName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: announcement.priority == AnnouncementPriority.emergency
                                        ? Colors.red.shade900
                                        : Colors.orange.shade900,
                                    ),
                                  ),
                                ),
                              ]
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat.yMMMd().add_jm().format(announcement.publishedAt.toLocal()),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                          Text(announcement.content),
                        ],
                      ),
                    ),
                  );
                }),
            ]
          ],
        ),
      ),
      floatingActionButton: canPublish
          ? FloatingActionButton(
              onPressed: _openComposer,
              tooltip: 'New Announcement',
              child: const Icon(Icons.add_alert),
            )
          : null,
    );
  }
}
