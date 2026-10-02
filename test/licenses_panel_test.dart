import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/ui/licenses_panel.dart';
import 'package:flowday/ui/theme.dart';

void main() {
  for (final width in [390.0, 1100.0]) {
    testWidgets('license list and full text at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: flowTheme(brightness: Brightness.dark),
          home: Scaffold(
            body: LicensesPanel(
              entries: Stream.fromIterable([
                LicenseEntryWithLineBreaks([
                  'alpha',
                  'beta',
                ], 'Copyright 2026\n\nPermission is granted.'),
                LicenseEntryWithLineBreaks(['beta'], 'Second license text.'),
              ]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('license-beta')));
      await tester.pumpAndSettle();
      expect(
        find.text('Copyright 2026\n\nPermission is granted.'),
        findsOneWidget,
      );
      expect(find.text('Second license text.'), findsOneWidget);
      if (width < 650) {
        await tester.tap(find.byKey(const Key('license-back')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('license-alpha')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
