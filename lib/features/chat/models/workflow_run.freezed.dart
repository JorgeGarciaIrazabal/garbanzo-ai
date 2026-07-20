// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'workflow_run.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$WorkflowRun {

 String get id; String get userId; String? get conversationId; String? get roomId; String? get toolCallId; String get status; String get instruction; Map<String, dynamic>? get scope; String? get summary; String? get error; List<Map<String, dynamic>> get progress; int get progressOffset; int get progressTotal; DateTime get createdAt; DateTime get updatedAt; DateTime? get completedAt;
/// Create a copy of WorkflowRun
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowRunCopyWith<WorkflowRun> get copyWith => _$WorkflowRunCopyWithImpl<WorkflowRun>(this as WorkflowRun, _$identity);

  /// Serializes this WorkflowRun to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowRun&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.conversationId, conversationId) || other.conversationId == conversationId)&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.toolCallId, toolCallId) || other.toolCallId == toolCallId)&&(identical(other.status, status) || other.status == status)&&(identical(other.instruction, instruction) || other.instruction == instruction)&&const DeepCollectionEquality().equals(other.scope, scope)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.error, error) || other.error == error)&&const DeepCollectionEquality().equals(other.progress, progress)&&(identical(other.progressOffset, progressOffset) || other.progressOffset == progressOffset)&&(identical(other.progressTotal, progressTotal) || other.progressTotal == progressTotal)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,conversationId,roomId,toolCallId,status,instruction,const DeepCollectionEquality().hash(scope),summary,error,const DeepCollectionEquality().hash(progress),progressOffset,progressTotal,createdAt,updatedAt,completedAt);

