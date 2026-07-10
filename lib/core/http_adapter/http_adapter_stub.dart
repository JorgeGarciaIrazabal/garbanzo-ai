import 'package:dio/dio.dart';

/// Non-web platforms keep dio's default `dart:io` adapter, which already
/// streams responses incrementally.
HttpClientAdapter? createPlatformAdapter() => null;
