// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'virtual_folder.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$VirtualFolder {

 String get id; String get name; String get description;@JsonKey(name: 'created_at') DateTime get createdAt;@JsonKey(name: 'updated_at') DateTime get updatedAt;
/// Create a copy of VirtualFolder
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VirtualFolderCopyWith<VirtualFolder> get copyWith => _$VirtualFolderCopyWithImpl<VirtualFolder>(this as VirtualFolder, _$identity);

  /// Serializes this VirtualFolder to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VirtualFolder&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,description,createdAt,updatedAt);

@override
String toString() {
  return 'VirtualFolder(id: $id, name: $name, description: $description, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $VirtualFolderCopyWith<$Res>  {
  factory $VirtualFolderCopyWith(VirtualFolder value, $Res Function(VirtualFolder) _then) = _$VirtualFolderCopyWithImpl;
@useResult
$Res call({
 String id, String name, String description,@JsonKey(name: 'created_at') DateTime createdAt,@JsonKey(name: 'updated_at') DateTime updatedAt
});




}
/// @nodoc
class _$VirtualFolderCopyWithImpl<$Res>
    implements $VirtualFolderCopyWith<$Res> {
  _$VirtualFolderCopyWithImpl(this._self, this._then);

  final VirtualFolder _self;
  final $Res Function(VirtualFolder) _then;

/// Create a copy of VirtualFolder
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? description = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(VirtualFolder(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [VirtualFolder].
extension VirtualFolderPatterns on VirtualFolder {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VirtualFolder value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VirtualFolder() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VirtualFolder value)  $default,){
final _that = this;
switch (_that) {
case _VirtualFolder():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VirtualFolder value)?  $default,){
final _that = this;
switch (_that) {
case _VirtualFolder() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String description, @JsonKey(name: 'created_at')  DateTime createdAt, @JsonKey(name: 'updated_at')  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VirtualFolder() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.createdAt,_that.updatedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String description, @JsonKey(name: 'created_at')  DateTime createdAt, @JsonKey(name: 'updated_at')  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _VirtualFolder():
return $default(_that.id,_that.name,_that.description,_that.createdAt,_that.updatedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String description, @JsonKey(name: 'created_at')  DateTime createdAt, @JsonKey(name: 'updated_at')  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _VirtualFolder() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _VirtualFolder implements VirtualFolder {
  const _VirtualFolder({required this.id, required this.name, this.description = '', @JsonKey(name: 'created_at') required this.createdAt, @JsonKey(name: 'updated_at') required this.updatedAt});
  factory _VirtualFolder.fromJson(Map<String, dynamic> json) => _$VirtualFolderFromJson(json);

@override final  String id;
@override final  String name;
@override@JsonKey() final  String description;
@override@JsonKey(name: 'created_at') final  DateTime createdAt;
@override@JsonKey(name: 'updated_at') final  DateTime updatedAt;

/// Create a copy of VirtualFolder
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VirtualFolderCopyWith<_VirtualFolder> get copyWith => __$VirtualFolderCopyWithImpl<_VirtualFolder>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$VirtualFolderToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _VirtualFolder&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,description,createdAt,updatedAt);

@override
String toString() {
  return 'VirtualFolder(id: $id, name: $name, description: $description, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$VirtualFolderCopyWith<$Res> implements $VirtualFolderCopyWith<$Res> {
  factory _$VirtualFolderCopyWith(_VirtualFolder value, $Res Function(_VirtualFolder) _then) = __$VirtualFolderCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String description,@JsonKey(name: 'created_at') DateTime createdAt,@JsonKey(name: 'updated_at') DateTime updatedAt
});




}
/// @nodoc
class __$VirtualFolderCopyWithImpl<$Res>
    implements _$VirtualFolderCopyWith<$Res> {
  __$VirtualFolderCopyWithImpl(this._self, this._then);

  final _VirtualFolder _self;
  final $Res Function(_VirtualFolder) _then;

/// Create a copy of VirtualFolder
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_VirtualFolder(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}


/// @nodoc
mixin _$FolderFile {

 String get id;@JsonKey(name: 'folder_id') String get folderId; String get path;@JsonKey(name: 'media_type') String get mediaType;@JsonKey(name: 'size_bytes') int get sizeBytes; String get sha256; int get revision;@JsonKey(name: 'created_at') DateTime get createdAt;@JsonKey(name: 'updated_at') DateTime get updatedAt;
/// Create a copy of FolderFile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FolderFileCopyWith<FolderFile> get copyWith => _$FolderFileCopyWithImpl<FolderFile>(this as FolderFile, _$identity);

  /// Serializes this FolderFile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FolderFile&&(identical(other.id, id) || other.id == id)&&(identical(other.folderId, folderId) || other.folderId == folderId)&&(identical(other.path, path) || other.path == path)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes)&&(identical(other.sha256, sha256) || other.sha256 == sha256)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,folderId,path,mediaType,sizeBytes,sha256,revision,createdAt,updatedAt);

@override
String toString() {
  return 'FolderFile(id: $id, folderId: $folderId, path: $path, mediaType: $mediaType, sizeBytes: $sizeBytes, sha256: $sha256, revision: $revision, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $FolderFileCopyWith<$Res>  {
  factory $FolderFileCopyWith(FolderFile value, $Res Function(FolderFile) _then) = _$FolderFileCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(name: 'folder_id') String folderId, String path,@JsonKey(name: 'media_type') String mediaType,@JsonKey(name: 'size_bytes') int sizeBytes, String sha256, int revision,@JsonKey(name: 'created_at') DateTime createdAt,@JsonKey(name: 'updated_at') DateTime updatedAt
});




}
/// @nodoc
class _$FolderFileCopyWithImpl<$Res>
    implements $FolderFileCopyWith<$Res> {
  _$FolderFileCopyWithImpl(this._self, this._then);

  final FolderFile _self;
  final $Res Function(FolderFile) _then;

/// Create a copy of FolderFile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? folderId = null,Object? path = null,Object? mediaType = null,Object? sizeBytes = null,Object? sha256 = null,Object? revision = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(FolderFile(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,folderId: null == folderId ? _self.folderId : folderId // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as String,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,sha256: null == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [FolderFile].
extension FolderFilePatterns on FolderFile {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FolderFile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FolderFile() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FolderFile value)  $default,){
final _that = this;
switch (_that) {
case _FolderFile():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FolderFile value)?  $default,){
final _that = this;
switch (_that) {
case _FolderFile() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'folder_id')  String folderId,  String path, @JsonKey(name: 'media_type')  String mediaType, @JsonKey(name: 'size_bytes')  int sizeBytes,  String sha256,  int revision, @JsonKey(name: 'created_at')  DateTime createdAt, @JsonKey(name: 'updated_at')  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FolderFile() when $default != null:
return $default(_that.id,_that.folderId,_that.path,_that.mediaType,_that.sizeBytes,_that.sha256,_that.revision,_that.createdAt,_that.updatedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'folder_id')  String folderId,  String path, @JsonKey(name: 'media_type')  String mediaType, @JsonKey(name: 'size_bytes')  int sizeBytes,  String sha256,  int revision, @JsonKey(name: 'created_at')  DateTime createdAt, @JsonKey(name: 'updated_at')  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _FolderFile():
return $default(_that.id,_that.folderId,_that.path,_that.mediaType,_that.sizeBytes,_that.sha256,_that.revision,_that.createdAt,_that.updatedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(name: 'folder_id')  String folderId,  String path, @JsonKey(name: 'media_type')  String mediaType, @JsonKey(name: 'size_bytes')  int sizeBytes,  String sha256,  int revision, @JsonKey(name: 'created_at')  DateTime createdAt, @JsonKey(name: 'updated_at')  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _FolderFile() when $default != null:
return $default(_that.id,_that.folderId,_that.path,_that.mediaType,_that.sizeBytes,_that.sha256,_that.revision,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FolderFile implements FolderFile {
  const _FolderFile({required this.id, @JsonKey(name: 'folder_id') required this.folderId, required this.path, @JsonKey(name: 'media_type') required this.mediaType, @JsonKey(name: 'size_bytes') required this.sizeBytes, required this.sha256, required this.revision, @JsonKey(name: 'created_at') required this.createdAt, @JsonKey(name: 'updated_at') required this.updatedAt});
  factory _FolderFile.fromJson(Map<String, dynamic> json) => _$FolderFileFromJson(json);

@override final  String id;
@override@JsonKey(name: 'folder_id') final  String folderId;
@override final  String path;
@override@JsonKey(name: 'media_type') final  String mediaType;
@override@JsonKey(name: 'size_bytes') final  int sizeBytes;
@override final  String sha256;
@override final  int revision;
@override@JsonKey(name: 'created_at') final  DateTime createdAt;
@override@JsonKey(name: 'updated_at') final  DateTime updatedAt;

/// Create a copy of FolderFile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FolderFileCopyWith<_FolderFile> get copyWith => __$FolderFileCopyWithImpl<_FolderFile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FolderFileToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FolderFile&&(identical(other.id, id) || other.id == id)&&(identical(other.folderId, folderId) || other.folderId == folderId)&&(identical(other.path, path) || other.path == path)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes)&&(identical(other.sha256, sha256) || other.sha256 == sha256)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,folderId,path,mediaType,sizeBytes,sha256,revision,createdAt,updatedAt);

@override
String toString() {
  return 'FolderFile(id: $id, folderId: $folderId, path: $path, mediaType: $mediaType, sizeBytes: $sizeBytes, sha256: $sha256, revision: $revision, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$FolderFileCopyWith<$Res> implements $FolderFileCopyWith<$Res> {
  factory _$FolderFileCopyWith(_FolderFile value, $Res Function(_FolderFile) _then) = __$FolderFileCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(name: 'folder_id') String folderId, String path,@JsonKey(name: 'media_type') String mediaType,@JsonKey(name: 'size_bytes') int sizeBytes, String sha256, int revision,@JsonKey(name: 'created_at') DateTime createdAt,@JsonKey(name: 'updated_at') DateTime updatedAt
});




}
/// @nodoc
class __$FolderFileCopyWithImpl<$Res>
    implements _$FolderFileCopyWith<$Res> {
  __$FolderFileCopyWithImpl(this._self, this._then);

  final _FolderFile _self;
  final $Res Function(_FolderFile) _then;

/// Create a copy of FolderFile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? folderId = null,Object? path = null,Object? mediaType = null,Object? sizeBytes = null,Object? sha256 = null,Object? revision = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_FolderFile(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,folderId: null == folderId ? _self.folderId : folderId // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as String,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,sha256: null == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}


/// @nodoc
mixin _$FolderText {

 FolderFile get file; String get text; int get offset;@JsonKey(name: 'next_offset') int? get nextOffset;@JsonKey(name: 'total_chars') int get totalChars; bool get editable;
/// Create a copy of FolderText
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FolderTextCopyWith<FolderText> get copyWith => _$FolderTextCopyWithImpl<FolderText>(this as FolderText, _$identity);

  /// Serializes this FolderText to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FolderText&&(identical(other.file, file) || other.file == file)&&(identical(other.text, text) || other.text == text)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset)&&(identical(other.totalChars, totalChars) || other.totalChars == totalChars)&&(identical(other.editable, editable) || other.editable == editable));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,file,text,offset,nextOffset,totalChars,editable);

@override
String toString() {
  return 'FolderText(file: $file, text: $text, offset: $offset, nextOffset: $nextOffset, totalChars: $totalChars, editable: $editable)';
}


}

/// @nodoc
abstract mixin class $FolderTextCopyWith<$Res>  {
  factory $FolderTextCopyWith(FolderText value, $Res Function(FolderText) _then) = _$FolderTextCopyWithImpl;
@useResult
$Res call({
 FolderFile file, String text, int offset,@JsonKey(name: 'next_offset') int? nextOffset,@JsonKey(name: 'total_chars') int totalChars, bool editable
});


$FolderFileCopyWith<$Res> get file;

}
/// @nodoc
class _$FolderTextCopyWithImpl<$Res>
    implements $FolderTextCopyWith<$Res> {
  _$FolderTextCopyWithImpl(this._self, this._then);

  final FolderText _self;
  final $Res Function(FolderText) _then;

/// Create a copy of FolderText
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? file = null,Object? text = null,Object? offset = null,Object? nextOffset = freezed,Object? totalChars = null,Object? editable = null,}) {
  return _then(FolderText(
file: null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as FolderFile,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,totalChars: null == totalChars ? _self.totalChars : totalChars // ignore: cast_nullable_to_non_nullable
as int,editable: null == editable ? _self.editable : editable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of FolderText
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FolderFileCopyWith<$Res> get file {

  return $FolderFileCopyWith<$Res>(_self.file, (value) {
    return _then(_self.copyWith(file: value));
  });
}
}


/// Adds pattern-matching-related methods to [FolderText].
extension FolderTextPatterns on FolderText {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FolderText value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FolderText() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FolderText value)  $default,){
final _that = this;
switch (_that) {
case _FolderText():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FolderText value)?  $default,){
final _that = this;
switch (_that) {
case _FolderText() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( FolderFile file,  String text,  int offset, @JsonKey(name: 'next_offset')  int? nextOffset, @JsonKey(name: 'total_chars')  int totalChars,  bool editable)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FolderText() when $default != null:
return $default(_that.file,_that.text,_that.offset,_that.nextOffset,_that.totalChars,_that.editable);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( FolderFile file,  String text,  int offset, @JsonKey(name: 'next_offset')  int? nextOffset, @JsonKey(name: 'total_chars')  int totalChars,  bool editable)  $default,) {final _that = this;
switch (_that) {
case _FolderText():
return $default(_that.file,_that.text,_that.offset,_that.nextOffset,_that.totalChars,_that.editable);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( FolderFile file,  String text,  int offset, @JsonKey(name: 'next_offset')  int? nextOffset, @JsonKey(name: 'total_chars')  int totalChars,  bool editable)?  $default,) {final _that = this;
switch (_that) {
case _FolderText() when $default != null:
return $default(_that.file,_that.text,_that.offset,_that.nextOffset,_that.totalChars,_that.editable);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FolderText implements FolderText {
  const _FolderText({required this.file, required this.text, required this.offset, @JsonKey(name: 'next_offset') this.nextOffset, @JsonKey(name: 'total_chars') required this.totalChars, required this.editable});
  factory _FolderText.fromJson(Map<String, dynamic> json) => _$FolderTextFromJson(json);

@override final  FolderFile file;
@override final  String text;
@override final  int offset;
@override@JsonKey(name: 'next_offset') final  int? nextOffset;
@override@JsonKey(name: 'total_chars') final  int totalChars;
@override final  bool editable;

/// Create a copy of FolderText
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FolderTextCopyWith<_FolderText> get copyWith => __$FolderTextCopyWithImpl<_FolderText>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FolderTextToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FolderText&&(identical(other.file, file) || other.file == file)&&(identical(other.text, text) || other.text == text)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset)&&(identical(other.totalChars, totalChars) || other.totalChars == totalChars)&&(identical(other.editable, editable) || other.editable == editable));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,file,text,offset,nextOffset,totalChars,editable);

@override
String toString() {
  return 'FolderText(file: $file, text: $text, offset: $offset, nextOffset: $nextOffset, totalChars: $totalChars, editable: $editable)';
}


}

/// @nodoc
abstract mixin class _$FolderTextCopyWith<$Res> implements $FolderTextCopyWith<$Res> {
  factory _$FolderTextCopyWith(_FolderText value, $Res Function(_FolderText) _then) = __$FolderTextCopyWithImpl;
@override @useResult
$Res call({
 FolderFile file, String text, int offset,@JsonKey(name: 'next_offset') int? nextOffset,@JsonKey(name: 'total_chars') int totalChars, bool editable
});


@override $FolderFileCopyWith<$Res> get file;

}
/// @nodoc
class __$FolderTextCopyWithImpl<$Res>
    implements _$FolderTextCopyWith<$Res> {
  __$FolderTextCopyWithImpl(this._self, this._then);

  final _FolderText _self;
  final $Res Function(_FolderText) _then;

/// Create a copy of FolderText
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? file = null,Object? text = null,Object? offset = null,Object? nextOffset = freezed,Object? totalChars = null,Object? editable = null,}) {
  return _then(_FolderText(
file: null == file ? _self.file : file // ignore: cast_nullable_to_non_nullable
as FolderFile,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,totalChars: null == totalChars ? _self.totalChars : totalChars // ignore: cast_nullable_to_non_nullable
as int,editable: null == editable ? _self.editable : editable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of FolderText
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FolderFileCopyWith<$Res> get file {

  return $FolderFileCopyWith<$Res>(_self.file, (value) {
    return _then(_self.copyWith(file: value));
  });
}
}

// dart format on
