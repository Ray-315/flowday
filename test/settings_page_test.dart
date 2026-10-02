import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/app.dart';

void main() {
  testWidgets(
    'avatar hover opens profile and sidebar preferences preserve navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = FlowStore(
        FlowData(
          preferences: {'sidebarPosition': 'right', 'sidebarCollapsed': true},
        ),
      );
      await tester.pumpWidget(FlowDayApp(store: store));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byKey(const Key('nav-settings'))).dx,
        greaterThan(1300),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('profile-menu'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('个人资料'), findsOneWidget);
      await tester.tap(find.text('个人资料'));
      await tester.pumpAndSettle();
      expect(find.text('账号信息'), findsOneWidget);
      await mouse.removePointer();
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
  testWidgets('settings categories and appearance change app theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = FlowStore(FlowData());
    await tester.pumpWidget(FlowDayApp(store: store));
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-navigation')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-appearance')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-dark')));
    await tester.pumpAndSettle();
    expect(store.data.preferences['themeMode'], 'dark');
    expect(
      Theme.of(tester.element(find.byKey(const Key('theme-dark')))).brightness,
      Brightness.dark,
    );
  });
}
