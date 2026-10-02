import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/app.dart';

FlowStore fixture() {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  return FlowStore(
    FlowData(
      projects: [Project(id: 'p', title: 'LLM 水印论文', description: '实验与论文写作')],
      tasks: [
        Task(
          id: 't',
          title: '整理实验结果',
          projectId: 'p',
          deadline: day.add(const Duration(hours: 18)),
        ),
      ],
      events: [
        CalendarEvent(
          id: 'e',
          title: '实验：鲁棒性测试',
          projectId: 'p',
          taskId: 't',
          start: day.add(const Duration(hours: 10)),
          end: day.add(const Duration(hours: 12)),
        ),
      ],
      nodes: [
        FlowNode(
          id: 'n',
          projectId: 'p',
          title: '文献阅读',
          taskId: 't',
          x: 60,
          y: 80,
        ),
      ],
    ),
  );
}

void main() {
  test('navigation is Chinese and excludes Inbox', () {
    expect(destinations.map((d) => d.$2), [
      '今天',
      '日历',
      '项目',
      '任务',
      '工作流',
      '统计分析',
      '通知',
      '回收站',
    ]);
    expect(destinations.any((d) => d.$1 == 'inbox'), isFalse);
  });
  for (final width in [390.0, 1440.0]) {
    testWidgets('all pages with data at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(FlowDayApp(store: fixture()));
      await tester.pumpAndSettle();
      for (final id in [
        'todo',
        'projects',
        'calendar',
        'workflow',
        'reports',
        'notices',
        'trash',
        'settings',
        'today',
      ]) {
        if (width < 850) {
          await tester.tap(find.byKey(const Key('open-navigation')));
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(find.byKey(Key('nav-$id')));
        await tester.tap(find.byKey(Key('nav-$id')));
        await tester.pumpAndSettle();
      }
    });
    testWidgets('calendar views with data at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(FlowDayApp(store: fixture()));
      await tester.pumpAndSettle();
      if (width < 850) {
        await tester.tap(find.byKey(const Key('open-navigation')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('nav-calendar')));
      await tester.pumpAndSettle();
      for (final view in ['周', '日', '列表', '时间轴', '月']) {
        await tester.tap(find.text(view).first);
        await tester.pumpAndSettle();
      }
    });
  }
}
