import 'dart:async';
import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart' as a2ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:genui/genui.dart' as genui;
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/services/visual_ui_service.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/copy_button.dart';
import 'package:garbanzo_ai/features/chat/widgets/message/speak_button.dart';
import 'package:garbanzo_ai/features/chat/widgets/visual_answers/visual_components.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// The SDK is confined here; chat history and model calls remain app-owned.
class VisualAnswer extends StatefulWidget {
  const VisualAnswer({
    super.key,
    required this.message,
    required this.conversationId,
    required this.canSubmit,
    this.service,
  });

  final ChatMessage message;
  final String? conversationId;
  final bool canSubmit;
  final VisualUIService? service;

  @override
  State<VisualAnswer> createState() => _VisualAnswerState();
}

class _VisualAnswerState extends State<VisualAnswer> {
  genui.SurfaceController? _controller;
  StreamSubscription<genui.ChatMessage>? _sdkErrors;
  Object? _error;
  bool _available = false;
  final _statuses = <String, Map<String, dynamic>>{};
  final _inFlight = <String>{};
  final _requestIds = <String, String>{};

  Map<String, dynamic> get _presentation => widget.message.visualPresentation!;
  VisualUIService get _service => widget.service ?? VisualUIService();

  @override
  void initState() {
    super.initState();
    _initialize();
    _hydrate();
  }

  @override
  void didUpdateWidget(VisualAnswer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.canSubmit && widget.canSubmit) _hydrate();
  }

  Future<void> _initialize() async {
    genui.SurfaceController? controller;
    try {
      final schema =
          jsonDecode(
                await rootBundle.loadString(
                  'backend/app/schemas/visual_ui_catalog.json',
                ),
              )
              as Map<String, dynamic>;
      if (!mounted) return;
      final components = Map<String, dynamic>.from(schema['components'] as Map);
      final definitions = (_presentation['components'] as List).cast<Map>();
      if (!definitions.any((c) => c['id'] == 'root') ||
          definitions.any((c) => !components.containsKey(c['component']))) {
        throw const FormatException(
          'Unsupported visual component or missing root',
        );
      }
      final catalog = genui.Catalog(
        components.entries.map(
          (entry) => genui.CatalogItem(
            name: entry.key,
            dataSchema: Schema.fromMap(Map<String, Object?>.from(entry.value)),
            widgetBuilder: (item) {
              try {
                return buildVisualComponent(
                  item,
                  onSubmit: _submit,
                  canSubmit: widget.canSubmit && _available,
                  statuses: _statuses,
                  inFlight: _inFlight,
                );
              } catch (error) {
                return Text(
                  '${AppLocalizations.of(item.buildContext)!.visualAnswerError}: $error',
                );
              }
            },
          ),
        ),
        catalogId: schema['catalog_id'] as String,
      );
      controller = genui.SurfaceController(catalogs: [catalog]);
      _sdkErrors = controller.onSubmit.listen((message) {
        for (final part in message.parts.uiInteractionParts) {
          final payload = jsonDecode(part.interaction) as Map;
          if (payload['error'] is Map && mounted) {
            setState(() => _error = payload['error']['message']);
          }
        }
      });
      final id = _presentation['surface_id'] as String;
      controller.handleMessage(
        a2ui.A2uiMessage.fromJson({
          'version': schema['protocol_version'],
          'createSurface': {'surfaceId': id, 'catalogId': schema['catalog_id']},
        }),
      );
      controller.handleMessage(
        a2ui.A2uiMessage.fromJson({
          'version': schema['protocol_version'],
          'updateComponents': {
            'surfaceId': id,
            'components': _presentation['components'],
          },
        }),
      );
      if (controller.contextFor(id).definition.value == null) {
        throw StateError('The visual surface could not be constructed');
      }
      setState(() => _controller = controller);
    } catch (error) {
      controller?.dispose();
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _hydrate() async {
    if (!widget.canSubmit ||
        widget.conversationId == null ||
        (_presentation['actions'] as List).isEmpty) {
      return;
    }
    try {
      final state = await _service.state(
        widget.conversationId!,
        widget.message.toolCallId!,
      );
      if (!mounted) return;
      setState(() {
        _available = state['available'] == true;
        for (final raw in state['submissions'] as List) {
          final status = Map<String, dynamic>.from(raw as Map);
          _statuses[status['action_id'] as String] = status;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _submit(String actionId, Map<String, dynamic> values) async {
    if (!widget.canSubmit || !_available || _inFlight.contains(actionId)) {
      return;
    }
    setState(() => _inFlight.add(actionId));
    try {
      final result = await _service.submit(widget.conversationId!, {
        'tool_call_id': widget.message.toolCallId,
        'surface_id': _presentation['surface_id'],
        'action_id': actionId,
        'submission_id': _requestIds.putIfAbsent(
          actionId,
          () => const Uuid().v4(),
        ),
        'values': values,
      });
      if (!mounted) return;
      setState(() => _statuses[actionId] = result);
      final payload = result['result'];
      if (result['status'] == 'completed' &&
          payload is Map &&
          widget.service == null) {
        final chat = context.read<ChatProvider>();
        if (chat.currentConversation?.id == widget.conversationId) {
          if (payload['message_id'] is String) {
            chat.followServerResponse(widget.conversationId!);
          } else {
            await chat.loadConversation(widget.conversationId!);
          }
        }
      }
    } catch (error) {
      // A request may have reached the server. Inspect its saved state before
      // allowing any further click; do not retry execution automatically.
      if (mounted) {
        setState(() {
          _available = false;
          _error = error;
        });
      }
    } finally {
      if (mounted) setState(() => _inFlight.remove(actionId));
    }
  }

  @override
  void dispose() {
    _sdkErrors?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final summary = _presentation['summary'] as String;
    final controller = _controller;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (controller != null)
            genui.Surface(
              surfaceContext: controller.contextFor(
                _presentation['surface_id'] as String,
              ),
            )
          else if (_error == null)
            const LinearProgressIndicator(),
          if (_error != null) ...[
            Text('${l10n.visualAnswerError}: $_error'),
            if (controller == null) SelectableText(summary),
          ],
          if ((_presentation['actions'] as List).isNotEmpty &&
              (_error != null ||
                  _statuses.values.any((s) => s['status'] == 'pending')))
            TextButton(
              onPressed: () {
                setState(() => _error = null);
                _hydrate();
              },
              child: Text(l10n.visualCheckStatus),
            ),
          if (controller != null &&
              widget.canSubmit &&
              !_available &&
              (_presentation['actions'] as List).isNotEmpty &&
              _error == null)
            Text(l10n.visualAnswerReadOnly),
          Wrap(
            spacing: 8,
            children: [
              CopyButton(content: summary),
              SpeakButton(
                content: summary,
                messageId: widget.message.id,
                isStreaming: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
