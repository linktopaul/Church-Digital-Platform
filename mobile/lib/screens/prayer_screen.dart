import 'package:flutter/material.dart';
import '../models/prayer_models.dart';
import '../services/prayer_api_client.dart';

/// Screen for viewing and submitting confidential pastoral prayer requests.
///
/// Guardrails:
/// - Fails closed: If [apiClient] is null, renders an explicit sign-in / configuration state.
/// - Privacy: Content is marked confidential, never logged, and only visible according to permissions.
/// - Status mutation: Pastor status controls reflect server authorization; non-pastor cannot mutate status.
/// - No optimistic writes: List and status updates only reflect confirmed server responses.
class PrayerScreen extends StatefulWidget {
  final PrayerApiClient? apiClient;
  final bool isPastor;

  const PrayerScreen({
    super.key,
    this.apiClient,
    this.isPastor = false,
  });

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  String? _errorMessage;
  List<PrayerRequestData> _myRequests = [];
  List<PrayerRequestData> _allRequests = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.isPastor ? 2 : 1,
      vsync: this,
    );
    if (widget.apiClient != null) {
      _loadData();
    }
  }

  @override
  void didUpdateWidget(covariant PrayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPastor != widget.isPastor) {
      _tabController.dispose();
      _tabController = TabController(
        length: widget.isPastor ? 2 : 1,
        vsync: this,
      );
    }
    if (oldWidget.apiClient != widget.apiClient && widget.apiClient != null) {
      _loadData();
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
      final myReqs = await client.getMyPrayerRequests();
      List<PrayerRequestData> allReqs = [];
      if (widget.isPastor) {
        allReqs = await client.getAllPrayerRequests();
      }

      if (mounted) {
        setState(() {
          _myRequests = myReqs;
          _allRequests = allReqs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e is PrayerApiException
              ? e.message
              : 'Failed to load prayer requests. Please try again.';
        });
      }
    }
  }

  void _openSubmitDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _PrayerSubmitBottomSheet(
        apiClient: widget.apiClient!,
        onSuccess: (newRequest) {
          setState(() {
            _myRequests = [newRequest, ..._myRequests];
            if (widget.isPastor) {
              _allRequests = [newRequest, ..._allRequests];
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your prayer request was submitted confidentially.'),
            ),
          );
        },
      ),
    );
  }

  Future<void> _updateStatus(PrayerRequestData request, PrayerRequestStatus newStatus) async {
    final client = widget.apiClient;
    if (client == null) return;

    try {
      final updated = await client.updatePrayerRequestStatus(
        request.id,
        UpdatePrayerRequestStatusInput(status: newStatus),
      );

      if (mounted) {
        setState(() {
          _allRequests = _allRequests
              .map((r) => r.id == updated.id ? updated : r)
              .toList();
          _myRequests = _myRequests
              .map((r) => r.id == updated.id ? updated : r)
              .toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Prayer request status updated to ${newStatus.displayName}.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PrayerApiException ? e.message : 'Failed to update prayer status.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
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
              'Confidential pastoral prayer requests require an active, authenticated member session.',
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

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(),
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
              'Unable to Load Requests',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'An error occurred while connecting to the prayer service.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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

  Widget _buildEmptyState({required bool isPastorFeed}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              isPastorFeed ? 'No Prayer Requests' : 'No Submitted Requests',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              isPastorFeed
                  ? 'There are currently no prayer requests submitted to the pastoral staff.'
                  : 'You have not submitted any prayer requests yet. Share your requests with our pastoral team confidentially.',
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

  Widget _buildStatusChip(PrayerRequestStatus status) {
    Color bg;
    Color fg;
    switch (status) {
      case PrayerRequestStatus.submitted:
        bg = Colors.amber.shade100;
        fg = Colors.amber.shade900;
        break;
      case PrayerRequestStatus.praying:
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade900;
        break;
      case PrayerRequestStatus.answered:
        bg = Colors.green.shade100;
        fg = Colors.green.shade900;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRequestCard(PrayerRequestData request, {required bool canManageStatus}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lock,
                      size: 14,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Confidential',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
                _buildStatusChip(request.status),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              request.content,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDate(request.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                if (canManageStatus)
                  PopupMenuButton<PrayerRequestStatus>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    tooltip: 'Change Status',
                    onSelected: (newStatus) => _updateStatus(request, newStatus),
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: PrayerRequestStatus.submitted,
                        child: Text('Mark as Submitted'),
                      ),
                      const PopupMenuItem(
                        value: PrayerRequestStatus.praying,
                        child: Text('Mark as Praying'),
                      ),
                      const PopupMenuItem(
                        value: PrayerRequestStatus.answered,
                        child: Text('Mark as Answered'),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Widget _buildList(List<PrayerRequestData> requests, {required bool isPastorFeed}) {
    if (requests.isEmpty) {
      return _buildEmptyState(isPastorFeed: isPastorFeed);
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: requests.length,
        itemBuilder: (context, index) {
          final req = requests[index];
          return _buildRequestCard(req, canManageStatus: widget.isPastor && isPastorFeed);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.apiClient == null) {
      return _buildUnauthenticatedState();
    }

    return Scaffold(
      appBar: widget.isPastor
          ? TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'My Requests', icon: Icon(Icons.person)),
                Tab(text: 'All Pastoral Requests', icon: Icon(Icons.admin_panel_settings)),
              ],
            )
          : null,
      body: _isLoading
          ? _buildLoadingState()
          : _errorMessage != null
              ? _buildErrorState()
              : widget.isPastor
                  ? TabBarView(
                      controller: _tabController,
                      children: [
                        _buildList(_myRequests, isPastorFeed: false),
                        _buildList(_allRequests, isPastorFeed: true),
                      ],
                    )
                  : _buildList(_myRequests, isPastorFeed: false),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSubmitDialog,
        icon: const Icon(Icons.add),
        label: const Text('Request Prayer'),
      ),
    );
  }
}

class _PrayerSubmitBottomSheet extends StatefulWidget {
  final PrayerApiClient apiClient;
  final void Function(PrayerRequestData newRequest) onSuccess;

  const _PrayerSubmitBottomSheet({
    required this.apiClient,
    required this.onSuccess,
  });

  @override
  State<_PrayerSubmitBottomSheet> createState() => _PrayerSubmitBottomSheetState();
}

class _PrayerSubmitBottomSheetState extends State<_PrayerSubmitBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final created = await widget.apiClient.createPrayerRequest(
        CreatePrayerRequestInput(content: _contentController.text.trim()),
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess(created);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submitError = e is PrayerApiException
              ? e.message
              : 'Failed to submit prayer request. Please check your connection.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        top: 24,
        left: 20,
        right: 20,
        bottom: bottomInset + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Confidential Prayer Request',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This request is strictly confidential and visible only to pastoral staff.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contentController,
                maxLines: 5,
                minLines: 3,
                decoration: const InputDecoration(
                  labelText: 'How can our pastors pray for you?',
                  hintText: 'Share your prayer needs here...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter your prayer request.';
                  }
                  return null;
                },
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _submitError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit Request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
