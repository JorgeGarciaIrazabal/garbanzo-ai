import 'package:flutter_test/flutter_test.dart';

/// Pins the bug-class behind ChatProvider.deleteConversation:
///
/// `ChatService.listConversations()` returns a Freezed-decoded list whose
/// `.items` field is an unmodifiable List. Calling `.removeWhere(...)` on it
/// throws `UnsupportedError: Cannot remove from an unmodifiable list`.
/// The provider must build a new list via `.where(...).toList()` instead.
void main() {
  group('unmodifiable conversation-list mutation', () {
    test('removeWhere on an unmodifiable list throws', () {
      final source = List<int>.unmodifiable([1, 2, 3]);
      expect(
        () => source.removeWhere((x) => x == 2),
        throwsUnsupportedError,
      );
    });

    test('where(...).toList() works on the same unmodifiable list', () {
      final source = List<int>.unmodifiable([1, 2, 3]);
      final result = source.where((x) => x != 2).toList();
      expect(result, [1, 3]);
      // Result is a fresh growable list — safe for further mutation.
      expect(() => result.add(4), returnsNormally);
    });
  });
}
