import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/usage/models/usage_summary.dart';
import 'package:garbanzo_ai/features/usage/providers/usage_provider.dart';
import 'package:garbanzo_ai/features/usage/services/usage_service.dart';
import 'package:mocktail/mocktail.dart';

class MockUsageService extends Mock implements UsageService {}

UsageSummary _summary(int days) => UsageSummary(
      days: days,
      totalTokensPrompt: 100,
      totalTokensGenerated: 50,
      totalMessages: 4,
      byModel: const [],
      byConversation: const [],
      byDay: const [],
    );

void main() {
  late MockUsageService service;

  setUp(() {
    service = MockUsageService();
  });

  UsageProvider provider() => UsageProvider(service: service);

  test('load stores the summary and clears loading', () async {
    when(() => service.fetchSummary(days: 30))
        .thenAnswer((_) async => _summary(30));

    final p = provider();
    await p.load();

    expect(p.summary?.totalMessages, 4);
    expect(p.days, 30);
    expect(p.isLoading, isFalse);
    expect(p.error, isNull);
  });

  test('load(days:) updates the window and passes it to the service', () async {
    when(() => service.fetchSummary(days: 7))
        .thenAnswer((_) async => _summary(7));

    final p = provider();
    await p.load(days: 7);

    expect(p.days, 7);
    verify(() => service.fetchSummary(days: 7)).called(1);
  });

  test('a fetch failure surfaces a user-facing error', () async {
    when(() => service.fetchSummary(days: any(named: 'days')))
        .thenThrow(Exception('API Error (500): boom'));

    final p = provider();
    await p.load();

    expect(p.summary, isNull);
    expect(p.error, isNotNull);
    expect(p.isLoading, isFalse);
  });
}