@override
String toString() {
  return 'WorkflowRun(id: $id, userId: $userId, conversationId: $conversationId, roomId: $roomId, toolCallId: $toolCallId, status: $status, instruction: $instruction, scope: $scope, summary: $summary, error: $error, progress: $progress, progressOffset: $progressOffset, progressTotal: $progressTotal, createdAt: $createdAt, updatedAt: $updatedAt, completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class $WorkflowRunCopyWith<$Res>  {
  factory $WorkflowRunCopyWith(WorkflowRun value, $Res Function(WorkflowRun) _then) = _$WorkflowRunCopyWithImpl;
@useResult
$Res call({
 String id, String userId, String? conversationId, String? roomId, String? toolCallId, String status, String instruction, Map<String, dynamic>? scope, String? summary, String? error, List<Map<String, dynamic>> progress, int progressOffset, int progressTotal, DateTime createdAt, DateTime updatedAt, DateTime? completedAt
});




}
/// @nodoc
class _$WorkflowRunCopyWithImpl<$Res>
    implements $WorkflowRunCopyWith<$Res> {
  _$WorkflowRunCopyWithImpl(this._self, this._then);

  final WorkflowRun _self;
  final $Res Function(WorkflowRun) _then;

/// Create a copy of WorkflowRun
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? userId = null,Object? conversationId = freezed,Object? roomId = freezed,Object? toolCallId = freezed,Object? status = null,Object? instruction = null,Object? scope = freezed,Object? summary = freezed,Object? error = freezed,Object? progress = null,Object? progressOffset = null,Object? progressTotal = null,Object? createdAt = null,Object? updatedAt = null,Object? completedAt = freezed,}) {
  return _then(WorkflowRun(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,conversationId: freezed == conversationId ? _self.conversationId : conversationId // ignore: cast_nullable_to_non_nullable
as String?,roomId: freezed == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String?,toolCallId: freezed == toolCallId ? _self.toolCallId : toolCallId // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,instruction: null == instruction ? _self.instruction : instruction // ignore: cast_nullable_to_non_nullable
as String,scope: freezed == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>,progressOffset: null == progressOffset ? _self.progressOffset : progressOffset // ignore: cast_nullable_to_non_nullable
as int,progressTotal: null == progressTotal ? _self.progressTotal : progressTotal // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkflowRun].
extension WorkflowRunPatterns on WorkflowRun {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkflowRun value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkflowRun() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkflowRun value)  $default,){
final _that = this;
switch (_that) {
case _WorkflowRun():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkflowRun value)?  $default,){
final _that = this;
switch (_that) {
case _WorkflowRun() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String userId,  String? conversationId,  String? roomId,  String? toolCallId,  String status,  String instruction,  Map<String, dynamic>? scope,  String? summary,  String? error,  List<Map<String, dynamic>> progress,  int progressOffset,  int progressTotal,  DateTime createdAt,  DateTime updatedAt,  DateTime? completedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkflowRun() when $default != null:
return $default(_that.id,_that.userId,_that.conversationId,_that.roomId,_that.toolCallId,_that.status,_that.instruction,_that.scope,_that.summary,_that.error,_that.progress,_that.progressOffset,_that.progressTotal,_that.createdAt,_that.updatedAt,_that.completedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String userId,  String? conversationId,  String? roomId,  String? toolCallId,  String status,  String instruction,  Map<String, dynamic>? scope,  String? summary,  String? error,  List<Map<String, dynamic>> progress,  int progressOffset,  int progressTotal,  DateTime createdAt,  DateTime updatedAt,  DateTime? completedAt)  $default,) {final _that = this;
switch (_that) {
case _WorkflowRun():
return $default(_that.id,_that.userId,_that.conversationId,_that.roomId,_that.toolCallId,_that.status,_that.instruction,_that.scope,_that.summary,_that.error,_that.progress,_that.progressOffset,_that.progressTotal,_that.createdAt,_that.updatedAt,_that.completedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String userId,  String? conversationId,  String? roomId,  String? toolCallId,  String status,  String instruction,  Map<String, dynamic>? scope,  String? summary,  String? error,  List<Map<String, dynamic>> progress,  int progressOffset,  int progressTotal,  DateTime createdAt,  DateTime updatedAt,  DateTime? completedAt)?  $default,) {final _that = this;
switch (_that) {
case _WorkflowRun() when $default != null:
return $default(_that.id,_that.userId,_that.conversationId,_that.roomId,_that.toolCallId,_that.status,_that.instruction,_that.scope,_that.summary,_that.error,_that.progress,_that.progressOffset,_that.progressTotal,_that.createdAt,_that.updatedAt,_that.completedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WorkflowRun extends WorkflowRun {
  const _WorkflowRun({required this.id, required this.userId, this.conversationId, this.roomId, this.toolCallId, required this.status, required this.instruction,  Map<String, dynamic>? scope, this.summary, this.error,  List<Map<String, dynamic>> progress = const <Map<String, dynamic>>[], this.progressOffset = 0, this.progressTotal = 0, required this.createdAt, required this.updatedAt, this.completedAt}): _scope = scope,_progress = progress,super._();
  factory _WorkflowRun.fromJson(Map<String, dynamic> json) => _$WorkflowRunFromJson(json);

@override final  String id;
@override final  String userId;
@override final  String? conversationId;
@override final  String? roomId;
@override final  String? toolCallId;
@override final  String status;
@override final  String instruction;
 final  Map<String, dynamic>? _scope;
@override Map<String, dynamic>? get scope {
  final value = _scope;
  if (value == null) return null;
  if (_scope is EqualUnmodifiableMapView) return _scope;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

@override final  String? summary;
@override final  String? error;
 final  List<Map<String, dynamic>> _progress;
@override@JsonKey() List<Map<String, dynamic>> get progress {
  if (_progress is EqualUnmodifiableListView) return _progress;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_progress);
}

@override@JsonKey() final  int progressOffset;
@override@JsonKey() final  int progressTotal;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override final  DateTime? completedAt;

/// Create a copy of WorkflowRun
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkflowRunCopyWith<_WorkflowRun> get copyWith => __$WorkflowRunCopyWithImpl<_WorkflowRun>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WorkflowRunToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkflowRun&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.conversationId, conversationId) || other.conversationId == conversationId)&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.toolCallId, toolCallId) || other.toolCallId == toolCallId)&&(identical(other.status, status) || other.status == status)&&(identical(other.instruction, instruction) || other.instruction == instruction)&&const DeepCollectionEquality().equals(other._scope, _scope)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.error, error) || other.error == error)&&const DeepCollectionEquality().equals(other._progress, _progress)&&(identical(other.progressOffset, progressOffset) || other.progressOffset == progressOffset)&&(identical(other.progressTotal, progressTotal) || other.progressTotal == progressTotal)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,conversationId,roomId,toolCallId,status,instruction,const DeepCollectionEquality().hash(_scope),summary,error,const DeepCollectionEquality().hash(_progress),progressOffset,progressTotal,createdAt,updatedAt,completedAt);

@override
String toString() {
  return 'WorkflowRun(id: $id, userId: $userId, conversationId: $conversationId, roomId: $roomId, toolCallId: $toolCallId, status: $status, instruction: $instruction, scope: $scope, summary: $summary, error: $error, progress: $progress, progressOffset: $progressOffset, progressTotal: $progressTotal, createdAt: $createdAt, updatedAt: $updatedAt, completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class _$WorkflowRunCopyWith<$Res> implements $WorkflowRunCopyWith<$Res> {
  factory _$WorkflowRunCopyWith(_WorkflowRun value, $Res Function(_WorkflowRun) _then) = __$WorkflowRunCopyWithImpl;
@override @useResult
$Res call({
 String id, String userId, String? conversationId, String? roomId, String? toolCallId, String status, String instruction, Map<String, dynamic>? scope, String? summary, String? error, List<Map<String, dynamic>> progress, int progressOffset, int progressTotal, DateTime createdAt, DateTime updatedAt, DateTime? completedAt
});




}
/// @nodoc
class __$WorkflowRunCopyWithImpl<$Res>
    implements _$WorkflowRunCopyWith<$Res> {
  __$WorkflowRunCopyWithImpl(this._self, this._then);

  final _WorkflowRun _self;
  final $Res Function(_WorkflowRun) _then;

/// Create a copy of WorkflowRun
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? userId = null,Object? conversationId = freezed,Object? roomId = freezed,Object? toolCallId = freezed,Object? status = null,Object? instruction = null,Object? scope = freezed,Object? summary = freezed,Object? error = freezed,Object? progress = null,Object? progressOffset = null,Object? progressTotal = null,Object? createdAt = null,Object? updatedAt = null,Object? completedAt = freezed,}) {
  return _then(_WorkflowRun(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,conversationId: freezed == conversationId ? _self.conversationId : conversationId // ignore: cast_nullable_to_non_nullable
as String?,roomId: freezed == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String?,toolCallId: freezed == toolCallId ? _self.toolCallId : toolCallId // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,instruction: null == instruction ? _self.instruction : instruction // ignore: cast_nullable_to_non_nullable
as String,scope: freezed == scope ? _self._scope : scope // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,progress: null == progress ? _self._progress : progress // ignore: cast_nullable_to_non_nullable
as List<Map<String, dynamic>>,progressOffset: null == progressOffset ? _self.progressOffset : progressOffset // ignore: cast_nullable_to_non_nullable
as int,progressTotal: null == progressTotal ? _self.progressTotal : progressTotal // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}


/// @nodoc
mixin _$WorkflowChange {

 String get path; String get status;/// Base64 of the new content; null for deletions (and for files too large
/// to send back, which are reported as skipped).
 String? get data;/// sha256 of the content that was uploaded. The local file must still
/// match this, or the user edited it during the run and applying would
/// clobber their work.
 String? get baseSha256; int get size;
/// Create a copy of WorkflowChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowChangeCopyWith<WorkflowChange> get copyWith => _$WorkflowChangeCopyWithImpl<WorkflowChange>(this as WorkflowChange, _$identity);

  /// Serializes this WorkflowChange to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowChange&&(identical(other.path, path) || other.path == path)&&(identical(other.status, status) || other.status == status)&&(identical(other.data, data) || other.data == data)&&(identical(other.baseSha256, baseSha256) || other.baseSha256 == baseSha256)&&(identical(other.size, size) || other.size == size));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,path,status,data,baseSha256,size);

@override
String toString() {
  return 'WorkflowChange(path: $path, status: $status, data: $data, baseSha256: $baseSha256, size: $size)';
}


}

/// @nodoc
abstract mixin class $WorkflowChangeCopyWith<$Res>  {
  factory $WorkflowChangeCopyWith(WorkflowChange value, $Res Function(WorkflowChange) _then) = _$WorkflowChangeCopyWithImpl;
@useResult
$Res call({
 String path, String status, String? data, String? baseSha256, int size
});




}
/// @nodoc
class _$WorkflowChangeCopyWithImpl<$Res>
    implements $WorkflowChangeCopyWith<$Res> {
  _$WorkflowChangeCopyWithImpl(this._self, this._then);

  final WorkflowChange _self;
  final $Res Function(WorkflowChange) _then;

/// Create a copy of WorkflowChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? status = null,Object? data = freezed,Object? baseSha256 = freezed,Object? size = null,}) {
  return _then(WorkflowChange(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as String?,baseSha256: freezed == baseSha256 ? _self.baseSha256 : baseSha256 // ignore: cast_nullable_to_non_nullable
as String?,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkflowChange].
extension WorkflowChangePatterns on WorkflowChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkflowChange value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkflowChange() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkflowChange value)  $default,){
final _that = this;
switch (_that) {
case _WorkflowChange():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkflowChange value)?  $default,){
final _that = this;
switch (_that) {
case _WorkflowChange() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String path,  String status,  String? data,  String? baseSha256,  int size)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkflowChange() when $default != null:
return $default(_that.path,_that.status,_that.data,_that.baseSha256,_that.size);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String path,  String status,  String? data,  String? baseSha256,  int size)  $default,) {final _that = this;
switch (_that) {
case _WorkflowChange():
return $default(_that.path,_that.status,_that.data,_that.baseSha256,_that.size);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String path,  String status,  String? data,  String? baseSha256,  int size)?  $default,) {final _that = this;
switch (_that) {
case _WorkflowChange() when $default != null:
return $default(_that.path,_that.status,_that.data,_that.baseSha256,_that.size);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _WorkflowChange extends WorkflowChange {
  const _WorkflowChange({required this.path, required this.status, this.data, this.baseSha256, this.size = 0}): super._();
  factory _WorkflowChange.fromJson(Map<String, dynamic> json) => _$WorkflowChangeFromJson(json);

@override final  String path;
@override final  String status;
/// Base64 of the new content; null for deletions (and for files too large
/// to send back, which are reported as skipped).
@override final  String? data;
/// sha256 of the content that was uploaded. The local file must still
/// match this, or the user edited it during the run and applying would
/// clobber their work.
@override final  String? baseSha256;
@override@JsonKey() final  int size;

/// Create a copy of WorkflowChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkflowChangeCopyWith<_WorkflowChange> get copyWith => __$WorkflowChangeCopyWithImpl<_WorkflowChange>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$WorkflowChangeToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkflowChange&&(identical(other.path, path) || other.path == path)&&(identical(other.status, status) || other.status == status)&&(identical(other.data, data) || other.data == data)&&(identical(other.baseSha256, baseSha256) || other.baseSha256 == baseSha256)&&(identical(other.size, size) || other.size == size));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,path,status,data,baseSha256,size);

@override
String toString() {
  return 'WorkflowChange(path: $path, status: $status, data: $data, baseSha256: $baseSha256, size: $size)';
}


}

/// @nodoc
abstract mixin class _$WorkflowChangeCopyWith<$Res> implements $WorkflowChangeCopyWith<$Res> {
  factory _$WorkflowChangeCopyWith(_WorkflowChange value, $Res Function(_WorkflowChange) _then) = __$WorkflowChangeCopyWithImpl;
@override @useResult
$Res call({
 String path, String status, String? data, String? baseSha256, int size
});




}
/// @nodoc
class __$WorkflowChangeCopyWithImpl<$Res>
    implements _$WorkflowChangeCopyWith<$Res> {
  __$WorkflowChangeCopyWithImpl(this._self, this._then);

  final _WorkflowChange _self;
  final $Res Function(_WorkflowChange) _then;

/// Create a copy of WorkflowChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? status = null,Object? data = freezed,Object? baseSha256 = freezed,Object? size = null,}) {
  return _then(_WorkflowChange(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,data: freezed == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as String?,baseSha256: freezed == baseSha256 ? _self.baseSha256 : baseSha256 // ignore: cast_nullable_to_non_nullable
as String?,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
