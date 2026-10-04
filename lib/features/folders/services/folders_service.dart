import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/api_error.dart';
import 'package:garbanzo_ai/features/chat/services/export_downloader.dart';
import 'package:garbanzo_ai/features/folders/models/virtual_folder.dart';

class FolderException implements Exception {
  const FolderException(this.status, this.detail);
  final int status;
  final String detail;
  @override
  String toString() => detail;
}

/// Stateless, authenticated API access. UI state stays with each page/user.
class FoldersService {
  FoldersService({ApiClient? api, ExportDownloader? downloader})
    : _api = api ?? ApiClient.instance,
      _downloader = downloader ?? const ExportDownloader();

  static const maxFileBytes = 10 * 1024 * 1024;
  static const maxFolderBytes = 100 * 1024 * 1024;
  static const maxFolderFiles = 500;
  static const _base = '/api/v1/folders';
  final ApiClient _api;
  final ExportDownloader _downloader;

  dynamic _checked(Response response, [int status = 200]) {
    if (response.statusCode != status) {
      throw FolderException(
        response.statusCode ?? 0,
        apiErrorDetail(response.data) ?? 'Folder request failed',
      );
    }
    return response.data;
  }

  List<VirtualFolder> _folders(dynamic data) => (data as List)
      .map((row) => VirtualFolder.fromJson(row as Map<String, dynamic>))
      .toList();

  Future<List<VirtualFolder>> list() async =>
      _folders(_checked(await _api.get(_base)));
  Future<VirtualFolder> create(String name, {String description = ''}) async =>
      VirtualFolder.fromJson(
        _checked(
          await _api.post(
            _base,
            data: {'name': name, 'description': description},
          ),
          201,
        ),
      );
  Future<VirtualFolder> update(
    String id, {
    String? name,
    String? description,
  }) async {
    if (name == null && description == null) {
      throw ArgumentError('Provide a folder name or description');
    }
    return VirtualFolder.fromJson(
      _checked(
        await _api.patch(
          '$_base/$id',
          data: {'name': ?name, 'description': ?description},
        ),
      ),
    );
  }

  Future<VirtualFolder> rename(String id, String name) =>
      update(id, name: name);
  Future<void> delete(String id) async =>
      _checked(await _api.delete('$_base/$id'), 204);
  Future<List<FolderFile>> files(String id) async =>
      (_checked(await _api.get('$_base/$id/files')) as List)
          .map((row) => FolderFile.fromJson(row as Map<String, dynamic>))
          .toList();

  Future<FolderFile> upload(
    String id,
    String path,
    Uint8List bytes, {
    bool keepBoth = false,
  }) async {
    if (bytes.length > maxFileBytes) {
      throw const FolderException(413, 'File exceeds 10 MiB');
    }
    return FolderFile.fromJson(
      _checked(
        await _api.postMultipart(
          '$_base/$id/files',
          data: FormData.fromMap({
            'path': path,
            if (keepBoth) 'keep_both': true,
            'file': MultipartFile.fromBytes(
              bytes,
              filename: path.split('/').last,
            ),
          }),
        ),
        201,
      ),
    );
  }

  Future<FolderFile> replaceFile(FolderFile file, Uint8List bytes) async {
    if (bytes.length > maxFileBytes) {
      throw const FolderException(413, 'File exceeds 10 MiB');
    }
    return FolderFile.fromJson(
      _checked(
        await _api.put(
          '$_base/${file.folderId}/files/${file.id}/content',
          data: FormData.fromMap({
            'revision': file.revision,
            'file': MultipartFile.fromBytes(
              bytes,
              filename: file.path.split('/').last,
            ),
          }),
        ),
      ),
    );
  }

  Future<FolderText> text(FolderFile file, {int offset = 0}) async =>
      FolderText.fromJson(
        _checked(
          await _api.get(
            '$_base/${file.folderId}/files/${file.id}/text',
            queryParameters: {'offset': offset, 'limit': 12000},
          ),
        ),
      );
  Future<FolderFile> saveText(FolderFile file, String content) async =>
      FolderFile.fromJson(
        _checked(
          await _api.put(
            '$_base/${file.folderId}/files/${file.id}/text',
            data: {'content': content, 'revision': file.revision},
          ),
        ),
      );
  Future<FolderFile> createText(String id, String path, String content) async =>
      FolderFile.fromJson(
        _checked(
          await _api.post(
            '$_base/$id/text',
            data: {'path': path, 'content': content},
          ),
          201,
        ),
      );
  Future<void> deleteFile(FolderFile file) async => _checked(
    await _api.delete(
      '$_base/${file.folderId}/files/${file.id}?revision=${file.revision}',
    ),
    204,
  );
  Future<List<VirtualFolder>> attached(String conversationId) async => _folders(
    _checked(await _api.get('$_base/conversations/$conversationId')),
  );
  Future<void> attach(String conversationId, String folderId) async => _checked(
    await _api.put('$_base/conversations/$conversationId/$folderId'),
  );
  Future<void> detach(String conversationId, String folderId) async => _checked(
    await _api.delete('$_base/conversations/$conversationId/$folderId'),
    204,
  );

  Future<Uint8List> content(FolderFile file) async => (await _api.download(
    '$_base/${file.folderId}/files/${file.id}/content',
  )).bytes;

  Future<void> download({
    required String folderId,
    String? fileId,
    required String filename,
    required String mediaType,
    required String title,
  }) async {
    final path = fileId == null
        ? '$_base/$folderId/download'
        : '$_base/$folderId/files/$fileId/content';
    final result = await _api.download(path);
    await _downloader.downloadBytes(
      bytes: result.bytes,
      filename: safeDownloadFilename(result.filename ?? filename),
      title: title,
      mimeType: mediaType,
    );
  }
}

/// Folder names are labels, not filesystem paths. Apply this to server names
/// too, so downloaded artifacts remain valid on Windows/Android/desktop.
String safeDownloadFilename(String filename) {
  var safe = filename
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (safe.isEmpty) safe = 'download';
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(safe)) {
    safe = '_$safe';
  }
  return safe;
}
