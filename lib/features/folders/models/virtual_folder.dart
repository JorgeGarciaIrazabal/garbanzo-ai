import 'package:freezed_annotation/freezed_annotation.dart';

part 'virtual_folder.freezed.dart';
part 'virtual_folder.g.dart';

@freezed
abstract class VirtualFolder with _$VirtualFolder {
  const factory VirtualFolder({
    required String id,
    required String name,
    @Default('') String description,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _VirtualFolder;

  factory VirtualFolder.fromJson(Map<String, dynamic> json) =>
      _$VirtualFolderFromJson(json);
}

@freezed
abstract class FolderFile with _$FolderFile {
  const factory FolderFile({
    required String id,
    @JsonKey(name: 'folder_id') required String folderId,
    required String path,
    @JsonKey(name: 'media_type') required String mediaType,
    @JsonKey(name: 'size_bytes') required int sizeBytes,
    required String sha256,
    required int revision,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _FolderFile;

  factory FolderFile.fromJson(Map<String, dynamic> json) =>
      _$FolderFileFromJson(json);
}

@freezed
abstract class FolderText with _$FolderText {
  const factory FolderText({
    required FolderFile file,
    required String text,
    required int offset,
    @JsonKey(name: 'next_offset') int? nextOffset,
    @JsonKey(name: 'total_chars') required int totalChars,
    required bool editable,
  }) = _FolderText;

  factory FolderText.fromJson(Map<String, dynamic> json) =>
      _$FolderTextFromJson(json);
}
