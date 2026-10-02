import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/today_page.dart';
import 'package:flowday/ui/theme.dart';

void main() {
  testWidgets('Today contains timeline, Todo, mini calendar and overview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = FlowStore(FlowData());
    await tester.pumpWidget(
      MaterialApp(
        theme: flowTheme(),
        home: Scaffold(
          body: TodayPage(store: store, navigate: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('today-timeline')), findsOneWidget);
    expect(find.byKey(const Key('today-mini-calendar')), findsOneWidget);
    expect(find.text('本日概览'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('today-capture')), '明天整理实验结果');
    await tester.tap(find.byKey(const Key('today-capture-submit')));
    await tester.pumpAndSettle();
    expect(store.data.captures, isEmpty);
    expect(find.text('明天整理实验结果'), findsOneWidget);
  });
}
