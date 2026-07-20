// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workflow_run.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_WorkflowRun _$WorkflowRunFromJson(Map<String, dynamic> json) => _WorkflowRun(
  id: json['id'] as String,
  userId: json['user_id'] as String,
  conversationId: json['conversation_id'] as String?,
  roomId: json['room_id'] as String?,
  toolCallId: json['tool_call_id'] as String?,
  status: json['status'] as String,
  instruction: json['instruction'] as String,
  scope: json['scope'] as Map<String, dynamic>?,
  summary: json['summary'] as String?,
  error: json['error'] as String?,
  progress:
      (json['progress'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList() ??
      const <Map<String, dynamic>>[],
  progressOffset: (json['progress_offset'] as num?)?.toInt() ?? 0,
  progressTotal: (json['progress_total'] as num?)?.toInt() ?? 0,
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
  completedAt: json['completed_at'] == null
      ? null
      : DateTime.parse(json['completed_at'] as String),
);

Map<String, dynamic> _$WorkflowRunToJson(_WorkflowRun instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'conversation_id': instance.conversationId,
      'room_id': instance.roomId,
      'tool_call_id': instance.toolCallId,
      'status': instance.status,
      'instruction': instance.instruction,
      'scope': instance.scope,
      'summary': instance.summary,
      'error': instance.error,
      'progress': instance.progress,
      'progress_offset': instance.progressOffset,
      'progress_total': instance.progressTotal,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'completed_at': instance.completedAt?.toIso8601String(),
    };

_WorkflowChange _$WorkflowChangeFromJson(Map<String, dynamic> json) =>
    _WorkflowChange(
      path: json['path'] as String,
      status: json['status'] as String,
      data: json['data'] as String?,
      baseSha256: json['base_sha256'] as String?,
      size: (json['size'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$WorkflowChangeToJson(_WorkflowChange instance) =>
    <String, dynamic>{
      'path': instance.path,
      'status': instance.status,
      'data': instance.data,
      'base_sha256': instance.baseSha256,
      'size': instance.size,
    };
