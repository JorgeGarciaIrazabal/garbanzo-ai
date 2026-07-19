/// Facade for the client-side folder reader (idea 17).
///
/// Picks the `dart:io` implementation on desktop/mobile and a no-op stub on
/// web, so `ChatProvider` (which runs on every platform) can import this
/// without pulling `dart:io` into the web build.
library;

export 'package:garbanzo_ai/features/chat/services/folder_read_error.dart';
export 'package:garbanzo_ai/features/chat/services/folder_reader_stub.dart'
    if (dart.library.io) 'package:garbanzo_ai/features/chat/services/folder_reader_io.dart';
