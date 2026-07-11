import 'package:freezed_annotation/freezed_annotation.dart';

part 'memory.freezed.dart';
part 'memory.g.dart';

/// A memory stored about a user, extracted from conversations or manually created.
@freezed
abstract class Memory with _$Memory {
  const Memory._();

  const factory Memory({
    required String id,
    required String userId,
    required String content,
    String? sourceConversationId,
    required DateTime createdAt,
    required bool isActive,
  }) = _Memory;

  factory Memory.fromJson(Map<String, dynamic> json) => _$MemoryFromJson(json);
}

/// A list of memories.
@freezed
abstract class MemoryList with _$MemoryList {
  const MemoryList._();

  const factory MemoryList({required List<Memory> items}) = _MemoryList;

  factory MemoryList.fromJson(Map<String, dynamic> json) {
    final items =
        (json['items'] as List?)
            ?.map((e) => Memory.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return MemoryList(items: items);
  }
}
