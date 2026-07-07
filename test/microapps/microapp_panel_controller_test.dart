import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:garbanzo_ai/features/microapps/providers/microapp_panel_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MicroappPanelController', () {
    test('opens from a micro_app tool result with a data file (house)', () {
      final c = MicroappPanelController();
      int notes = 0;
      c.addListener(() => notes++);

      final handled = c.openFromToolResult('micro_app', {
        'app': 'house-designer',
        'app_path': 'house-designer/',
        'file': 'houses/tiny-cabin.house.json',
        'file_name': 'tiny-cabin.house.json',
        'dev_port': 8123,
        'summary': 'Added a window.',
      });

      expect(handled, isTrue);
      expect(c.isOpen, isTrue);
      expect(c.file, 'houses/tiny-cabin.house.json');
      expect(c.fileName, 'tiny-cabin.house.json');
      expect(c.devPort, 8123);
      expect(notes, 1);

      final url = c.url!;
      expect(url, contains(':8123/micro-apps/house-designer/'));
      expect(url, contains('embed=1'));
      expect(url, contains('project=/micro-apps/houses/tiny-cabin.house.json'));
      expect(url, contains('save=1'));
    });

    test('opens a source-only app (no data file) without a project param', () {
      final c = MicroappPanelController();
      final handled = c.openFromToolResult('micro_app', {
        'app': 'madrid-fire-planner',
        'app_path': 'madrid-fire-planner/',
        'file': null,
        'dev_port': 8200,
      });
      expect(handled, isTrue);
      final url = c.url!;
      expect(url, contains(':8200/micro-apps/madrid-fire-planner/?embed=1'));
      expect(url, isNot(contains('project=')));
    });

    test('ignores non-microapp tool results', () {
      final c = MicroappPanelController();
      final handled = c.openFromToolResult('some_mcp_tool', {'foo': 'bar'});
      expect(handled, isFalse);
      expect(c.isOpen, isFalse);
    });

    test('ignores malformed results (missing dev_port)', () {
      final c = MicroappPanelController();
      final handled = c.openFromToolResult('micro_app', {'app': 'house-designer'});
      expect(handled, isFalse);
      expect(c.isOpen, isFalse);
    });

    test('reload bumps the counter; close hides the panel', () {
      final c = MicroappPanelController();
      c.openFromToolResult('micro_app', {
        'app': 'house-designer',
        'app_path': 'house-designer/',
        'dev_port': 8300,
      });
      final before = c.reloadCounter;
      c.reload();
      expect(c.reloadCounter, before + 1);
      c.close();
      expect(c.isOpen, isFalse);
    });
  });
}
