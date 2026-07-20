/// Facade for the client-side folder writer (idea 18 write-back).
///
/// Same conditional-import trick as [folder_reader.dart]: the `dart:io`
/// implementation on desktop, a throwing stub on web, so providers that run on
/// every platform can import this safely.
library;

export 'package:garbanzo_ai/features/chat/services/folder_read_error.dart';
export 'package:garbanzo_ai/features/chat/services/folder_writer_stub.dart'
    if (dart.library.io) 'package:garbanzo_ai/features/chat/services/folder_writer_io.dart';
