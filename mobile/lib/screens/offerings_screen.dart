import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/offering_models.dart';
import '../services/offering_api_client.dart';
import '../theme/app_theme.dart';

class OfferingsScreen extends StatefulWidget {
  final OfferingApiClient? apiClient;
  final bool isPastor;
  final bool canManageOfferings;
  final Future<bool> Function(String url)? onLaunchUrl;

  const OfferingsScreen({
    super.key,
    this.apiClient,
    this.isPastor = false,
    this.canManageOfferings = false,
    this.onLaunchUrl,
  });

  @override
  State<OfferingsScreen> createState() => _OfferingsScreenState();
}

class _OfferingsScreenState extends State<OfferingsScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  // Giving Form State
  ChurchGivingConfig? _config;
  OfferingFundType _selectedFund = OfferingFundType.generalOffering;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _utrController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  // My Contributions State
  List<Contribution> _myContributions = [];
  bool _isLoadingMyGiving = false;
  String? _myGivingError;

  // Pastoral Ledger State
  List<Contribution> _ledgerContributions = [];
  LedgerSummary? _ledgerSummary;
  bool _isLoadingLedger = false;
  String? _ledgerError;
  OfferingFundType? _ledgerFundFilter;

  bool get _hasLedgerAccess => widget.isPastor || widget.canManageOfferings;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _hasLedgerAccess ? 3 : 2,
      vsync: this,
    );
    _tabController.addListener(_handleTabChange);
    if (widget.apiClient != null) {
      _loadInitialData();
    }
  }

  @override
  void didUpdateWidget(covariant OfferingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clientChanged = oldWidget.apiClient != widget.apiClient;
    final accessChanged = (oldWidget.isPastor != widget.isPastor) ||
        (oldWidget.canManageOfferings != widget.canManageOfferings);

    if (accessChanged) {
      _tabController.removeListener(_handleTabChange);
      _tabController.dispose();
      _tabController = TabController(
        length: _hasLedgerAccess ? 3 : 2,
        vsync: this,
      );
      _tabController.addListener(_handleTabChange);
    }

    if (clientChanged) {
      _myContributions = [];
      _ledgerContributions = [];
      _ledgerSummary = null;
      _myGivingError = null;
      _ledgerError = null;
      _config = null;
      if (widget.apiClient != null) {
        _loadInitialData();
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _utrController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 1) {
      _loadMyContributions();
    } else if (_tabController.index == 2 && _hasLedgerAccess) {
      _loadLedger();
    }
  }

  String _sanitizeErrorMessage(dynamic e, {bool isLedger = false}) {
    if (e is OfferingApiException) {
      if (e.statusCode == 401) {
        return 'Your session has expired. Please sign in again.';
      }
      if (e.statusCode == 403) {
        return isLedger
            ? 'Access denied: Restricted to pastoral leadership or authorized staff.'
            : 'Access denied: You do not have permission for this action.';
      }
      return e.message;
    }
    final str = e.toString().toLowerCase();
    if (str.contains('401') || str.contains('unauthorized')) {
      return 'Your session has expired. Please sign in again.';
    }
    if (str.contains('403') || str.contains('forbidden') || str.contains('access denied')) {
      return isLedger
          ? 'Access denied: Restricted to pastoral leadership or authorized staff.'
          : 'Access denied: You do not have permission for this action.';
    }
    return isLedger
        ? 'Failed to load church contribution ledger. Please check your connection.'
        : 'Failed to load contribution records. Please check your connection.';
  }

  Future<void> _loadInitialData() async {
    await _loadConfig();
    if (!mounted) return;
    _loadMyContributions();
    if (_hasLedgerAccess) {
      _loadLedger();
    }
  }

  Future<void> _loadConfig() async {
    final client = widget.apiClient;
    if (client == null) return;

    try {
      final config = await client.getGivingConfig();
      if (mounted) {
        setState(() {
          _config = config;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMyContributions() async {
    if (!mounted) return;
    final client = widget.apiClient;
    if (client == null) return;

    setState(() {
      _isLoadingMyGiving = true;
      _myGivingError = null;
    });

    try {
      final list = await client.getMyContributions();
      if (mounted) {
        setState(() {
          _myContributions = list;
          _isLoadingMyGiving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _myGivingError = _sanitizeErrorMessage(e, isLedger: false);
          _isLoadingMyGiving = false;
        });
      }
    }
  }

  Future<void> _loadLedger() async {
    if (!mounted) return;
    final client = widget.apiClient;
    if (client == null || !_hasLedgerAccess) return;

    setState(() {
      _isLoadingLedger = true;
      _ledgerError = null;
    });

    try {
      final ledgerFuture = client.getLedger(fundType: _ledgerFundFilter);
      final summaryFuture = client.getLedgerSummary();

      final results = await Future.wait([ledgerFuture, summaryFuture]);
      if (mounted) {
        setState(() {
          _ledgerContributions = results[0] as List<Contribution>;
          _ledgerSummary = results[1] as LedgerSummary;
          _isLoadingLedger = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ledgerError = _sanitizeErrorMessage(e, isLedger: true);
          _isLoadingLedger = false;
        });
      }
    }
  }

  Future<void> _submitContribution() async {
    if (!_formKey.currentState!.validate()) return;

    final client = widget.apiClient;
    if (client == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your session has expired. Please sign in again.')),
      );
      return;
    }

    final parsedAmount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final amount = (parsedAmount * 100).round() / 100.0;
    if (amount < 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an amount of at least 0.01.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final recorded = await client.recordContribution(RecordContributionInput(
        fundType: _selectedFund,
        amount: amount,
        currency: _config?.currency ?? 'INR',
        paymentNote: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        transactionReference: _utrController.text.trim().isEmpty ? null : _utrController.text.trim(),
      ));

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _amountController.clear();
          _noteController.clear();
          _utrController.clear();
        });

        _showSuccessDialog(recorded);
        _loadMyContributions();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        final errorText = _sanitizeErrorMessage(e, isLedger: false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorText)),
        );
      }
    }
  }

  void _showSuccessDialog(Contribution contribution) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Contribution Intent Recorded',
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Receipt: ${contribution.receiptNumber}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
                  ),
                  const Divider(height: 24),
                  _buildSummaryRow('Fund', contribution.fundName),
                  _buildSummaryRow('Amount', '${contribution.currency} ${contribution.amount.toStringAsFixed(2)}'),
                  _buildSummaryRow('Status', contribution.status.displayName),
                  if (contribution.paymentNote != null && contribution.paymentNote!.isNotEmpty)
                    _buildSummaryRow('Note', contribution.paymentNote!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _launchUpi(contribution.upiIntentUri),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.payment),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Open UPI App to Complete Payment',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: contribution.upiPayeeId));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied UPI ID (${contribution.upiPayeeId}) to clipboard!')),
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.copy, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Copy Church UPI ID (${contribution.upiPayeeId})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _launchUpi(String uri) async {
    var launched = false;
    if (widget.onLaunchUrl != null) {
      launched = await widget.onLaunchUrl!(uri);
    } else {
      try {
        final parsed = Uri.parse(uri);
        if (await canLaunchUrl(parsed)) {
          launched = await launchUrl(parsed, mode: LaunchMode.externalApplication);
        }
      } catch (_) {
        launched = false;
      }
    }

    if (!launched) {
      Clipboard.setData(ClipboardData(text: uri));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open UPI app. Intent URI copied to clipboard.')),
        );
      }
    }
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _verifyContributionDialog(Contribution contribution) async {
    final noteCtrl = TextEditingController();
    final utrCtrl = TextEditingController(text: contribution.transactionReference ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verify Contribution'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Member: ${contribution.memberName}', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('Amount: ${contribution.currency} ${contribution.amount.toStringAsFixed(2)}'),
              Text('Receipt: ${contribution.receiptNumber}'),
              const SizedBox(height: 16),
              TextField(
                controller: utrCtrl,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Bank Reference / UTR',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Pastoral Audit Note (Optional)',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Verification'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final client = widget.apiClient;
        if (client != null) {
          await client.verifyContribution(
            contribution.id,
            transactionReference: utrCtrl.text.trim().isEmpty ? null : utrCtrl.text.trim(),
            verificationNote: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Contribution successfully verified.')),
            );
            _loadLedger();
          }
        }
      } catch (e) {
        if (mounted) {
          final errText = _sanitizeErrorMessage(e, isLedger: true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errText)),
          );
        }
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
              'Recording offerings, viewing receipts, and managing tithes require an active, authenticated member session.',
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
    if (widget.apiClient == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Digital Offerings & Giving'),
        ),
        body: _buildUnauthenticatedState(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Digital Offerings & Giving',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.bold),
            ),
            Text(
              'Caritas Romana · Oblationes & Eleemosynae',
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 11,
                letterSpacing: 0.8,
                color: BasilicaColors.burgundy.withAlpha(180),
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: BasilicaColors.burgundy,
          labelColor: BasilicaColors.burgundy,
          unselectedLabelColor: BasilicaColors.inkMuted,
          labelStyle: const TextStyle(fontFamily: 'serif', fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontFamily: 'serif'),
          tabs: [
            const Tab(text: 'Give Now'),
            const Tab(text: 'My Giving'),
            if (_hasLedgerAccess)
              const Tab(text: 'Ledger'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGiveTab(),
          _buildMyGivingTab(),
          if (_hasLedgerAccess) _buildLedgerTab(),
        ],
      ),
    );
  }

  Widget _buildGiveTab() {
    return RefreshIndicator(
      onRefresh: _loadConfig,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: BasilicaColors.stone,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: BasilicaColors.borderSoft),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: BasilicaColors.burgundy,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: BasilicaColors.gold.withAlpha(120)),
                        ),
                        child: const Icon(Icons.qr_code_2, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Support the Church Ministry',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'serif',
                                    color: BasilicaColors.burgundy,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _config != null
                                  ? 'UPI ID: ${_config!.upiId} (${_config!.payeeName})'
                                  : 'Give faithfully and cheerfully via UPI instant transfer.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: BasilicaColors.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<OfferingFundType>(
                isExpanded: true,
                initialValue: _selectedFund,
                decoration: const InputDecoration(
                  labelText: 'Select Ministry Fund',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: OfferingFundType.values.map((fund) {
                  return DropdownMenuItem(
                    value: fund,
                    child: Text(fund.displayName),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedFund = val);
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount (${_config?.currency ?? 'INR'})',
                  hintText: 'e.g. 500.00',
                  prefixIcon: const Icon(Icons.currency_rupee),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter an amount.';
                  }
                  final parsed = double.tryParse(val.trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a valid positive number.';
                  }
                  final rounded = (parsed * 100).round() / 100.0;
                  if (rounded < 0.01) {
                    return 'Amount must be at least 0.01.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [500, 1000, 2500, 5000]
                    .map(
                      (preset) => ActionChip(
                        label: Text('₹$preset'),
                        onPressed: () {
                          _amountController.text = '$preset';
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _noteController,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Note / Thanksgiving (Optional)',
                  hintText: 'e.g. Thanksgiving for family blessings',
                  prefixIcon: Icon(Icons.note_alt_outlined),
                  counterText: '',
                ),
                validator: (v) {
                  if (v != null && v.trim().length > 500) {
                    return 'Giving note cannot exceed 500 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _utrController,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Bank Reference / UTR (Optional)',
                  hintText: 'e.g. UPI Ref 1234567890 if already paid',
                  prefixIcon: Icon(Icons.numbers_outlined),
                  counterText: '',
                ),
                validator: (v) {
                  if (v != null && v.trim().length > 100) {
                    return 'Reference cannot exceed 100 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _isSubmitting ? null : _submitContribution,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_forward),
                            SizedBox(width: 8),
                            Text(
                              'Generate UPI Payment & Record',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyGivingTab() {
    if (_isLoadingMyGiving) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_myGivingError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 56),
              const SizedBox(height: 16),
              Text(
                'Unable to Load Giving Records',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _myGivingError!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadMyContributions,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_myContributions.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadMyContributions,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(
                        'No Contribution Records Yet',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your recorded tithes and offerings will appear here with instant receipts.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMyContributions,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _myContributions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, index) {
          final item = _myContributions[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _getStatusColor(item.status).withAlpha(40),
                child: Icon(
                  _getStatusIcon(item.status),
                  color: _getStatusColor(item.status),
                ),
              ),
              title: Text(
                '${item.currency} ${item.amount.toStringAsFixed(2)} - ${item.fundName}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('Receipt: ${item.receiptNumber}'),
                  Text(
                    '${item.createdAt.year}-${item.createdAt.month.toString().padLeft(2, '0')}-${item.createdAt.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              trailing: Chip(
                label: Text(
                  item.status.displayName,
                  style: TextStyle(
                    color: _getStatusColor(item.status),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                backgroundColor: _getStatusColor(item.status).withAlpha(20),
                side: BorderSide(color: _getStatusColor(item.status), width: 0.5),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLedgerTab() {
    if (_isLoadingLedger) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_ledgerError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 56),
              const SizedBox(height: 16),
              Text(
                'Unable to Load Ledger',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _ledgerError!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadLedger,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLedger,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_ledgerSummary != null) ...[
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'Total Given',
                    '₹${_ledgerSummary!.totalAmount.toStringAsFixed(0)}',
                    '${_ledgerSummary!.totalCount} records',
                    BasilicaColors.burgundy,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSummaryCard(
                    'Verified',
                    '₹${_ledgerSummary!.verifiedAmount.toStringAsFixed(0)}',
                    'Audited',
                    BasilicaColors.olive,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSummaryCard(
                    'Pending',
                    '₹${_ledgerSummary!.pendingAmount.toStringAsFixed(0)}',
                    'To Verify',
                    BasilicaColors.gold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          Row(
            children: [
              const Text('Filter Fund:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<OfferingFundType?>(
                  value: _ledgerFundFilter,
                  isExpanded: true,
                  hint: const Text('All Funds'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All Funds')),
                    ...OfferingFundType.values.map(
                      (f) => DropdownMenuItem(value: f, child: Text(f.displayName)),
                    ),
                  ],
                  onChanged: (val) {
                    setState(() => _ledgerFundFilter = val);
                    _loadLedger();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_ledgerContributions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No contributions found in this filter.',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            )
          else
            ..._ledgerContributions.map((c) => _buildLedgerTile(c)),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String mainValue, String subValue, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                mainValue,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(subValue, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLedgerTile(Contribution c) {
    final isVerified = c.status == ContributionStatus.verified;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(
          '${c.memberName} - ${c.currency} ${c.amount.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.fundName} • ${c.receiptNumber}'),
            if (c.transactionReference != null && c.transactionReference!.isNotEmpty)
              Text('Ref: ${c.transactionReference}', style: const TextStyle(fontSize: 11)),
            if (isVerified && c.verifiedBy != null)
              Text('Verified by: ${c.verifiedBy}', style: const TextStyle(fontSize: 11, color: Colors.green)),
            if (isVerified && c.verificationNote != null && c.verificationNote!.isNotEmpty)
              Text('Audit Note: ${c.verificationNote}', style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
          ],
        ),
        trailing: isVerified
            ? const Icon(Icons.check_circle, color: Colors.green)
            : ElevatedButton(
                onPressed: () => _verifyContributionDialog(c),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(60, 32),
                ),
                child: const Text('Verify', style: TextStyle(fontSize: 12)),
              ),
      ),
    );
  }

  Color _getStatusColor(ContributionStatus status) {
    switch (status) {
      case ContributionStatus.verified:
        return Colors.green;
      case ContributionStatus.submitted:
        return Colors.blue;
      case ContributionStatus.pending:
        return Colors.orange;
      case ContributionStatus.rejected:
        return Colors.red;
    }
  }

  IconData _getStatusIcon(ContributionStatus status) {
    switch (status) {
      case ContributionStatus.verified:
        return Icons.verified;
      case ContributionStatus.submitted:
        return Icons.send;
      case ContributionStatus.pending:
        return Icons.hourglass_top;
      case ContributionStatus.rejected:
        return Icons.cancel;
    }
  }
}
