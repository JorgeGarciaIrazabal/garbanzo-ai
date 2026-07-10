import 'package:dio/dio.dart';
import 'package:dio_compatibility_layer/dio_compatibility_layer.dart';
import 'package:fetch_client/fetch_client.dart';

/// Web needs a Fetch-API-backed adapter: dio's default browser adapter is
/// XHR-based and waits for `onLoad` — the FULL response body — before
/// delivering anything, so `ResponseType.stream` (our SSE chat stream and
/// streaming TTS) arrives as one buffer at the very end instead of
/// incrementally. The Fetch API exposes the response as a ReadableStream,
/// which `fetch_client` surfaces chunk by chunk.
HttpClientAdapter? createPlatformAdapter() =>
    ConversionLayerAdapter(FetchClient(mode: RequestMode.cors));
