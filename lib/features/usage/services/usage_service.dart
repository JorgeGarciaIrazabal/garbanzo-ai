import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/api_error.dart';
import 'package:garbanzo_ai/features/usage/models/usage_summary.dart';

class UsageService {
  UsageService({ApiClient? api}) : _client = api ?? ApiClient.instance;
  static final UsageService instance = UsageService();

  final ApiClient _client;

  Future<UsageSummary> fetchSummary({int days = 30}) async {
    final res = await _client.get(
      '/api/v1/usage/summary',
      queryParameters: {'days': days},
    );
    expectStatus(res, const {200}, operation: 'Failed to load usage');
    final data = res.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid usage response');
    }
    return UsageSummary.fromJson(data);
  }
}
