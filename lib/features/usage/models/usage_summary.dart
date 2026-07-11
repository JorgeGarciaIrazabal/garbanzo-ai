class UsageByModel {
  final String model;
  final int tokensPrompt;
  final int tokensGenerated;
  final int messageCount;

  const UsageByModel({
    required this.model,
    required this.tokensPrompt,
    required this.tokensGenerated,
    required this.messageCount,
  });

  int get totalTokens => tokensPrompt + tokensGenerated;

  factory UsageByModel.fromJson(Map<String, dynamic> json) => UsageByModel(
    model: json['model'] as String? ?? 'unknown',
    tokensPrompt: (json['tokens_prompt'] as num?)?.toInt() ?? 0,
    tokensGenerated: (json['tokens_generated'] as num?)?.toInt() ?? 0,
    messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
  );
}

class UsageByConversation {
  final String conversationId;
  final String? title;
  final int tokensPrompt;
  final int tokensGenerated;
  final int messageCount;

  const UsageByConversation({
    required this.conversationId,
    this.title,
    required this.tokensPrompt,
    required this.tokensGenerated,
    required this.messageCount,
  });

  int get totalTokens => tokensPrompt + tokensGenerated;

  factory UsageByConversation.fromJson(Map<String, dynamic> json) =>
      UsageByConversation(
        conversationId: json['conversation_id'] as String? ?? '',
        title: json['title'] as String?,
        tokensPrompt: (json['tokens_prompt'] as num?)?.toInt() ?? 0,
        tokensGenerated: (json['tokens_generated'] as num?)?.toInt() ?? 0,
        messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
      );
}

class UsageByDay {
  final DateTime date;
  final int tokensPrompt;
  final int tokensGenerated;

  const UsageByDay({
    required this.date,
    required this.tokensPrompt,
    required this.tokensGenerated,
  });

  int get totalTokens => tokensPrompt + tokensGenerated;

  factory UsageByDay.fromJson(Map<String, dynamic> json) {
    final raw = json['date'] as String?;
    final parsed = (raw != null) ? DateTime.tryParse(raw) : null;
    return UsageByDay(
      date: parsed ?? DateTime.now(),
      tokensPrompt: (json['tokens_prompt'] as num?)?.toInt() ?? 0,
      tokensGenerated: (json['tokens_generated'] as num?)?.toInt() ?? 0,
    );
  }
}

class UsageSummary {
  final int days;
  final int totalTokensPrompt;
  final int totalTokensGenerated;
  final int totalMessages;
  final List<UsageByModel> byModel;
  final List<UsageByConversation> byConversation;
  final List<UsageByDay> byDay;

  const UsageSummary({
    required this.days,
    required this.totalTokensPrompt,
    required this.totalTokensGenerated,
    required this.totalMessages,
    required this.byModel,
    required this.byConversation,
    required this.byDay,
  });

  int get totalTokens => totalTokensPrompt + totalTokensGenerated;

  factory UsageSummary.fromJson(Map<String, dynamic> json) => UsageSummary(
    days: (json['days'] as num?)?.toInt() ?? 30,
    totalTokensPrompt: (json['total_tokens_prompt'] as num?)?.toInt() ?? 0,
    totalTokensGenerated:
        (json['total_tokens_generated'] as num?)?.toInt() ?? 0,
    totalMessages: (json['total_messages'] as num?)?.toInt() ?? 0,
    byModel: (json['by_model'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(UsageByModel.fromJson)
        .toList(),
    byConversation: (json['by_conversation'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(UsageByConversation.fromJson)
        .toList(),
    byDay: (json['by_day'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(UsageByDay.fromJson)
        .toList(),
  );
}
