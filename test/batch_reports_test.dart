import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/task_pages.dart';
import 'package:flowday/ui/overview_pages.dart';
import 'package:flowday/ui/theme.dart';

Future<void> showPage(WidgetTester tester, Widget page) => tester.pumpWidget(
  MaterialApp(
    theme: flowTheme(),
    home: Scaffold(body: page),
  ),
);

void main() {
  testWidgets(
    'batch archive can be previewed and reversed without deleting tasks',
    (tester) async {
      final store = FlowStore(
        FlowData(
          tasks: [
            Task(id: 'a', title: '任务甲'),
            Task(id: 'b', title: '任务乙'),
          ],
        ),
      );
      addTearDown(store.dispose);
      await showPage(tester, TodoPage(store: store));
      await tester.tap(find.text('批量选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('todo-select-all')));
      await tester.pump();
      await tester.tap(find.text('归档'));
      await tester.pumpAndSettle();
      expect(find.text('归档 · 2 个任务'), findsOneWidget);
      expect(store.tasks.length, 2);
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(store.tasks, isEmpty);
      expect(store.data.tasks.length, 2);
      await tester.tap(find.text('已归档'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('todo-select-all')));
      await tester.pump();
      await tester.tap(find.text('取消归档'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(store.tasks.length, 2);
    },
  );

  testWidgets('batch move and tags apply only after per-task confirmation', (
    tester,
  ) async {
    final store = FlowStore(
      FlowData(
        projects: [Project(id: 'p', title: '目标项目')],
        tasks: [
          Task(id: 'a', title: '任务甲', tags: ['原标签']),
          Task(id: 'b', title: '任务乙'),
        ],
      ),
    );
    addTearDown(store.dispose);
    List<String>? scheduled;
    await showPage(
      tester,
      TodoPage(store: store, onSchedule: (ids) => scheduled = ids),
    );
    await tester.tap(find.text('批量选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('todo-select-all')));
    await tester.pump();
    await tester.tap(find.text('安排本周'));
    expect(scheduled, ['a', 'b']);
    await tester.tap(find.text('移动项目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('目标项目').last);
    await tester.pumpAndSettle();
    expect(store.tasks.every((t) => t.projectId == null), isTrue);
    expect(find.text('无项目 → 目标项目'), findsNWidgets(2));
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(store.tasks.every((t) => t.projectId == 'p'), isTrue);
    await tester.tap(find.byKey(const Key('todo-select-all')));
    await tester.pump();
    await tester.tap(find.text('修改标签'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '研究，数据');
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(store.tasks.first.tags, ['原标签']);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(store.tasks.every((t) => t.tags.join(',') == '研究,数据'), isTrue);
  });

  testWidgets('project delete and recycle restore preserve project tasks', (
    tester,
  ) async {
    final store = FlowStore(
      FlowData(
        projects: [Project(id: 'p', title: '项目甲')],
        tasks: [Task(id: 't', title: '任务', projectId: 'p')],
      ),
    );
    addTearDown(store.dispose);
    await showPage(tester, ProjectsPage(store: store, openWorkflow: (_) {}));
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移入回收站'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(store.tasks, isEmpty);
    await showPage(tester, TrashPage(store: store));
    expect(find.text('项目甲'), findsOneWidget);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.projectId, 'p');
    expect(find.text('项目甲'), findsNothing);
  });

  testWidgets(
    'reports filter completed dates and apportion crossing event time',
    (tester) async {
      final store = FlowStore(
        FlowData(
          tasks: [
            Task(
              id: 't',
              title: '本周完成',
              status: TaskStatus.done,
              completedAt: DateTime(2026, 10, 1),
              estimateMinutes: 90,
              actualMinutes: 90,
            ),
            Task(
              id: 'future',
              title: '本周计划',
              deadline: DateTime(2026, 10, 2),
              estimateMinutes: 60,
            ),
            Task(
              id: 'old',
              title: '历史完成',
              status: TaskStatus.done,
              completedAt: DateTime(2026, 9, 1),
              actualMinutes: 300,
            ),
          ],
          events: [
            CalendarEvent(
              id: 'e',
              title: '跨周时间块',
              taskId: 't',
              start: DateTime(2026, 9, 27, 23, 30),
              end: DateTime(2026, 9, 28, 1),
              completed: true,
              actualMinutes: 90,
            ),
          ],
        ),
      );
      addTearDown(store.dispose);
      await showPage(
        tester,
        ReportsPage(store: store, initialDate: DateTime(2026, 10, 1)),
      );
      expect(find.text('1.0 h'), findsOneWidget);
      expect(find.text('2.5 h'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      await tester.tap(find.text('日'));
      await tester.pumpAndSettle();
      expect(find.text('0.0 h'), findsOneWidget);
      expect(find.text('1.5 h'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    },
  );
}
