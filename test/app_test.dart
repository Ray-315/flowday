import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/app.dart';

void main() {
  testWidgets('desktop navigation and task creation', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = FlowStore(FlowData());
    await tester.pumpWidget(FlowDayApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-todo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建任务').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('task-title')), '整理实验结果');
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    expect(store.tasks.single.title, '整理实验结果');
    expect(find.text('整理实验结果'), findsNWidgets(2));
  });

  testWidgets('mobile navigation fits narrow viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(FlowDayApp(store: FlowStore(FlowData())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-navigation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-calendar')));
    await tester.pumpAndSettle();
    expect(find.text('日历'), findsWidgets);
  });
}
