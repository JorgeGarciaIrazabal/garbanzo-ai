import 'package:dio/dio.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/reports/models/report.dart';

/// HTTP client for `/api/v1/reports` and the admin triage endpoints.
class ReportsService {
  ReportsService._();
  static final ReportsService instance = ReportsService._();

  final ApiClient _api = ApiClient.instance;

  /// Submit a bug report or feature request.
  Future<Report> create({
    required String type,
    required String title,
    required String description,
    Map<String, dynamic>? metadata,
    String? conversationId,
    String? severity,
    String? source,
  }) async {
    final response = await _api.post(
      '/api/v1/reports',
      data: {
        'type': type,
        'title': title,
        'description': description,
        'metadata': ?metadata,
        'conversation_id': ?conversationId,
        'severity': ?severity,
        'source': ?source,
      },
    );
    if (response.statusCode == 201) {
      return Report.fromJson(response.data as Map<String, dynamic>);
    }
    throw _error(response);
  }

  /// The current user's own reports, newest first.
  Future<List<Report>> listMine() async {
    final response = await _api.get('/api/v1/reports/mine');
    if (response.statusCode == 200) {
      final data = response.data as List;
      return data
          .map((e) => Report.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw _error(response);
  }

  /// All reports across users (admin only), optionally filtered by status.
  Future<List<Report>> adminList({String? status}) async {
    final response = await _api.get(
      '/api/v1/admin/reports',
      queryParameters: {'status': ?status},
    );
    if (response.statusCode == 200) {
      final data = response.data as List;
      return data
          .map((e) => Report.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw _error(response);
  }

  /// Move a report through its triage flow (admin only).
  Future<Report> adminUpdateStatus(String id, String status) async {
    final response = await _api.patch(
      '/api/v1/admin/reports/$id',
      data: {'status': status},
    );
    if (response.statusCode == 200) {
      return Report.fromJson(response.data as Map<String, dynamic>);
    }
    throw _error(response);
  }

  Exception _error(Response<dynamic> response) {
    final detail = switch (response.data) {
      {'detail': final String d} => d,
      _ => 'HTTP ${response.statusCode}',
    };
    return Exception(detail);
  }
}
