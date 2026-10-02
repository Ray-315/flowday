import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/app.dart';
import 'package:flowday/ui/settings_page.dart';

void main() {
  testWidgets('render settings previews', (tester) async {
    LicenseRegistry.addLicense(
      () => Stream.value(
        LicenseEntryWithLineBreaks([
          'flutter',
        ], File('.tools/flutter/LICENSE').readAsStringSync()),
      ),
    );
    final font = FontLoader('HarmonyOS Sans SC')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              'assets/fonts/HarmonyOS_Sans_SC_Regular.ttf',
            ).readAsBytesSync(),
          ),
        ),
      );
    await font.load();
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
    final dir = Directory.systemTemp.createTempSync(
      'flowday-settings-preview-',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    tester.view.physicalSize = const Size(1536, 1024);
    tester.view.devicePixelRatio = 1;
    final key = GlobalKey();
    final store = FlowStore(FlowData(preferences: {'displayName': '使用者'}));
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: FlowDayApp(store: store, directory: dir),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    Future<void> save(String name) async {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('docs/screenshots/settings').createSync(recursive: true);
        File(
          'docs/screenshots/settings/$name.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final section in settingsSections) {
      await tester.tap(find.byKey(Key('settings-${section.$1}')));
      await tester.pumpAndSettle();
      await save(section.$1);
    }
    await tester.tap(find.byKey(const Key('settings-appearance')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.pumpAndSettle();
    await save('appearance-dark');
    for (final mode in ['dark', 'light']) {
      store.data.preferences['themeMode'] = mode;
      store.changed();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-schedule')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('calendarView-月')));
      await tester.pumpAndSettle();
      await save('select-$mode');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    store.data.preferences['themeMode'] = 'light';
    store.changed();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-menu')));
    await tester.pumpAndSettle();
    await save('profile');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-about')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开源声明'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    await save('licenses-light');
    store.data.preferences['themeMode'] = 'dark';
    store.changed();
    await tester.pumpAndSettle();
    await save('licenses-dark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
