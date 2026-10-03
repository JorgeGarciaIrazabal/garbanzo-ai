import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/folders/services/folders_service.dart';
import 'package:garbanzo_ai/features/folders/widgets/folder_download_button.dart';


import 'folders_test_support.dart';

void main() {
  test('download filenames cannot contain path separators or reserved names', () {
    expect(safeDownloadFilename('Research/project.zip'), 'Research_project.zip');
    expect(safeDownloadFilename(r'notes\final.txt'), 'notes_final.txt');
    expect(safeDownloadFilename('CON.zip'), '_CON.zip');
  });
  test('editing and deleting transmit original revision; conflicts surface', () async {
    final api = RecordingApi();
    api.response = Response(requestOptions: RequestOptions(), statusCode: 409, data: {'detail': 'revision changed'});
    final service = FoldersService(api: api);
    await expectLater(service.saveText(testFile, 'new content'), throwsA(isA<FolderException>().having((e) => e.status, 'status', 409).having((e) => e.detail, 'detail', 'revision changed')));
    expect(api.path, '/api/v1/folders/folder/files/file/text');
    expect(api.data, {'content': 'new content', 'revision': 7});
    api.response = Response(requestOptions: RequestOptions(), statusCode: 204);
    await service.deleteFile(testFile);
    expect(api.path, '/api/v1/folders/folder/files/file?revision=7');
  });
  test('oversized upload fails before sending bytes', () async {
    final api = RecordingApi();
    await expectLater(FoldersService(api: api).upload('folder', 'large.bin', Uint8List(FoldersService.maxFileBytes + 1)), throwsA(isA<FolderException>().having((e) => e.status, 'status', 413)));
    expect(api.path, isNull);
  });
  test('file and ZIP downloads use authenticated ApiClient and export delivery', () async {
    final api = RecordingApi(); final downloader = RecordingDownloader();
    final service = FoldersService(api: api, downloader: downloader);
    await service.download(folderId: 'folder', fileId: 'file', filename: 'suggested.txt', mediaType: 'text/plain', title: 'Download');
    expect(api.path, '/api/v1/folders/folder/files/file/content');
    expect(downloader.filename, 'from-server.txt');
    expect(downloader.bytes, [1,2,3]);
    await service.download(folderId: 'folder', filename: 'folder.zip', mediaType: 'application/zip', title: 'Download');
    expect(api.path, '/api/v1/folders/folder/download');
  });
  test('download result rejects errors, unrelated tools and malformed fields', () {
    final result = {'ok': true, 'action': 'download', 'download': {'folder_id': 'folder', 'file_id': 'file', 'filename': 'notes.txt', 'media_type': 'text/plain'}};
    expect(folderDownloadResult('virtual_folders', result)?['file_id'], 'file');
    expect(folderDownloadResult('another_tool', result), isNull);
    expect(folderDownloadResult('virtual_folders', {...result, 'ok': false}), isNull);
    expect(folderDownloadResult('virtual_folders', {'ok': true, 'action': 'download', 'download': {'folder_id': 'folder'}}), isNull);
    expect(folderDownloadResult('virtual_folders', 'not JSON'), isNull);
  });
}
