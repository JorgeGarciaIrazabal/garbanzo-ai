// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'agent_progress.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AgentProgress {

 List<AgentStep> get steps; bool get live;/// Seconds since the run started, as last reported by a heartbeat. Null
/// when no heartbeat has arrived yet (the client then falls back to its
/// own clock from [startedAt]).
 int? get heartbeatElapsedSeconds;/// Seconds since the last signal of any kind. The UI surfaces this so a
/// quiet agent is visibly quiet rather than ambiguously idle.
 int? get secondsSinceSignal; DateTime? get startedAt; DateTime? get finishedAt;/// Most recent activity reported by a heartbeat, used when no step is
/// available yet (e.g. the model is still loading).
 String? get heartbeatActivity;/// Steps completed, from the heartbeat. Distinct from `steps.length`
/// because the stream may have been joined mid-run.
 int get completedCount;
/// Create a copy of AgentProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProgressCopyWith<AgentProgress> get copyWith => _$AgentProgressCopyWithImpl<AgentProgress>(this as AgentProgress, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProgress&&const DeepCollectionEquality().equals(other.steps, steps)&&(identical(other.live, live) || other.live == live)&&(identical(other.heartbeatElapsedSeconds, heartbeatElapsedSeconds) || other.heartbeatElapsedSeconds == heartbeatElapsedSeconds)&&(identical(other.secondsSinceSignal, secondsSinceSignal) || other.secondsSinceSignal == secondsSinceSignal)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.heartbeatActivity, heartbeatActivity) || other.heartbeatActivity == heartbeatActivity)&&(identical(other.completedCount, completedCount) || other.completedCount == completedCount));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(steps),live,heartbeatElapsedSeconds,secondsSinceSignal,startedAt,finishedAt,heartbeatActivity,completedCount);

@override
String toString() {
  return 'AgentProgress(steps: $steps, live: $live, heartbeatElapsedSeconds: $heartbeatElapsedSeconds, secondsSinceSignal: $secondsSinceSignal, startedAt: $startedAt, finishedAt: $finishedAt, heartbeatActivity: $heartbeatActivity, completedCount: $completedCount)';
}


}

