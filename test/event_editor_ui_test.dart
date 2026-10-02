import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/editors.dart';
import 'package:flowday/ui/theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'event editor at phone width saves and preserves duration $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = FlowStore(FlowData());
        addTearDown(store.dispose);
        final start = DateTime(2026, 10, 1, 9);
        await tester.pumpWidget(
          MaterialApp(
            theme: flowTheme(brightness: brightness),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openEditor(
                    context,
                    EventEditor(store: store, initialDate: start),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('event-time-开始时间')), findsOneWidget);
        expect(find.byKey(const ValueKey('event-time-结束时间')), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('保存')).dx,
          greaterThan(tester.getTopLeft(find.text('取消')).dx),
        );
        await tester.enterText(find.byType(TextFormField).first, '组会');
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect(store.events.single.title, '组会');
        expect(store.events.single.start, start);
        expect(
          store.events.single.end.difference(start),
          const Duration(hours: 1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('event cancellation leaves workspace unchanged', (tester) async {
    final store = FlowStore(FlowData());
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: flowTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openEditor(context, EventEditor(store: store)),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '不保存');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.events, isEmpty);
  });
}
