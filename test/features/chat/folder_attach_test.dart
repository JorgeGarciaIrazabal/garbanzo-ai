import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/attach_menu_button.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/folder_chip.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('FolderChip', () {
    testWidgets('shows the folder basename and calls onRemove', (tester) async {
      var removed = false;
      await tester.pumpWidget(
        _wrap(
          FolderChip(
            folderPath: '/home/me/projects/garbanzo',
            onRemove: () => removed = true,
          ),
        ),
      );

      // The scope label carries the last path segment, not the full path.
      expect(find.textContaining('garbanzo'), findsOneWidget);
      expect(find.textContaining('/home/me'), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      expect(removed, isTrue);
    });
  });

  group('AttachMenuButton folder option', () {
    testWidgets('shows Folder option on desktop when onPickFolder is set', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var picked = false;
      await tester.pumpWidget(
        _wrap(
          AttachMenuButton(
            enabled: true,
            existingNames: () => <String>{},
            onAdded: (_) {},
            onPickFolder: () async => picked = true,
          ),
        ),
      );

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      final folderItem = find.text('Folder');
      expect(folderItem, findsOneWidget);
      await tester.tap(folderItem);
      await tester.pumpAndSettle();
      expect(picked, isTrue);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('hides Folder option when onPickFolder is null', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        _wrap(
          AttachMenuButton(
            enabled: true,
            existingNames: () => <String>{},
            onAdded: (List<ChatAttachment> _) {},
          ),
        ),
      );

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('Folder'), findsNothing);

      debugDefaultTargetPlatformOverride = null;
    });
  });
}
