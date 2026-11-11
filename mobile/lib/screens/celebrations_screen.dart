import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/celebration_models.dart';
import '../services/celebration_api_client.dart';
import '../theme/app_theme.dart';

/// Screen displaying today's and upcoming church member celebrations
/// (birthdays and wedding anniversaries) with scripture blessing actions.
class CelebrationsScreen extends StatefulWidget {
  final CelebrationApiClient? apiClient;
  final bool isPastor;
  final Future<bool> Function(String url)? onLaunchUrl;

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

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.apiClient != null) {
      _loadCelebrations();
    }
  }

  @override
  void didUpdateWidget(covariant CelebrationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiClient != widget.apiClient) {
      _errorMessage = null;
      _todayCelebrations = [];
      _upcomingCelebrations = [];
      _templates = [];
      if (widget.apiClient != null) {
        _loadCelebrations();
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatCelebrationDate(DateTime date) {
    final month = (date.month >= 1 && date.month <= 12)
        ? _monthNames[date.month - 1]
        : '';
    return '$month ${date.day}';
  }

  String _sanitizeErrorMessage(dynamic e) {
    if (e is CelebrationApiException) {
      if (e.statusCode == 401) {
        return 'Your session has expired. Please sign in again.';
      }
      if (e.statusCode == 403) {
        return 'Access denied. You do not have permission to view celebrations.';
      }
      // Avoid leaking raw endpoint bodies or stack traces
      if (e.message.toLowerCase().contains('401') || e.message.toLowerCase().contains('unauthorized')) {
        return 'Your session has expired. Please sign in again.';
      }
      if (e.message.toLowerCase().contains('403') || e.message.toLowerCase().contains('forbidden')) {
        return 'Access denied. You do not have permission to view celebrations.';
      }
      return e.message;
    }
    final str = e.toString().toLowerCase();
    if (str.contains('401') || str.contains('unauthorized')) {
      return 'Your session has expired. Please sign in again.';
    }
    if (str.contains('403') || str.contains('forbidden') || str.contains('access denied')) {
      return 'Access denied. You do not have permission to view celebrations.';
    }
    return 'Failed to load celebrations. Please try again.';
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
          _errorMessage = _sanitizeErrorMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  void _showBlessingModal(CelebrationEvent celebration) {
    final matchingTemplates = _templates
        .where((t) => t.type == celebration.type)
        .toList();
    final formattedDate = _formatCelebrationDate(celebration.date);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: SingleChildScrollView(
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
                    '$formattedDate • ${celebration.milestoneLabel}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                          fontWeight: FontWeight.w500,
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

                          var launched = false;
                          if (widget.onLaunchUrl != null) {
                            launched = await widget.onLaunchUrl!(urlString);
                          } else {
                            try {
                              final uri = Uri.parse(urlString);
                              if (await canLaunchUrl(uri)) {
                                launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            } catch (_) {
                              launched = false;
                            }
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildCelebrationTile(CelebrationEvent celebration, {bool showDate = false}) {
    final isBirthday = celebration.type == CelebrationType.birthday;
    final icon = isBirthday ? Icons.cake_outlined : Icons.favorite_border;
    final color = isBirthday ? SanctuaryColors.gold : const Color(0xFFB83B5E);
    final bg = isBirthday ? SanctuaryColors.goldSoft : const Color(0xFFFCEEF2);
    final subtitleText = showDate
        ? '${_formatCelebrationDate(celebration.date)} • ${celebration.milestoneLabel}'
        : celebration.milestoneLabel;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
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
              subtitleText,
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

  Widget _buildCelebrationList(
    List<CelebrationEvent> items,
    String emptyMessage, {
    bool showDate = false,
  }) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadCelebrations,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SanctuaryEmptyState(
                    icon: Icons.cake_outlined,
                    title: 'No Celebrations Found',
                    description: emptyMessage,
                    accentColor: SanctuaryColors.gold,
                    accentBackground: SanctuaryColors.goldSoft,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCelebrations,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        itemBuilder: (context, index) => _buildCelebrationTile(
          items[index],
          showDate: showDate,
        ),
      ),
    );
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
              'Please sign in to view church celebrations.',
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
              'Unable to Load Celebrations',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'An error occurred while connecting to the celebration service.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadCelebrations,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.apiClient == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Celebrations & Blessings')),
        body: _buildUnauthenticatedState(),
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
              ? _buildErrorState()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCelebrationList(
                      _todayCelebrations,
                      'No celebrations today. Check back tomorrow!',
                      showDate: false,
                    ),
                    _buildCelebrationList(
                      _upcomingCelebrations,
                      'No upcoming celebrations this week.',
                      showDate: true,
                    ),
                  ],
                ),
    );
  }
}
