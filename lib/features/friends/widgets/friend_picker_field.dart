import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/friends/models/friend_models.dart';

/// Email multi-picker backed by the user's friends list: selected people
/// render as removable chips, typing filters friends into tappable
/// suggestions, and submitting free text keeps working as the "by email"
/// fallback for people who aren't friends yet.
class FriendPickerField extends StatefulWidget {
  const FriendPickerField({
    super.key,
    required this.friends,
    required this.onChanged,
    this.label = 'Invite people',
    this.excludeEmails = const {},
  });

  final List<Friend> friends;

  /// Fires with the full selection whenever it changes.
  final ValueChanged<List<String>> onChanged;

  final String label;

  /// Emails never suggested (e.g. existing room members).
  final Set<String> excludeEmails;

  @override
  State<FriendPickerField> createState() => FriendPickerFieldState();
}

class FriendPickerFieldState extends State<FriendPickerField> {
  final _controller = TextEditingController();
  final _selected = <String>[];

  List<String> get selectedEmails => List.unmodifiable(_selected);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String email) {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || _selected.contains(normalized)) return;
    setState(() {
      _selected.add(normalized);
      _controller.clear();
    });
    widget.onChanged(selectedEmails);
  }

  void _remove(String email) {
    setState(() => _selected.remove(email));
    widget.onChanged(selectedEmails);
  }

  /// Free-text fallback: comma-separated emails are all added at once.
  void _submitText(String text) {
    for (final part in text.split(',')) {
      final email = part.trim();
      if (email.contains('@')) _add(email);
    }
  }

  /// Folds any email still sitting in the text field into the selection —
  /// call before reading [selectedEmails] so "type and hit Create" works
  /// without an explicit Enter.
  void commitPendingText() => _submitText(_controller.text);

  List<Friend> get _suggestions {
    final query = _controller.text.trim().toLowerCase();
    return widget.friends
        .where(
          (f) =>
              !_selected.contains(f.email.toLowerCase()) &&
              !widget.excludeEmails.contains(f.email) &&
              (query.isEmpty ||
                  f.email.toLowerCase().contains(query) ||
                  (f.fullName?.toLowerCase().contains(query) ?? false)),
        )
        .take(5)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final email in _selected)
                  InputChip(
                    label: Text(email),
                    onDeleted: () => _remove(email),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        TextField(
          key: const Key('friend_picker_input'),
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.friends.isEmpty
                ? 'email@example.com'
                : 'Type a friend\'s name or any email',
          ),
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
          onSubmitted: _submitText,
        ),
        if (suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final friend in suggestions)
                  ActionChip(
                    avatar: const Icon(Icons.person_add_alt, size: 18),
                    label: Text(friend.displayName),
                    tooltip: friend.email,
                    onPressed: () => _add(friend.email),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
