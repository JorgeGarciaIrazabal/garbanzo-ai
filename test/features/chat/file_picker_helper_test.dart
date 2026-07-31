import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/file_picker_helper.dart';
import 'package:image/image.dart' as image_lib;

void main() {
  test('validation rejects duplicate names within one shared batch', () async {
    final result = await FilePickerHelper.validate(
      files: [
        (name: 'photo.png', bytes: Uint8List.fromList([1])),
        (name: 'photo.png', bytes: Uint8List.fromList([2])),
      ],
      existingNames: {},
    );

    expect(result.added, hasLength(1));
    expect(result.validationErrors, ['Duplicate file: photo.png']);
  });

  test('oversized BMP is downscaled below 3 MiB without changing format', () async {
    final source = image_lib.Image(width: 1200, height: 1200);
    final bytes = image_lib.encodeBmp(source);
    expect(bytes.length, greaterThan(3 * 1024 * 1024));

    final result = await FilePickerHelper.validate(
      files: [(name: 'scan.bmp', bytes: bytes)],
      existingNames: {},
    );

    expect(result.rejected, isEmpty);
    expect(result.added, hasLength(1));
    final fitted = result.added.single;
    expect(fitted.name, 'scan.bmp');
    expect(fitted.mimeType, 'image/bmp');
    expect(fitted.bytes.length, lessThanOrEqualTo(3 * 1024 * 1024));
    final decoded = image_lib.decodeBmp(fitted.bytes)!;
    expect(decoded.width, lessThan(1200));
    expect(decoded.width, decoded.height);
  });

  test('oversized WebP falls back to PNG', () async {
    final tinyWebp = base64Decode(
      'UklGRnwEAABXRUJQVlA4THAEAAAvL8ALEE2YadtGyfqFP+RxiOh/HMAMUEutegNowahtJEmGUM+5t/jjWzBsI0ly0q8xMTFlAOQflhYW20iSGrWFBosi/8B4EcKF0P/4AZA+kO0SAAgc+o/VrdEdoHt6Sv918oZV3/Sk3kmGDAAY/yCRZGvbIUnvFxHVtm3btjeQq8w9tI1R2bZdqfgGgRN/tqZvKU654EiSJEmJzJqLGz6EoSPPK+cT+x4kbKU5tjvl1Lbtastc5/6EOufQowcB9Ij4BFBTYw5EwPjegVvbtmplnnv/x90to02HXDuy6PdA7BI5970zAUDwL5nYvtTOVRhLbGo4cCvJ9XsCDWAcaMn1lrNhgJ5tPFu2uaaF0pAi2ni/zJkwg7yaWnE5tU8jYEjT9nmNVlz300HeTQUAPVCAL0UB1sEu0XgMdj3HDn/x9xsoM57E9juYGu0hXgCgP6WBKoYE5kHceB0a7wdAJrZbeDq/fwbtdi0ihnQzA4t7oWmXGVDYobKL7PwVHjKFUEtAfoIrGCyZyBNFhPift+D+wQ5ARQQceMSLKHo83oUCuDtnSyVTfD8PYyudncFx4IiJ4YGKCJidZLXHKmerKFDEa3ctY5MMiTAJQkIx5k0rQwU04MSi1V/HiNjqQaoHSYrHxrDZxwrFTKfH51qqkFTIaZCUAEKKcuGR5zpeigdkAxhRVgYmacMGjhNOcSCpHiS3Zpwjazsrk73OqeEwQhAHtvg4YfaxnIoj6LXJdh5cbTiBlLAZjNhZ+xgnuOysWA4MfTfXenAdrw529gFCqtJBjOyqPJju4KBg4FI8hawWsXoYq0x9jpJHIlupIUBKYDargQdZOMmi6NisWIKkKxprFHr0aghMuooqUawnh8MqpUvZ5HHY2IQcUWar2xokR6cB4AOttcOwFGagqaes0mNcwojXwK3GViHGrcMyIsAaCLU+6sMwURZJrvcQk4ZGjvJOf79kFUa+JdmSBUKLpaKb1Hi0aa2Zs/crFf/QO6Y0Z1WSsXa3ux/HHqPs9RKdK1Qh2UE+57KRXFqy52v1jgiLBGuh0aNSa7hdDuy5d2eTR8fMgSNwYKZQyTidkE0i6HbaxS4PhBSUkvF77bLqMysqJNn1WK+VXpaK7Ucu3u8KxmGxdnce3MEcGZEJjEPHdaBS0xJBSnybxr7OSo92jS4ua1i2APj2JiShsURCIakatMg6wijHoMopFmRWIwcIyEo3VAH45kROYaBCqv0XiW9afOTYvESnNB8o+PWaHx4bjBjUQIHKzPJMKv/V/f0RHduhbIfBymrSKgn8V9aSeSLIIOdUpBV54qL4JbZfFWhtPNpZoad3cAugP6WBKoYErNwbMOZ6ugx9Ejc8TK4/8i1fJta1PZNYpvlYIS3X7dwfwK0AzWcW3GIddnMYz+FDqAIJhJGpeWS7VHXXMjoE/hgcD+GrtVytbtdUrg6AWRtG68n3MNc98AhuCfRBBF874BmoNA104Os/+NZmGHLm0e1PP/gjjK2//UugAfIcaIDfFQ==',
    );
    final result = await FilePickerHelper.validate(
      files: [(name: 'sticker.webp', bytes: tinyWebp)],
      existingNames: {},
      imageLimitBytes: 1024,
    );

    expect(result.rejected, isEmpty);
    final fitted = result.added.single;
    expect(fitted.name, 'sticker.png');
    expect(fitted.mimeType, 'image/png');
    expect(image_lib.decodePng(fitted.bytes), isNotNull);
  });
}
