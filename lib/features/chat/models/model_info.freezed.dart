// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ModelInfo {

 String get id; String get name; String? get description; int? get contextLength; String get provider; bool? get supportsTools; bool? get supportsVision; bool? get supportsThinking;
/// Create a copy of ModelInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelInfoCopyWith<ModelInfo> get copyWith => _$ModelInfoCopyWithImpl<ModelInfo>(this as ModelInfo, _$identity);

  /// Serializes this ModelInfo to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelInfo&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.contextLength, contextLength) || other.contextLength == contextLength)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.supportsTools, supportsTools) || other.supportsTools == supportsTools)&&(identical(other.supportsVision, supportsVision) || other.supportsVision == supportsVision)&&(identical(other.supportsThinking, supportsThinking) || other.supportsThinking == supportsThinking));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,description,contextLength,provider,supportsTools,supportsVision,supportsThinking);

@override
String toString() {
  return 'ModelInfo(id: $id, name: $name, description: $description, contextLength: $contextLength, provider: $provider, supportsTools: $supportsTools, supportsVision: $supportsVision, supportsThinking: $supportsThinking)';
}


}

/// @nodoc
abstract mixin class $ModelInfoCopyWith<$Res>  {
  factory $ModelInfoCopyWith(ModelInfo value, $Res Function(ModelInfo) _then) = _$ModelInfoCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? description, int? contextLength, String provider, bool? supportsTools, bool? supportsVision, bool? supportsThinking
});




}
/// @nodoc
class _$ModelInfoCopyWithImpl<$Res>
    implements $ModelInfoCopyWith<$Res> {
  _$ModelInfoCopyWithImpl(this._self, this._then);

  final ModelInfo _self;
  final $Res Function(ModelInfo) _then;

/// Create a copy of ModelInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? contextLength = freezed,Object? provider = null,Object? supportsTools = freezed,Object? supportsVision = freezed,Object? supportsThinking = freezed,}) {
  return _then(ModelInfo(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,contextLength: freezed == contextLength ? _self.contextLength : contextLength // ignore: cast_nullable_to_non_nullable
as int?,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as String,supportsTools: freezed == supportsTools ? _self.supportsTools : supportsTools // ignore: cast_nullable_to_non_nullable
as bool?,supportsVision: freezed == supportsVision ? _self.supportsVision : supportsVision // ignore: cast_nullable_to_non_nullable
as bool?,supportsThinking: freezed == supportsThinking ? _self.supportsThinking : supportsThinking // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelInfo].
extension ModelInfoPatterns on ModelInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelInfo value)  $default,){
final _that = this;
switch (_that) {
case _ModelInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelInfo value)?  $default,){
final _that = this;
switch (_that) {
case _ModelInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? description,  int? contextLength,  String provider,  bool? supportsTools,  bool? supportsVision,  bool? supportsThinking)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelInfo() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.contextLength,_that.provider,_that.supportsTools,_that.supportsVision,_that.supportsThinking);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? description,  int? contextLength,  String provider,  bool? supportsTools,  bool? supportsVision,  bool? supportsThinking)  $default,) {final _that = this;
switch (_that) {
case _ModelInfo():
return $default(_that.id,_that.name,_that.description,_that.contextLength,_that.provider,_that.supportsTools,_that.supportsVision,_that.supportsThinking);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? description,  int? contextLength,  String provider,  bool? supportsTools,  bool? supportsVision,  bool? supportsThinking)?  $default,) {final _that = this;
switch (_that) {
case _ModelInfo() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.contextLength,_that.provider,_that.supportsTools,_that.supportsVision,_that.supportsThinking);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ModelInfo implements ModelInfo {
  const _ModelInfo({required this.id, required this.name, this.description, this.contextLength, required this.provider, this.supportsTools, this.supportsVision, this.supportsThinking});
  factory _ModelInfo.fromJson(Map<String, dynamic> json) => _$ModelInfoFromJson(json);

@override final  String id;
@override final  String name;
@override final  String? description;
@override final  int? contextLength;
@override final  String provider;
@override final  bool? supportsTools;
@override final  bool? supportsVision;
@override final  bool? supportsThinking;

/// Create a copy of ModelInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelInfoCopyWith<_ModelInfo> get copyWith => __$ModelInfoCopyWithImpl<_ModelInfo>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ModelInfoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelInfo&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.contextLength, contextLength) || other.contextLength == contextLength)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.supportsTools, supportsTools) || other.supportsTools == supportsTools)&&(identical(other.supportsVision, supportsVision) || other.supportsVision == supportsVision)&&(identical(other.supportsThinking, supportsThinking) || other.supportsThinking == supportsThinking));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,description,contextLength,provider,supportsTools,supportsVision,supportsThinking);

@override
String toString() {
  return 'ModelInfo(id: $id, name: $name, description: $description, contextLength: $contextLength, provider: $provider, supportsTools: $supportsTools, supportsVision: $supportsVision, supportsThinking: $supportsThinking)';
}


}

/// @nodoc
abstract mixin class _$ModelInfoCopyWith<$Res> implements $ModelInfoCopyWith<$Res> {
  factory _$ModelInfoCopyWith(_ModelInfo value, $Res Function(_ModelInfo) _then) = __$ModelInfoCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? description, int? contextLength, String provider, bool? supportsTools, bool? supportsVision, bool? supportsThinking
});




}
/// @nodoc
class __$ModelInfoCopyWithImpl<$Res>
    implements _$ModelInfoCopyWith<$Res> {
  __$ModelInfoCopyWithImpl(this._self, this._then);

  final _ModelInfo _self;
  final $Res Function(_ModelInfo) _then;

/// Create a copy of ModelInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? contextLength = freezed,Object? provider = null,Object? supportsTools = freezed,Object? supportsVision = freezed,Object? supportsThinking = freezed,}) {
  return _then(_ModelInfo(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,contextLength: freezed == contextLength ? _self.contextLength : contextLength // ignore: cast_nullable_to_non_nullable
as int?,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as String,supportsTools: freezed == supportsTools ? _self.supportsTools : supportsTools // ignore: cast_nullable_to_non_nullable
as bool?,supportsVision: freezed == supportsVision ? _self.supportsVision : supportsVision // ignore: cast_nullable_to_non_nullable
as bool?,supportsThinking: freezed == supportsThinking ? _self.supportsThinking : supportsThinking // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}


/// @nodoc
mixin _$ModelList {

 List<ModelInfo> get models;
/// Create a copy of ModelList
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelListCopyWith<ModelList> get copyWith => _$ModelListCopyWithImpl<ModelList>(this as ModelList, _$identity);

  /// Serializes this ModelList to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelList&&const DeepCollectionEquality().equals(other.models, models));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(models));

@override
String toString() {
  return 'ModelList(models: $models)';
}


}

/// @nodoc
abstract mixin class $ModelListCopyWith<$Res>  {
  factory $ModelListCopyWith(ModelList value, $Res Function(ModelList) _then) = _$ModelListCopyWithImpl;
@useResult
$Res call({
 List<ModelInfo> models
});




}
/// @nodoc
class _$ModelListCopyWithImpl<$Res>
    implements $ModelListCopyWith<$Res> {
  _$ModelListCopyWithImpl(this._self, this._then);

  final ModelList _self;
  final $Res Function(ModelList) _then;

/// Create a copy of ModelList
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? models = null,}) {
  return _then(ModelList(
models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as List<ModelInfo>,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelList].
extension ModelListPatterns on ModelList {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelList value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelList() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelList value)  $default,){
final _that = this;
switch (_that) {
case _ModelList():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelList value)?  $default,){
final _that = this;
switch (_that) {
case _ModelList() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<ModelInfo> models)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelList() when $default != null:
return $default(_that.models);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<ModelInfo> models)  $default,) {final _that = this;
switch (_that) {
case _ModelList():
return $default(_that.models);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<ModelInfo> models)?  $default,) {final _that = this;
switch (_that) {
case _ModelList() when $default != null:
return $default(_that.models);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ModelList implements ModelList {
  const _ModelList({required  List<ModelInfo> models}): _models = models;
  factory _ModelList.fromJson(Map<String, dynamic> json) => _$ModelListFromJson(json);

 final  List<ModelInfo> _models;
@override List<ModelInfo> get models {
  if (_models is EqualUnmodifiableListView) return _models;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_models);
}


/// Create a copy of ModelList
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelListCopyWith<_ModelList> get copyWith => __$ModelListCopyWithImpl<_ModelList>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ModelListToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelList&&const DeepCollectionEquality().equals(other._models, _models));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_models));

@override
String toString() {
  return 'ModelList(models: $models)';
}


}

/// @nodoc
abstract mixin class _$ModelListCopyWith<$Res> implements $ModelListCopyWith<$Res> {
  factory _$ModelListCopyWith(_ModelList value, $Res Function(_ModelList) _then) = __$ModelListCopyWithImpl;
@override @useResult
$Res call({
 List<ModelInfo> models
});




}
/// @nodoc
class __$ModelListCopyWithImpl<$Res>
    implements _$ModelListCopyWith<$Res> {
  __$ModelListCopyWithImpl(this._self, this._then);

  final _ModelList _self;
  final $Res Function(_ModelList) _then;

/// Create a copy of ModelList
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? models = null,}) {
  return _then(_ModelList(
models: null == models ? _self._models : models // ignore: cast_nullable_to_non_nullable
as List<ModelInfo>,
  ));
}


}

// dart format on
