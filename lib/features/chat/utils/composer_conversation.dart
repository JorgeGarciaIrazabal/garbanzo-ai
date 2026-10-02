import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/topics/providers/topic_discovery_provider.dart';

/// The topic landing edits settings and attachments for the next thread.
/// The legacy primary remains loaded only as a history and API source.
Conversation? composerConversation(BuildContext context, {bool listen = true}) {
  final conversation = Provider.of<ChatProvider>(
    context,
    listen: listen,
  ).currentConversation;
  if (conversation?.isPrimary == true &&
      Provider.of<TopicDiscoveryProvider?>(
            context,
            listen: listen,
          )?.showLanding ==
          true) {
    return null;
  }
  return conversation;
}
