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
import '../theme/app_theme.dart';

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
  int _fetchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _fetchAnnouncements();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.announcementClient != widget.announcementClient) {
      _fetchGeneration++;
      _announcements = [];
      _error = null;
      _isLoading = false;
      if (widget.announcementClient != null) {
        _fetchAnnouncements();
      }
    }
  }

  Future<void> _fetchAnnouncements() async {
    final client = widget.announcementClient;
    if (client == null) return;

    final int generation = ++_fetchGeneration;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final announcements = await client.getAnnouncements();
      if (!mounted || generation != _fetchGeneration) return;
      setState(() {
        _announcements = announcements;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || generation != _fetchGeneration) return;
      setState(() {
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
        _isLoading = false;
      });
    }
  }

  Future<void> _handlePublish(CreateAnnouncementInput input) async {
    if (widget.announcementClient == null) {
      throw StateError('Announcement client is not initialized.');
    }
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
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [SanctuaryColors.navy, SanctuaryColors.navyDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.church_outlined, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Church Sanctuary',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Weekly updates, celebrations, and ministry giving.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.celebrationClient != null) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: SanctuaryColors.goldSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.cake_outlined, color: SanctuaryColors.gold),
                  ),
                  title: const Text(
                    'Celebrations & Blessings',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Share birthdays, anniversaries & scripture blessings.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right, color: SanctuaryColors.inkMuted),
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
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: SanctuaryColors.sageSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.volunteer_activism_outlined, color: SanctuaryColors.sage),
                  ),
                  title: const Text(
                    'Digital Offerings & Giving',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Give securely via UPI and view receipts.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right, color: SanctuaryColors.inkMuted),
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
              const SizedBox(height: 22),
              SanctuarySectionHeader(
                title: 'Announcements',
                trailing: _announcements.isNotEmpty
                    ? SanctuaryStatusBadge(
                        label: '${_announcements.length}',
                        foregroundColor: SanctuaryColors.navy,
                        backgroundColor: SanctuaryColors.navySoft,
                      )
                    : null,
              ),
              const SizedBox(height: 10),
              if (_isLoading && _announcements.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_error != null && _announcements.isEmpty)
                SanctuaryEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Unable to Load Announcements',
                  description: _error!,
                  accentColor: Theme.of(context).colorScheme.error,
                  accentBackground: Theme.of(context).colorScheme.errorContainer,
                  action: FilledButton.icon(
                    onPressed: _fetchAnnouncements,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                )
              else if (_announcements.isEmpty)
                const SanctuaryEmptyState(
                  icon: Icons.campaign_outlined,
                  title: 'All Caught Up',
                  description: 'No announcements yet.',
                )
              else
                ..._announcements.map((announcement) {
                  final isEmergency = announcement.priority == AnnouncementPriority.emergency;
                  final isUrgent = announcement.priority == AnnouncementPriority.urgent;
                  final badgeFg = isEmergency
                      ? const Color(0xFF991B1B)
                      : (isUrgent ? const Color(0xFF9A5B13) : SanctuaryColors.navy);
                  final badgeBg = isEmergency
                      ? const Color(0xFFFEE2E2)
                      : (isUrgent ? SanctuaryColors.goldSoft : SanctuaryColors.navySoft);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: SanctuaryColors.ink,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              if (announcement.priority != AnnouncementPriority.routine) ...[
                                const SizedBox(width: 8),
                                SanctuaryStatusBadge(
                                  label: announcement.priority.displayName,
                                  foregroundColor: badgeFg,
                                  backgroundColor: badgeBg,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.schedule, size: 13, color: SanctuaryColors.inkMuted),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat.yMMMd().add_jm().format(announcement.publishedAt.toLocal()),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: SanctuaryColors.inkMuted,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            announcement.content,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: SanctuaryColors.ink.withValues(alpha: 0.9),
                                  height: 1.45,
                                ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
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
