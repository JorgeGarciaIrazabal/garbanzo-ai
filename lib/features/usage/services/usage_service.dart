import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/usage/models/usage_summary.dart';

class UsageService {
  UsageService._();
  static final UsageService instance = UsageService._();

  final _client = ApiClient.instance;

  Future<UsageSummary> fetchSummary({int days = 30}) async {
    final res = await _client.get(
      '/api/v1/usage/summary',
      queryParameters: {'days': days},
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to load usage: HTTP ${res.statusCode}');
    }
    final data = res.data;
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid usage response');
    }
    return UsageSummary.fromJson(data);
  }
}
