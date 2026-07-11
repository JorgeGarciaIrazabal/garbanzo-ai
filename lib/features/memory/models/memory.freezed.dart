// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'memory.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Memory {

 String get id; String get userId; String get content; String? get sourceConversationId; DateTime get createdAt; bool get isActive;
/// Create a copy of Memory
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemoryCopyWith<Memory> get copyWith => _$MemoryCopyWithImpl<Memory>(this as Memory, _$identity);

  /// Serializes this Memory to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Memory&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.content, content) || other.content == content)&&(identical(other.sourceConversationId, sourceConversationId) || other.sourceConversationId == sourceConversationId)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.isActive, isActive) || other.isActive == isActive));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,content,sourceConversationId,createdAt,isActive);

@override
String toString() {
  return 'Memory(id: $id, userId: $userId, content: $content, sourceConversationId: $sourceConversationId, createdAt: $createdAt, isActive: $isActive)';
}


}

/// @nodoc
abstract mixin class $MemoryCopyWith<$Res>  {
  factory $MemoryCopyWith(Memory value, $Res Function(Memory) _then) = _$MemoryCopyWithImpl;
@useResult
$Res call({
 String id, String userId, String content, String? sourceConversationId, DateTime createdAt, bool isActive
});




}
/// @nodoc
class _$MemoryCopyWithImpl<$Res>
    implements $MemoryCopyWith<$Res> {
  _$MemoryCopyWithImpl(this._self, this._then);

  final Memory _self;
  final $Res Function(Memory) _then;

/// Create a copy of Memory
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? userId = null,Object? content = null,Object? sourceConversationId = freezed,Object? createdAt = null,Object? isActive = null,}) {
  return _then(Memory(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,sourceConversationId: freezed == sourceConversationId ? _self.sourceConversationId : sourceConversationId // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [Memory].
extension MemoryPatterns on Memory {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Memory value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Memory() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Memory value)  $default,){
final _that = this;
switch (_that) {
case _Memory():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Memory value)?  $default,){
final _that = this;
switch (_that) {
case _Memory() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String userId,  String content,  String? sourceConversationId,  DateTime createdAt,  bool isActive)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Memory() when $default != null:
return $default(_that.id,_that.userId,_that.content,_that.sourceConversationId,_that.createdAt,_that.isActive);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String userId,  String content,  String? sourceConversationId,  DateTime createdAt,  bool isActive)  $default,) {final _that = this;
switch (_that) {
case _Memory():
return $default(_that.id,_that.userId,_that.content,_that.sourceConversationId,_that.createdAt,_that.isActive);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String userId,  String content,  String? sourceConversationId,  DateTime createdAt,  bool isActive)?  $default,) {final _that = this;
switch (_that) {
case _Memory() when $default != null:
return $default(_that.id,_that.userId,_that.content,_that.sourceConversationId,_that.createdAt,_that.isActive);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Memory extends Memory {
  const _Memory({required this.id, required this.userId, required this.content, this.sourceConversationId, required this.createdAt, required this.isActive}): super._();
  factory _Memory.fromJson(Map<String, dynamic> json) => _$MemoryFromJson(json);

@override final  String id;
@override final  String userId;
@override final  String content;
@override final  String? sourceConversationId;
@override final  DateTime createdAt;
@override final  bool isActive;

/// Create a copy of Memory
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemoryCopyWith<_Memory> get copyWith => __$MemoryCopyWithImpl<_Memory>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MemoryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Memory&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.content, content) || other.content == content)&&(identical(other.sourceConversationId, sourceConversationId) || other.sourceConversationId == sourceConversationId)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.isActive, isActive) || other.isActive == isActive));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,content,sourceConversationId,createdAt,isActive);

@override
String toString() {
  return 'Memory(id: $id, userId: $userId, content: $content, sourceConversationId: $sourceConversationId, createdAt: $createdAt, isActive: $isActive)';
}


}

