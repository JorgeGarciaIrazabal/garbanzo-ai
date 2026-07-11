import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:garbanzo_ai/features/chat/widgets/message/message_action_button.dart';

/// Copy button for copying message content to clipboard.
class CopyButton extends StatefulWidget {
  const CopyButton({super.key, required this.content});

  final String content;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.content));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _copied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MessageActionButton(
      icon: _copied ? Icons.check : Icons.copy,
      label: _copied ? 'Copied!' : 'Copy',
      tooltip: 'Copy message to clipboard',
      highlighted: _copied,
      onTap: _copy,
    );
  }
}