/// @nodoc
abstract mixin class $AgentProgressCopyWith<$Res>  {
  factory $AgentProgressCopyWith(AgentProgress value, $Res Function(AgentProgress) _then) = _$AgentProgressCopyWithImpl;
@useResult
$Res call({
 List<AgentStep> steps, bool live, int? heartbeatElapsedSeconds, int? secondsSinceSignal, DateTime? startedAt, DateTime? finishedAt, String? heartbeatActivity, int completedCount
});




}
/// @nodoc
class _$AgentProgressCopyWithImpl<$Res>
    implements $AgentProgressCopyWith<$Res> {
  _$AgentProgressCopyWithImpl(this._self, this._then);

  final AgentProgress _self;
  final $Res Function(AgentProgress) _then;

/// Create a copy of AgentProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? steps = null,Object? live = null,Object? heartbeatElapsedSeconds = freezed,Object? secondsSinceSignal = freezed,Object? startedAt = freezed,Object? finishedAt = freezed,Object? heartbeatActivity = freezed,Object? completedCount = null,}) {
  return _then(AgentProgress(
steps: null == steps ? _self.steps : steps // ignore: cast_nullable_to_non_nullable
as List<AgentStep>,live: null == live ? _self.live : live // ignore: cast_nullable_to_non_nullable
as bool,heartbeatElapsedSeconds: freezed == heartbeatElapsedSeconds ? _self.heartbeatElapsedSeconds : heartbeatElapsedSeconds // ignore: cast_nullable_to_non_nullable
as int?,secondsSinceSignal: freezed == secondsSinceSignal ? _self.secondsSinceSignal : secondsSinceSignal // ignore: cast_nullable_to_non_nullable
as int?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,finishedAt: freezed == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,heartbeatActivity: freezed == heartbeatActivity ? _self.heartbeatActivity : heartbeatActivity // ignore: cast_nullable_to_non_nullable
as String?,completedCount: null == completedCount ? _self.completedCount : completedCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AgentProgress].
extension AgentProgressPatterns on AgentProgress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentProgress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentProgress() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentProgress value)  $default,){
final _that = this;
switch (_that) {
case _AgentProgress():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentProgress value)?  $default,){
final _that = this;
switch (_that) {
case _AgentProgress() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<AgentStep> steps,  bool live,  int? heartbeatElapsedSeconds,  int? secondsSinceSignal,  DateTime? startedAt,  DateTime? finishedAt,  String? heartbeatActivity,  int completedCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentProgress() when $default != null:
return $default(_that.steps,_that.live,_that.heartbeatElapsedSeconds,_that.secondsSinceSignal,_that.startedAt,_that.finishedAt,_that.heartbeatActivity,_that.completedCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<AgentStep> steps,  bool live,  int? heartbeatElapsedSeconds,  int? secondsSinceSignal,  DateTime? startedAt,  DateTime? finishedAt,  String? heartbeatActivity,  int completedCount)  $default,) {final _that = this;
switch (_that) {
case _AgentProgress():
return $default(_that.steps,_that.live,_that.heartbeatElapsedSeconds,_that.secondsSinceSignal,_that.startedAt,_that.finishedAt,_that.heartbeatActivity,_that.completedCount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<AgentStep> steps,  bool live,  int? heartbeatElapsedSeconds,  int? secondsSinceSignal,  DateTime? startedAt,  DateTime? finishedAt,  String? heartbeatActivity,  int completedCount)?  $default,) {final _that = this;
switch (_that) {
case _AgentProgress() when $default != null:
return $default(_that.steps,_that.live,_that.heartbeatElapsedSeconds,_that.secondsSinceSignal,_that.startedAt,_that.finishedAt,_that.heartbeatActivity,_that.completedCount);case _:
  return null;

}
}

}

/// @nodoc


class _AgentProgress extends AgentProgress {
  const _AgentProgress({ List<AgentStep> steps = const <AgentStep>[], this.live = false, this.heartbeatElapsedSeconds, this.secondsSinceSignal, this.startedAt, this.finishedAt, this.heartbeatActivity, this.completedCount = 0}): _steps = steps,super._();
  

 final  List<AgentStep> _steps;
@override@JsonKey() List<AgentStep> get steps {
  if (_steps is EqualUnmodifiableListView) return _steps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_steps);
}

@override@JsonKey() final  bool live;
/// Seconds since the run started, as last reported by a heartbeat. Null
/// when no heartbeat has arrived yet (the client then falls back to its
/// own clock from [startedAt]).
@override final  int? heartbeatElapsedSeconds;
/// Seconds since the last signal of any kind. The UI surfaces this so a
/// quiet agent is visibly quiet rather than ambiguously idle.
@override final  int? secondsSinceSignal;
@override final  DateTime? startedAt;
@override final  DateTime? finishedAt;
/// Most recent activity reported by a heartbeat, used when no step is
/// available yet (e.g. the model is still loading).
@override final  String? heartbeatActivity;
/// Steps completed, from the heartbeat. Distinct from `steps.length`
/// because the stream may have been joined mid-run.
@override@JsonKey() final  int completedCount;

/// Create a copy of AgentProgress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentProgressCopyWith<_AgentProgress> get copyWith => __$AgentProgressCopyWithImpl<_AgentProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentProgress&&const DeepCollectionEquality().equals(other._steps, _steps)&&(identical(other.live, live) || other.live == live)&&(identical(other.heartbeatElapsedSeconds, heartbeatElapsedSeconds) || other.heartbeatElapsedSeconds == heartbeatElapsedSeconds)&&(identical(other.secondsSinceSignal, secondsSinceSignal) || other.secondsSinceSignal == secondsSinceSignal)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.heartbeatActivity, heartbeatActivity) || other.heartbeatActivity == heartbeatActivity)&&(identical(other.completedCount, completedCount) || other.completedCount == completedCount));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_steps),live,heartbeatElapsedSeconds,secondsSinceSignal,startedAt,finishedAt,heartbeatActivity,completedCount);

@override
String toString() {
  return 'AgentProgress(steps: $steps, live: $live, heartbeatElapsedSeconds: $heartbeatElapsedSeconds, secondsSinceSignal: $secondsSinceSignal, startedAt: $startedAt, finishedAt: $finishedAt, heartbeatActivity: $heartbeatActivity, completedCount: $completedCount)';
}


}

/// @nodoc
abstract mixin class _$AgentProgressCopyWith<$Res> implements $AgentProgressCopyWith<$Res> {
  factory _$AgentProgressCopyWith(_AgentProgress value, $Res Function(_AgentProgress) _then) = __$AgentProgressCopyWithImpl;
@override @useResult
$Res call({
 List<AgentStep> steps, bool live, int? heartbeatElapsedSeconds, int? secondsSinceSignal, DateTime? startedAt, DateTime? finishedAt, String? heartbeatActivity, int completedCount
});




}
/// @nodoc
class __$AgentProgressCopyWithImpl<$Res>
    implements _$AgentProgressCopyWith<$Res> {
  __$AgentProgressCopyWithImpl(this._self, this._then);

  final _AgentProgress _self;
  final $Res Function(_AgentProgress) _then;

/// Create a copy of AgentProgress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? steps = null,Object? live = null,Object? heartbeatElapsedSeconds = freezed,Object? secondsSinceSignal = freezed,Object? startedAt = freezed,Object? finishedAt = freezed,Object? heartbeatActivity = freezed,Object? completedCount = null,}) {
  return _then(_AgentProgress(
steps: null == steps ? _self._steps : steps // ignore: cast_nullable_to_non_nullable
as List<AgentStep>,live: null == live ? _self.live : live // ignore: cast_nullable_to_non_nullable
as bool,heartbeatElapsedSeconds: freezed == heartbeatElapsedSeconds ? _self.heartbeatElapsedSeconds : heartbeatElapsedSeconds // ignore: cast_nullable_to_non_nullable
as int?,secondsSinceSignal: freezed == secondsSinceSignal ? _self.secondsSinceSignal : secondsSinceSignal // ignore: cast_nullable_to_non_nullable
as int?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,finishedAt: freezed == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,heartbeatActivity: freezed == heartbeatActivity ? _self.heartbeatActivity : heartbeatActivity // ignore: cast_nullable_to_non_nullable
as String?,completedCount: null == completedCount ? _self.completedCount : completedCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
