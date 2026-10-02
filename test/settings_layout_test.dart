import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/settings_page.dart';
import 'package:flowday/ui/theme.dart';

void main() {
  for (final width in [390.0, 1100.0]) {
    testWidgets('all settings categories render at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dir = Directory.systemTemp.createTempSync(
        'flowday-settings-test-',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final section in settingsSections) {
        await tester.pumpWidget(
          MaterialApp(
            theme: flowTheme(),
            home: Scaffold(
              body: SettingsPage(
                key: ValueKey(section.$1),
                store: FlowStore(FlowData()),
                directory: dir,
                initialSection: section.$1,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: section.$1);
      }
    });
  }
}

