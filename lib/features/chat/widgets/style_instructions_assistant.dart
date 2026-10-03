import 'dart:async';

import 'package:flutter/material.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/providers/system_prompt_provider.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Generates a suggestion separately from the user's editable instructions.
class StyleInstructionsAssistant extends StatefulWidget {
  const StyleInstructionsAssistant({
    super.key,
    required this.controller,
    required this.prompts,
    required this.modelId,
    required this.enabled,
    required this.onPendingChanged,
  });

  final TextEditingController controller;
  final SystemPromptProvider prompts;
  final String? modelId;
  final bool enabled;
  final ValueChanged<bool> onPendingChanged;

  @override
  State<StyleInstructionsAssistant> createState() =>
      _StyleInstructionsAssistantState();
}

class _StyleInstructionsAssistantState
    extends State<StyleInstructionsAssistant> {
  final _request = TextEditingController();
  StreamSubscription<ChatResponseChunk>? _subscription;
  bool _open = false;
  bool _generating = false;
  bool _failed = false;
  String _suggestion = '';
  int _generation = 0;

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    _request.dispose();
    super.dispose();
  }

  void _discard() {
    _generation++;
    _subscription?.cancel();
    _subscription = null;
    setState(() {
      _generating = false;
      _suggestion = '';
      _failed = false;
      _open = false;
    });
    widget.onPendingChanged(false);
  }

  void _generate() {
    final request = _request.text.trim();
    final existing = widget.controller.text.trim();
    if (!widget.enabled ||
        _generating ||
        widget.modelId == null ||
        request.isEmpty ||
        existing.length > 8000) {
      return;
    }
    final generation = ++_generation;
    _subscription?.cancel();
    setState(() {
      _generating = true;
      _failed = false;
      _suggestion = '';
    });
    widget.onPendingChanged(true);

    void fail() {
      if (!mounted || generation != _generation || !_generating) return;
      _generation++;
      _subscription?.cancel();
      setState(() {
        _generating = false;
        _failed = true;
        _suggestion = '';
      });
      widget.onPendingChanged(false);
    }

    try {
      _subscription = widget.prompts
          .generateInstructions(
            intent: request,
            existingPrompt: existing.isEmpty ? null : existing,
            feedback: existing.isEmpty ? null : request,
            model: widget.modelId!,
          )
          .listen(
            (chunk) {
              if (!mounted || generation != _generation || !_generating) return;
              if (chunk.isError) {
                fail();
              } else if (chunk.isChunk) {
                setState(() => _suggestion += chunk.content ?? '');
              } else if (chunk.isDone) {
                if (_suggestion.trim().isEmpty) {
                  fail();
                } else {
                  setState(() => _generating = false);
                  _subscription?.cancel();
                }
              }
            },
            onError: (_) => fail(),
            onDone: fail,
          );
    } catch (_) {
      fail();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final hasInstructions = value.text.trim().isNotEmpty;
        final tooLong = value.text.trim().length > 8000;
        final hasSuggestion = _suggestion.isNotEmpty && !_generating;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('style_ai_help'),
                onPressed: widget.enabled && !_generating && !hasSuggestion
                    ? () => setState(() => _open = !_open)
                    : null,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(l.styleAiHelp),
              ),
            ),
            if (_open) ...[
              TextField(
                key: const ValueKey('style_ai_request'),
                controller: _request,
                enabled: widget.enabled && !_generating && !hasSuggestion,
                minLines: 2,
                maxLines: 3,
                maxLength: 1000,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: hasInstructions
                      ? l.styleAiChangeRequest
                      : l.styleAiIdea,
                  hintText: hasInstructions
                      ? l.styleAiChangeHint
                      : l.styleAiIdeaHint,
                  alignLabelWithHint: true,
                ),
              ),
              if (tooLong)
                Text(
                  l.styleAiTooLong,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_generating) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(l.styleAiGenerating),
              ],
              if (_suggestion.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  l.styleAiSuggestion,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _suggestion,
                      key: const ValueKey('style_ai_suggestion'),
                    ),
                  ),
                ),
              ],
              if (_failed)
                Text(
                  l.styleAiFailed,
                  key: const ValueKey('style_ai_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Wrap(
                spacing: 8,
                children: [
                  if (hasSuggestion)
                    FilledButton.tonal(
                      key: const ValueKey('style_ai_accept'),
                      onPressed: !widget.enabled
                          ? null
                          : () {
                              widget.controller.text = _suggestion.trim();
                              _discard();
                            },
                      child: Text(l.styleAiUse),
                    )
                  else if (!_generating)
                    FilledButton.tonalIcon(
                      key: const ValueKey('style_ai_generate'),
                      onPressed:
                          !widget.enabled ||
                              widget.modelId == null ||
                              tooLong ||
                              _request.text.trim().isEmpty
                          ? null
                          : _generate,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: Text(
                        hasInstructions ? l.styleAiImprove : l.labelGenerate,
                      ),
                    ),
                  TextButton(
                    key: const ValueKey('style_ai_discard'),
                    onPressed: _discard,
                    child: Text(hasSuggestion ? l.discard : l.cancel),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
