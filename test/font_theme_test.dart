import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/app.dart';
import 'package:flowday/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HarmonyOS font files are bundled with real weights', () async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    final family = manifest.cast<Map<String, dynamic>>().singleWhere(
      (e) => e['family'] == appFontFamily,
    );
    final fonts = family['fonts'] as List;
    expect(fonts.map((f) => f['weight']), [400, 500, 700]);
    for (final font in fonts) {
      expect(
        (await rootBundle.load(font['asset'] as String)).lengthInBytes,
        greaterThan(1000000),
      );
    }
  });

  test('both themes use HarmonyOS for text, menus, inputs and dialogs', () {
    for (final brightness in Brightness.values) {
      final theme = flowTheme(brightness: brightness);
      for (final style in [
        theme.textTheme.bodyMedium,
        theme.textTheme.titleLarge,
        theme.textTheme.labelLarge,
        theme.textTheme.displayLarge,
        theme.primaryTextTheme.bodyMedium,
        theme.inputDecorationTheme.hintStyle,
        theme.menuButtonTheme.style!.textStyle!.resolve({}),
        theme.popupMenuTheme.textStyle,
        theme.dropdownMenuTheme.textStyle,
        theme.dialogTheme.titleTextStyle,
        theme.dialogTheme.contentTextStyle,
        theme.tooltipTheme.textStyle,
      ]) {
        expect(style!.fontFamily, appFontFamily);
      }
    }
  });

  testWidgets('legacy font settings cannot override the global font', (
    tester,
  ) async {
    for (final legacy in ['Microsoft YaHei', 'system']) {
      await tester.pumpWidget(
        FlowDayApp(
          store: FlowStore(FlowData(preferences: {'fontFamily': legacy})),
        ),
      );
      await tester.pumpAndSettle();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme!.textTheme.bodyMedium!.fontFamily, appFontFamily);
      expect(app.darkTheme!.textTheme.bodyMedium!.fontFamily, appFontFamily);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
