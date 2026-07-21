import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:garbanzo_ai/core/log.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';
import 'package:garbanzo_ai/features/chat/services/folder_reader.dart';

/// Local-only folder attachments and client-served file-tool requests.
class ClientFolderController {
  ClientFolderController({
    required ChatService chatService,
    required void Function() onChanged,
    FolderReader folderReader = const FolderReader(),
  }) : _chatService = chatService,
       _onChanged = onChanged,
       _folderReader = folderReader;

  static const _prefsKey = 'client_folders';

  final ChatService _chatService;
  final FolderReader _folderReader;
  final void Function() _onChanged;
  final Map<String, String> _folders = {};
  String? _pendingFolder;

  String? folderFor(String? conversationId) =>
      conversationId == null ? _pendingFolder : _folders[conversationId];

  String? folderNameFor(String? conversationId) {
    final path = folderFor(conversationId);
    if (path == null) return null;
    final parts = path.split(RegExp(r'[/\\]')).where((part) => part.isNotEmpty);
    return parts.isEmpty ? null : parts.last;
  }

  bool hasFolder(String conversationId) => _folders.containsKey(conversationId);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _folders
          ..clear()
          ..addAll(decoded.map((key, value) => MapEntry('$key', '$value')));
        _onChanged();
      }
    } catch (error) {
      logDebug('Failed to load client folders: $error');
    }
  }

  Future<void> attach(String? conversationId, String path) async {
    if (conversationId == null) {
      _pendingFolder = path;
    } else {
      _folders[conversationId] = path;
      await _persist();
    }
    _onChanged();
  }

  Future<void> clear(String? conversationId) async {
    if (conversationId == null) {
      if (_pendingFolder == null) return;
      _pendingFolder = null;
      _onChanged();
      return;
    }
    if (_folders.remove(conversationId) != null) {
      _onChanged();
      await _persist();
    }
  }

  Future<void> adoptPending(String conversationId) async {
    final pending = _pendingFolder;
    if (pending == null) return;
    _pendingFolder = null;
    _folders[conversationId] = pending;
    await _persist();
  }

  Future<void> serveToolRequest(
    String conversationId,
    Map<String, dynamic> request,
  ) async {
    final toolCallId = request['tool_call_id']?.toString();
    final toolName = request['tool_name']?.toString();
    if (toolCallId == null) return;
    final root = _folders[conversationId];
    final args = (request['args'] as Map?)?.cast<String, dynamic>() ?? const {};
    final path = args['path']?.toString() ?? '';
    final payload = <String, dynamic>{'tool_call_id': toolCallId};
    try {
      if (root == null) {
        throw const FolderReadError('No folder is attached on this device.');
      }
      if (toolName == 'read_file') {
        final file = _folderReader.readFile(root, path);
        payload
          ..['ok'] = true
          ..['filename'] = file.filename
          ..['data'] = base64Encode(file.bytes);
      } else {
        payload
          ..['ok'] = true
          ..['entries'] = _folderReader.listDir(root, path);
      }
    } catch (error) {
      payload
        ..['ok'] = false
        ..['error'] = error is FolderReadError ? error.message : '$error';
    }
    try {
      await _chatService.postClientToolResult(conversationId, payload);
    } catch (error) {
      logDebug('Failed to post client tool result: $error');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_folders));
    } catch (error) {
      logDebug('Failed to persist client folders: $error');
    }
  }
}
