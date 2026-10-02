import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/ui/task_pages.dart';
import 'package:flowday/ui/calendar_page.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';

FlowStore fixture() {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  return FlowStore(
    FlowData(
      projects: [Project(id: 'p', title: 'LLM 水印论文')],
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
          start: day.add(const Duration(hours: 10)),
          end: day.add(const Duration(hours: 12)),
        ),
      ],
    ),
  );
}

void main() {
  testWidgets('pending task drag creates a linked time block', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = fixture();
    store.data.preferences['calendarView'] = '日';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CalendarPage(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    final task = find.text('整理实验结果');
    final target = find.byKey(const Key('calendar-slot-0-9'));
    await tester.dragFrom(
      tester.getCenter(task),
      tester.getCenter(target) - tester.getCenter(task),
    );
    await tester.pumpAndSettle();
    expect(store.events.where((e) => e.taskId == 't'), hasLength(1));
    expect(store.events.firstWhere((e) => e.taskId == 't').start.hour, 9);
  });
  testWidgets('desktop detail subtask completion writes to store', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = fixture();
    store.addTask(
      Task(id: 'sub', title: '核对数据', parentId: 't', projectId: 'p'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TodoPage(store: store)),
      ),
    );
    await tester.tap(find.text('核对数据'));
    await tester.pumpAndSettle();
    expect(
      store.tasks.firstWhere((t) => t.id == 'sub').status,
      TaskStatus.done,
    );
    expect(find.text('子任务  1/1'), findsOneWidget);
  });
  for (final width in [390.0, 1440.0]) {
    testWidgets('calendar all views and project cards at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = fixture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CalendarPage(store: store)),
        ),
      );
      for (final view in ['日', '周', '列表', '时间轴', '月']) {
        await tester.tap(find.text(view).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProjectsPage(store: store, openWorkflow: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TodoPage(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('desktop todo has selected detail and table columns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TodoPage(store: fixture())),
      ),
    );
    expect(find.byKey(const Key('todo-detail')), findsOneWidget);
    expect(find.text('预计耗时'), findsOneWidget);
    expect(find.text('添加时间块'), findsOneWidget);
  });
  testWidgets('desktop calendar provides project visibility', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CalendarPage(store: fixture())),
      ),
    );
    expect(find.text('我的日历'), findsOneWidget);
    await tester.tap(find.byKey(const Key('calendar-project-p')));
    await tester.pump();
    expect(find.textContaining('实验：鲁棒性测试'), findsNothing);
  });
}
