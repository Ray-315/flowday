import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/editors.dart';
import 'package:flowday/ui/theme.dart';

void main() {
  testWidgets('render event editor', (tester) async {
    final fonts = FontLoader(appFontFamily)
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              'assets/fonts/HarmonyOS_Sans_SC_Regular.ttf',
            ).readAsBytesSync(),
          ),
        ),
      );
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              '.tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
            ).readAsBytesSync(),
          ),
        ),
      );
    await icons.load();
    for (final brightness in Brightness.values) {
      tester.view.physicalSize = const Size(450, 900);
      tester.view.devicePixelRatio = 1;
      final store = FlowStore(
        FlowData(
          projects: [Project(id: 'p', title: '科研')],
        ),
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: flowTheme(brightness: brightness),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: EventEditor(
                store: store,
                initialDate: DateTime(2026, 10, 1, 14),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final rendered = await boundary.toImage();
        final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
        File(
          'docs/screenshots/event-editor-${brightness.name}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        rendered.dispose();
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
