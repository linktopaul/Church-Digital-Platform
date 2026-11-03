import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/celebration_models.dart';
import '../services/celebration_api_client.dart';

/// Screen displaying today's and upcoming church member celebrations
/// (birthdays and wedding anniversaries) with scripture blessing actions.
class CelebrationsScreen extends StatefulWidget {
  final CelebrationApiClient? apiClient;
  final bool isPastor;
  final Future<void> Function(String url)? onLaunchUrl;

  const CelebrationsScreen({
    super.key,
    this.apiClient,
    this.isPastor = false,
    this.onLaunchUrl,
  });

  @override
  State<CelebrationsScreen> createState() => _CelebrationsScreenState();
}

class _CelebrationsScreenState extends State<CelebrationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = false;
  String? _errorMessage;
  List<CelebrationEvent> _todayCelebrations = [];
  List<CelebrationEvent> _upcomingCelebrations = [];
  List<BlessingTemplate> _templates = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCelebrations();
  }

  @override
  void didUpdateWidget(covariant CelebrationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient) {
      _loadCelebrations();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCelebrations() async {
    final client = widget.apiClient;
    if (client == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = null;
        _todayCelebrations = [];
        _upcomingCelebrations = [];
        _templates = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        client.getTodayCelebrations(),
        client.getUpcomingCelebrations(days: 7),
        client.getBlessingTemplates(),
      ]);

      if (mounted) {
        setState(() {
          _todayCelebrations = results[0] as List<CelebrationEvent>;
          _upcomingCelebrations = results[1] as List<CelebrationEvent>;
          _templates = results[2] as List<BlessingTemplate>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e is CelebrationApiException
              ? e.message
              : 'Failed to load celebrations. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  void _showBlessingModal(CelebrationEvent celebration) {
    final matchingTemplates = _templates
        .where((t) => t.type == celebration.type)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    celebration.type == CelebrationType.birthday
                        ? Icons.cake
                        : Icons.favorite,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bless ${celebration.memberName}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                celebration.milestoneLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Scripture Blessing Options:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (matchingTemplates.isEmpty)
                const Text('May the Lord bless and keep you always. (Numbers 6:24)')
              else
                ...matchingTemplates.map((template) {
                  final formattedMessage = template.formatGreeting(celebration.memberName);
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            template.title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(formattedMessage),
                          const SizedBox(height: 4),
                          Text(
                            template.defaultScripture,
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 16),
              if (celebration.canMessageDirectly && celebration.whatsAppUrl != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.chat),
                    label: const Text('Open in WhatsApp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final urlString = celebration.whatsAppUrl;
                      if (urlString == null) return;

                      if (widget.onLaunchUrl != null) {
                        await widget.onLaunchUrl!(urlString);
                        return;
                      }

                      var launched = false;
                      try {
                        final uri = Uri.parse(urlString);
                        if (await canLaunchUrl(uri)) {
                          launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      } catch (_) {
                        launched = false;
                      }

                      if (!launched) {
                        await Clipboard.setData(
                          ClipboardData(text: urlString),
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('WhatsApp blessing link copied to clipboard.'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              ] else ...[
                const Center(
                  child: Text(
                    'Contact details unlisted. Celebrate together in prayer!',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCelebrationTile(CelebrationEvent celebration) {
    final isBirthday = celebration.type == CelebrationType.birthday;
    final icon = isBirthday ? Icons.cake : Icons.favorite;
    final color = isBirthday ? Colors.deepPurple : Colors.pink;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(38),
          child: Icon(icon, color: color),
        ),
        title: Text(
          celebration.memberName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              celebration.milestoneLabel,
              style: TextStyle(color: color, fontWeight: FontWeight.w500),
            ),
            if (!celebration.canMessageDirectly)
              const Text(
                'Private Contact',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
          ],
        ),
        trailing: celebration.canMessageDirectly
            ? IconButton(
                icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF25D366)),
                tooltip: 'Send Blessing',
                onPressed: () => _showBlessingModal(celebration),
              )
            : IconButton(
                icon: const Icon(Icons.visibility_outlined),
                tooltip: 'View Blessing',
                onPressed: () => _showBlessingModal(celebration),
              ),
      ),
    );
  }

  Widget _buildCelebrationList(List<CelebrationEvent> items, String emptyMessage) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cake_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCelebrations,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        itemBuilder: (context, index) => _buildCelebrationTile(items[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.apiClient == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Celebrations & Blessings')),
        body: const Center(
          child: Text('Please sign in to view church celebrations.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Celebrations & Blessings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Today's Celebrations"),
            Tab(text: 'Upcoming (7 Days)'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadCelebrations,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCelebrationList(
                      _todayCelebrations,
                      'No celebrations today. Check back tomorrow!',
                    ),
                    _buildCelebrationList(
                      _upcomingCelebrations,
                      'No upcoming celebrations this week.',
                    ),
                  ],
                ),
    );
  }
}
