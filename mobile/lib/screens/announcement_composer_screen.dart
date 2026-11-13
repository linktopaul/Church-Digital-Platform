import 'package:flutter/material.dart';
import '../models/announcement_models.dart';
import '../theme/app_theme.dart';

typedef AnnouncementSubmitCallback = Future<void> Function(CreateAnnouncementInput input);

/// Standalone composer screen for creating and publishing church announcements.
///
/// Features:
/// - Injected async [onSubmit] callback matching backend CreateAnnouncementRequest.
/// - Validates required fields (title, content, priority).
/// - Prevents duplicate submissions while in flight.
/// - Retains full draft state (title, content, priority) upon recoverable failure.
class AnnouncementComposerScreen extends StatefulWidget {
  final AnnouncementSubmitCallback onSubmit;
  final VoidCallback? onCancel;
  final AnnouncementPriority initialPriority;
  final String? initialTitle;
  final String? initialContent;

  const AnnouncementComposerScreen({
    super.key,
    required this.onSubmit,
    this.onCancel,
    this.initialPriority = AnnouncementPriority.routine,
    this.initialTitle,
    this.initialContent,
  });

  /// Static helper to push this composer onto the navigation stack.
  static Future<bool?> show(
    BuildContext context, {
    required AnnouncementSubmitCallback onSubmit,
    AnnouncementPriority initialPriority = AnnouncementPriority.routine,
    String? initialTitle,
    String? initialContent,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AnnouncementComposerScreen(
          onSubmit: onSubmit,
          initialPriority: initialPriority,
          initialTitle: initialTitle,
          initialContent: initialContent,
        ),
      ),
    );
  }

  @override
  State<AnnouncementComposerScreen> createState() => _AnnouncementComposerScreenState();
}

class _AnnouncementComposerScreenState extends State<AnnouncementComposerScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late AnnouncementPriority _selectedPriority;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _contentController = TextEditingController(text: widget.initialContent ?? '');
    _selectedPriority = widget.initialPriority;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final input = CreateAnnouncementInput(
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      priority: _selectedPriority,
    );

    try {
      await widget.onSubmit(input);

      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Announcement published successfully.'),
        ),
      );

      if (Navigator.canPop(context)) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;

      final cleanMessage = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      setState(() {
        _isSubmitting = false;
        _errorMessage = cleanMessage.isNotEmpty
            ? cleanMessage
            : 'Failed to publish announcement. Please try again.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage!),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      // NOTE: Draft in _titleController, _contentController, and _selectedPriority
      // is intentionally preserved so the user can review and retry.
    }
  }

  void _handleCancel() {
    if (widget.onCancel != null) {
      widget.onCancel!();
    } else if (Navigator.canPop(context)) {
      Navigator.of(context).pop(false);
    }
  }

  Widget _buildPriorityBadge(AnnouncementPriority priority) {
    Color color;
    switch (priority) {
      case AnnouncementPriority.routine:
        color = Colors.blue.shade700;
        break;
      case AnnouncementPriority.urgent:
        color = Colors.orange.shade800;
        break;
      case AnnouncementPriority.emergency:
        color = Colors.red.shade700;
        break;
    }

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_isSubmitting,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'New Announcement',
                style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.bold),
              ),
              Text(
                'Nuntius Paroecialis · Notificatio',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 11,
                  letterSpacing: 0.8,
                  color: BasilicaColors.burgundy.withAlpha(180),
                ),
              ),
            ],
          ),
          leading: IconButton(
            key: const Key('announcement_cancel_button'),
            icon: const Icon(Icons.close),
            onPressed: _isSubmitting ? null : _handleCancel,
            tooltip: 'Cancel',
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage != null) ...[
                    Container(
                      key: const Key('announcement_error_banner'),
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.error),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: theme.colorScheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (_errorMessage == null) ...[
                    Card(
                      color: BasilicaColors.stone,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: BasilicaColors.borderSoft),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.campaign_outlined, color: BasilicaColors.burgundy, size: 18),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Share church news, schedule changes, or urgent alerts with your congregation.',
                                style: TextStyle(fontSize: 12.5, color: BasilicaColors.inkMuted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Title Input
                  TextFormField(
                    key: const Key('announcement_title_field'),
                    controller: _titleController,
                    enabled: !_isSubmitting,
                    maxLength: 255,
                    maxLines: 2,
                    minLines: 1,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      hintText: 'e.g. Sunday Service Schedule',
                      prefixIcon: Icon(Icons.title),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter an announcement title.';
                      }
                      if (value.trim().length > 255) {
                        return 'Title cannot exceed 255 characters.';
                      }
                      return null;
                    },
                  ),
                const SizedBox(height: 16),

                // Priority Dropdown
                DropdownButtonFormField<AnnouncementPriority>(
                  key: const Key('announcement_priority_dropdown'),
                  isExpanded: true,
                  initialValue: _selectedPriority,
                  decoration: const InputDecoration(
                    labelText: 'Priority',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  items: AnnouncementPriority.values.map((priority) {
                    return DropdownMenuItem<AnnouncementPriority>(
                      value: priority,
                      child: Row(
                        children: [
                          _buildPriorityBadge(priority),
                          const SizedBox(width: 8),
                          Text(priority.displayName),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: _isSubmitting
                      ? null
                      : (val) {
                          if (val != null) {
                            setState(() => _selectedPriority = val);
                          }
                        },
                ),
                const SizedBox(height: 16),

                // Content Input
                TextFormField(
                  key: const Key('announcement_content_field'),
                  controller: _contentController,
                  enabled: !_isSubmitting,
                  minLines: 4,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'Content *',
                    hintText: 'Write the details of the announcement here...',
                    alignLabelWithHint: true,
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 72),
                      child: Icon(Icons.description_outlined),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter announcement content.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Submit Button
                FilledButton.icon(
                  key: const Key('announcement_publish_button'),
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    _isSubmitting ? 'Publishing...' : 'Publish Announcement',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}