/// @nodoc
abstract mixin class _$MemoryCopyWith<$Res> implements $MemoryCopyWith<$Res> {
  factory _$MemoryCopyWith(_Memory value, $Res Function(_Memory) _then) = __$MemoryCopyWithImpl;
@override @useResult
$Res call({
 String id, String userId, String content, String? sourceConversationId, DateTime createdAt, bool isActive
});




}
/// @nodoc
class __$MemoryCopyWithImpl<$Res>
    implements _$MemoryCopyWith<$Res> {
  __$MemoryCopyWithImpl(this._self, this._then);

  final _Memory _self;
  final $Res Function(_Memory) _then;

/// Create a copy of Memory
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? userId = null,Object? content = null,Object? sourceConversationId = freezed,Object? createdAt = null,Object? isActive = null,}) {
  return _then(_Memory(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,sourceConversationId: freezed == sourceConversationId ? _self.sourceConversationId : sourceConversationId // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$MemoryList {

 List<Memory> get items;
/// Create a copy of MemoryList
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemoryListCopyWith<MemoryList> get copyWith => _$MemoryListCopyWithImpl<MemoryList>(this as MemoryList, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MemoryList&&const DeepCollectionEquality().equals(other.items, items));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(items));

@override
String toString() {
  return 'MemoryList(items: $items)';
}


}

/// @nodoc
abstract mixin class $MemoryListCopyWith<$Res>  {
  factory $MemoryListCopyWith(MemoryList value, $Res Function(MemoryList) _then) = _$MemoryListCopyWithImpl;
@useResult
$Res call({
 List<Memory> items
});




}
/// @nodoc
class _$MemoryListCopyWithImpl<$Res>
    implements $MemoryListCopyWith<$Res> {
  _$MemoryListCopyWithImpl(this._self, this._then);

  final MemoryList _self;
  final $Res Function(MemoryList) _then;

/// Create a copy of MemoryList
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? items = null,}) {
  return _then(MemoryList(
items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<Memory>,
  ));
}

}


/// Adds pattern-matching-related methods to [MemoryList].
extension MemoryListPatterns on MemoryList {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MemoryList value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MemoryList() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MemoryList value)  $default,){
final _that = this;
switch (_that) {
case _MemoryList():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MemoryList value)?  $default,){
final _that = this;
switch (_that) {
case _MemoryList() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Memory> items)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MemoryList() when $default != null:
return $default(_that.items);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Memory> items)  $default,) {final _that = this;
switch (_that) {
case _MemoryList():
return $default(_that.items);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Memory> items)?  $default,) {final _that = this;
switch (_that) {
case _MemoryList() when $default != null:
return $default(_that.items);case _:
  return null;

}
}

}

/// @nodoc


class _MemoryList extends MemoryList {
  const _MemoryList({required  List<Memory> items}): _items = items,super._();
  

 final  List<Memory> _items;
@override List<Memory> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}


/// Create a copy of MemoryList
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemoryListCopyWith<_MemoryList> get copyWith => __$MemoryListCopyWithImpl<_MemoryList>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MemoryList&&const DeepCollectionEquality().equals(other._items, _items));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_items));

@override
String toString() {
  return 'MemoryList(items: $items)';
}


}

/// @nodoc
abstract mixin class _$MemoryListCopyWith<$Res> implements $MemoryListCopyWith<$Res> {
  factory _$MemoryListCopyWith(_MemoryList value, $Res Function(_MemoryList) _then) = __$MemoryListCopyWithImpl;
@override @useResult
$Res call({
 List<Memory> items
});




}
/// @nodoc
class __$MemoryListCopyWithImpl<$Res>
    implements _$MemoryListCopyWith<$Res> {
  __$MemoryListCopyWithImpl(this._self, this._then);

  final _MemoryList _self;
  final $Res Function(_MemoryList) _then;

/// Create a copy of MemoryList
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? items = null,}) {
  return _then(_MemoryList(
items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<Memory>,
  ));
}


}

// dart format on
