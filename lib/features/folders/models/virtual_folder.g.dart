// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'virtual_folder.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_VirtualFolder _$VirtualFolderFromJson(Map<String, dynamic> json) =>
    _VirtualFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$VirtualFolderToJson(_VirtualFolder instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

_FolderFile _$FolderFileFromJson(Map<String, dynamic> json) => _FolderFile(
  id: json['id'] as String,
  folderId: json['folder_id'] as String,
  path: json['path'] as String,
  mediaType: json['media_type'] as String,
  sizeBytes: (json['size_bytes'] as num).toInt(),
  sha256: json['sha256'] as String,
  revision: (json['revision'] as num).toInt(),
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
);

Map<String, dynamic> _$FolderFileToJson(_FolderFile instance) =>
    <String, dynamic>{
      'id': instance.id,
      'folder_id': instance.folderId,
      'path': instance.path,
      'media_type': instance.mediaType,
      'size_bytes': instance.sizeBytes,
      'sha256': instance.sha256,
      'revision': instance.revision,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };

_FolderText _$FolderTextFromJson(Map<String, dynamic> json) => _FolderText(
  file: FolderFile.fromJson(json['file'] as Map<String, dynamic>),
  text: json['text'] as String,
  offset: (json['offset'] as num).toInt(),
  nextOffset: (json['next_offset'] as num?)?.toInt(),
  totalChars: (json['total_chars'] as num).toInt(),
  editable: json['editable'] as bool,
);

Map<String, dynamic> _$FolderTextToJson(_FolderText instance) =>
    <String, dynamic>{
      'file': instance.file,
      'text': instance.text,
      'offset': instance.offset,
      'next_offset': instance.nextOffset,
      'total_chars': instance.totalChars,
      'editable': instance.editable,
    };
