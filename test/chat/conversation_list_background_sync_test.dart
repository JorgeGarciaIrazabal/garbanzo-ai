import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/providers/conversation_list_controller.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';

/// A [ChatService] fake whose [listConversations] throws a transient
/// [DioException] (connection closed before full header) — reproduces
/// user-report #248cf6f6: the background sync timer's GET failed and the
/// error bubbled up to the error reporter.
class _TransientErrorChatService extends ChatService {
  _TransientErrorChatService() : super.forTesting();

  int listCalls = 0;

  @override
  Future<ConversationList> listConversations({
    int page = 1,
    int pageSize = 20,
    bool silent = false,
    String kind = 'all',
  }) async {
    listCalls++;
    throw DioException(
      requestOptions: RequestOptions(path: '/api/v1/chat/conversations'),
      type: DioExceptionType.connectionError,
      message: 'Connection closed before full header was received',
    );
  }
}

void main() {
  group('ConversationListController background sync', () {
    test(
        'background load (showLoading: false) swallows transient DioException '
        'without surfacing an error (user-report #248cf6f6)',
        () async {
      final service = _TransientErrorChatService();
      final controller = ConversationListController(chatService: service);

      // Foreground load surfaces the error to the user.
      await controller.load(showLoading: true);
      expect(controller.error, isNotNull);
      expect(controller.error, contains('Failed to load conversations'));
      controller.clearError();

      // Background sync (the periodic timer path) must NOT surface an error —
      // the next tick will retry, transient network blips aren't user-facing.
      await controller.load(showLoading: false);
      expect(controller.error, isNull,
          reason: 'Background sync should not surface transient errors');
      expect(service.listCalls, 2);
    });

    test('foreground load still surfaces DioException with a clean message',
        () async {
      final service = _TransientErrorChatService();
      final controller = ConversationListController(chatService: service);

      await controller.load(showLoading: true);
      expect(controller.error, isNotNull);
      // The DioException's message is surfaced, not the opaque
      // "DioException [bad response]: null" that triggered the original report.
      expect(controller.error, contains('Connection closed before full header'));
      controller.dispose();
    });
  });
}
