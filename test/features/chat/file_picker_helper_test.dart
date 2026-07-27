import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/file_picker_helper.dart';

void main() {
  test('validation rejects duplicate names within one shared batch', () {
    final result = FilePickerHelper.validate(
      files: [
        (name: 'photo.png', bytes: Uint8List.fromList([1])),
        (name: 'photo.png', bytes: Uint8List.fromList([2])),
      ],
      existingNames: {},
    );

    expect(result.added, hasLength(1));
    expect(result.validationErrors, ['Duplicate file: photo.png']);
  });
}
