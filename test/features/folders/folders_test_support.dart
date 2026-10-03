import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/chat/services/export_downloader.dart';
import 'package:garbanzo_ai/features/folders/models/virtual_folder.dart';

class RecordingApi implements ApiClient {
  String? path;
  Object? data;
  Response<dynamic> response = Response(requestOptions: RequestOptions(), statusCode: 200);
  @override
  Future<Response> put(String path, {Object? data}) async {
    this.path = path; this.data = data; return response;
  }
  @override
  Future<Response> delete(String path, {Object? data}) async {
    this.path = path; this.data = data; return response;
  }
  @override
  Future<Response> postMultipart(String path, {required FormData data}) async {
    this.path = path; this.data = data; return response;
  }
  @override
  Future<({Uint8List bytes, String? filename})> download(String path) async {
    this.path = path; return (bytes: Uint8List.fromList([1,2,3]), filename: 'from-server.txt');
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class RecordingDownloader extends ExportDownloader {
  String? filename;
  Uint8List? bytes;
  @override
  Future<void> downloadBytes({required Uint8List bytes, required String filename, required String title, required String mimeType}) async {
    this.filename = filename; this.bytes = bytes;
  }
}
final testFile = FolderFile(id: 'file', folderId: 'folder', path: 'notes.txt', mediaType: 'text/plain', sizeBytes: 3, sha256: 'hash', revision: 7, createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026));
