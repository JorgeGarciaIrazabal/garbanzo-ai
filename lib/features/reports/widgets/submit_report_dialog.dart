import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/reports/models/report.dart';
import 'package:garbanzo_ai/features/reports/services/reports_service.dart';

/// Dialog for submitting a bug report or feature request (idea 14).
///
/// Admins triage submissions from the Admin page; the user sees a
/// confirmation snackbar on success.
class SubmitReportDialog extends StatefulWidget {
  const SubmitReportDialog({super.key, this.submit});

  /// Submission handler; defaults to [ReportsService.create]. Injectable for
  /// widget tests.
  final Future<Report> Function({
    required String type,
    required String title,
    required String description,
  })?
  submit;

  /// Shows the dialog. A confirmation snackbar appears on successful submit
  /// (shown from inside the dialog, so it works even when the caller — e.g.
  /// the settings drawer — has already been dismissed).
  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const SubmitReportDialog(),
  );

  @override
  State<SubmitReportDialog> createState() => _SubmitReportDialogState();
}

class _SubmitReportDialogState extends State<SubmitReportDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _type = 'bug';
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Re-evaluate the submit button's enabled state as the user types.
    _title.addListener(() => setState(() {}));
    _description.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_sending &&
      _title.text.trim().isNotEmpty &&
      _description.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await (widget.submit ?? ReportsService.instance.create)(
        type: _type,
        title: _title.text.trim(),
        description: _description.text.trim(),
      );
      if (mounted) {
        // Root messenger — outlives both this dialog and the drawer.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks! Your report was submitted.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Could not submit: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Report a bug or request a feature'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'bug',
                  label: Text('Bug'),
                  icon: Icon(Icons.bug_report_outlined),
                ),
                ButtonSegment(
                  value: 'feature',
                  label: Text('Feature'),
                  icon: Icon(Icons.lightbulb_outline),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selection) =>
                  setState(() => _type = selection.first),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('report_title_field'),
              controller: _title,
              enabled: !_sending,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'One-line summary',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('report_description_field'),
              controller: _description,
              enabled: !_sending,
              minLines: 4,
              maxLines: 8,
              maxLength: 10000,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: _type == 'bug'
                    ? 'What happened, and what did you expect?'
                    : 'What would you like the app to do?',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('report_submit_button'),
          onPressed: _canSubmit ? _submit : null,
          child: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }
}
