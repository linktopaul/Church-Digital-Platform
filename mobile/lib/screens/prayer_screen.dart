import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/prayer_models.dart';
import '../services/prayer_api_client.dart';

/// Screen for viewing and submitting confidential pastoral prayer requests.
///
/// Guardrails:
/// - Fails closed: If [apiClient] is null, renders an explicit sign-in / configuration state.
/// - Privacy: Content is marked confidential, never logged, and only visible according to permissions.
/// - Session isolation: Switching or clearing [apiClient] immediately purges cached confidential
///   requests, invalidates open submission sheets, and discards late prior-session responses.
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

class _PrayerScreenState extends State<PrayerScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final ValueNotifier<int> _sessionGenerationNotifier = ValueNotifier<int>(0);
  int _sessionGeneration = 0;
  int _loadGeneration = 0;
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
    final clientChanged = oldWidget.apiClient != widget.apiClient;
    final roleChanged = oldWidget.isPastor != widget.isPastor;

    if (roleChanged) {
      _tabController.dispose();
      _tabController = TabController(
        length: widget.isPastor ? 2 : 1,
        vsync: this,
      );
      if (!widget.isPastor) {
        _allRequests = [];
      }
    }

    if (clientChanged) {
      _sessionGeneration++;
      _sessionGenerationNotifier.value = _sessionGeneration;
      _loadGeneration++;
      _myRequests = [];
      _allRequests = [];
      _errorMessage = null;
      _isLoading = false;
    }

    if (widget.apiClient != null && (clientChanged || roleChanged)) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _sessionGeneration++;
    _sessionGenerationNotifier.value = _sessionGeneration;
    _sessionGenerationNotifier.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final client = widget.apiClient;
    if (client == null) return;

    final capturedSessionGen = _sessionGeneration;
    final capturedLoadGen = ++_loadGeneration;
    final capturedIsPastor = widget.isPastor;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final myReqs = await client.getMyPrayerRequests();
      if (!mounted ||
          capturedSessionGen != _sessionGeneration ||
          capturedLoadGen != _loadGeneration ||
          widget.apiClient != client) {
        return;
      }

      List<PrayerRequestData> allReqs = [];
      if (capturedIsPastor && widget.isPastor) {
        allReqs = await client.getAllPrayerRequests();
      }

      if (!mounted ||
          capturedSessionGen != _sessionGeneration ||
          capturedLoadGen != _loadGeneration ||
          widget.apiClient != client) {
        return;
      }

      setState(() {
        _myRequests = myReqs;
        _allRequests = widget.isPastor ? allReqs : [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted ||
          capturedSessionGen != _sessionGeneration ||
          capturedLoadGen != _loadGeneration ||
          widget.apiClient != client) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = e is PrayerApiException
            ? e.message
            : 'Failed to load prayer requests. Please try again.';
      });
    }
  }

  Future<PrayerRequestData> _submitRequestForSession({
    required PrayerApiClient originatingClient,
    required int originatingSessionGen,
    required String content,
  }) async {
    if (!mounted ||
        originatingSessionGen != _sessionGeneration ||
        widget.apiClient != originatingClient) {
      throw const PrayerApiException(
        'Session changed. Please sign in and submit your request again.',
        statusCode: 401,
      );
    }

    final created = await originatingClient.createPrayerRequest(
      CreatePrayerRequestInput(content: content),
    );

    if (!mounted ||
        originatingSessionGen != _sessionGeneration ||
        widget.apiClient != originatingClient) {
      throw const PrayerApiException(
        'Session changed while submitting prayer request.',
        statusCode: 401,
      );
    }

    // Invalidate any older in-flight GET started before this mutation completed
    // so a stale snapshot cannot overwrite the confirmed submission.
    final hadPendingLoad = _isLoading;
    _loadGeneration++;
    setState(() {
      _isLoading = false;
      _myRequests = [
        created,
        ..._myRequests.where((r) => r.id != created.id),
      ];
      if (widget.isPastor) {
        _allRequests = [
          created,
          ..._allRequests.where((r) => r.id != created.id),
        ];
      }
    });
    if (hadPendingLoad) {
      _loadData();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your prayer request was submitted confidentially.'),
      ),
    );

    return created;
  }

  void _openSubmitDialog() {
    final client = widget.apiClient;
    if (client == null) return;
    final capturedSessionGen = _sessionGeneration;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _PrayerSubmitBottomSheet(
        sessionGenerationListenable: _sessionGenerationNotifier,
        expectedSessionGeneration: capturedSessionGen,
        onSubmit: (content) => _submitRequestForSession(
          originatingClient: client,
          originatingSessionGen: capturedSessionGen,
          content: content,
        ),
      ),
    );
  }

  Future<void> _updateStatus(PrayerRequestData request, PrayerRequestStatus newStatus) async {
    final client = widget.apiClient;
    if (client == null) return;
    final capturedSessionGen = _sessionGeneration;

    try {
      final updated = await client.updatePrayerRequestStatus(
        request.id,
        UpdatePrayerRequestStatusInput(status: newStatus),
      );

      if (!mounted ||
          capturedSessionGen != _sessionGeneration ||
          widget.apiClient != client) {
        return;
      }

      // Invalidate any older in-flight GET started before this status mutation
      // completed so a stale snapshot cannot overwrite the confirmed status.
      final hadPendingLoad = _isLoading;
      _loadGeneration++;
      setState(() {
        _isLoading = false;
        _allRequests = _allRequests
            .map((r) => r.id == updated.id ? updated : r)
            .toList();
        _myRequests = _myRequests
            .map((r) => r.id == updated.id ? updated : r)
            .toList();
      });
      if (hadPendingLoad) {
        _loadData();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Prayer request status updated to ${newStatus.displayName}.'),
        ),
      );
    } catch (e) {
      if (!mounted ||
          capturedSessionGen != _sessionGeneration ||
          widget.apiClient != client) {
        return;
      }
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
      return RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(isPastorFeed: isPastorFeed),
            ),
          ],
        ),
      );
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
  final ValueListenable<int> sessionGenerationListenable;
  final int expectedSessionGeneration;
  final Future<PrayerRequestData> Function(String content) onSubmit;

  const _PrayerSubmitBottomSheet({
    required this.sessionGenerationListenable,
    required this.expectedSessionGeneration,
    required this.onSubmit,
  });

  @override
  State<_PrayerSubmitBottomSheet> createState() => _PrayerSubmitBottomSheetState();
}

class _PrayerSubmitBottomSheetState extends State<_PrayerSubmitBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  bool _isSubmitting = false;
  String? _submitError;

  bool get _isSessionValid =>
      widget.sessionGenerationListenable.value == widget.expectedSessionGeneration;

  @override
  void initState() {
    super.initState();
    widget.sessionGenerationListenable.addListener(_handleSessionGenerationChanged);
  }

  void _handleSessionGenerationChanged() {
    if (!_isSessionValid && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isSessionValid) return;
        final route = ModalRoute.of(context);
        if (route != null && route.isCurrent) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.sessionGenerationListenable.removeListener(_handleSessionGenerationChanged);
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isSessionValid) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await widget.onSubmit(_contentController.text.trim());

      if (mounted && _isSessionValid) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted && _isSessionValid) {
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