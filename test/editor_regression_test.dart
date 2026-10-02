import 'dart:async';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/app.dart';
import 'package:flowday/ui/editors.dart';
import 'package:flowday/ui/workflow_page.dart';
import 'package:flowday/ui/theme.dart';

void main() {
  testWidgets('explicit status edits override the latest task status', (
    tester,
  ) async {
    final task = Task(id: 't', title: 'Task');
    final store = FlowStore(FlowData(tasks: [task]));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  openEditor(context, TaskEditor(store: store, task: task)),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    tester
        .widget<FlowSelect<TaskStatus>>(find.byType(FlowSelect<TaskStatus>))
        .onChanged!(TaskStatus.waiting);
    store.updateTask(
      Task(id: 't', title: 'Task', status: TaskStatus.done, actualMinutes: 90),
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.tasks.single.status, TaskStatus.waiting);
    expect(store.tasks.single.actualMinutes, 90);
    expect(store.tasks.single.completedAt, isNull);
  });
  testWidgets('missing project dropdown values normalize safely', (
    tester,
  ) async {
    final store = FlowStore(
      FlowData(
        projects: [Project(id: 'p', title: 'Current')],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: projectField(store, 'missing', (_) {}))),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<FlowSelect<String>>(find.byType(FlowSelect<String>))
          .initialValue,
      isNull,
    );
  });
  testWidgets('exit request is cancelled when the save fails', (tester) async {
    final store = FlowStore(
      FlowData(),
      save: (_) async {
        throw StateError('disk');
      },
    );
    await tester.pumpWidget(FlowDayApp(store: store));
    await tester.pumpAndSettle();
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'saving details preserves automatic task completion and subtasks',
    (tester) async {
      final task = Task(id: 't', title: 'Parent');
      final store = FlowStore(
        FlowData(
          tasks: [
            task,
            Task(id: 'child', title: 'Child', parentId: 't'),
          ],
          events: [
            CalendarEvent(
              id: 'e',
              title: 'Block',
              taskId: 't',
              start: DateTime(2026),
              end: DateTime(2026, 1, 1, 1),
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    openEditor(context, TaskEditor(store: store, task: task)),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      store.completeEvent('e');
      store.setTaskStatus('child', TaskStatus.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.data.tasks.first.status, TaskStatus.done);
      expect(store.data.tasks.first.actualMinutes, 60);
      expect(store.data.tasks.first.completedAt, isNotNull);
      expect(store.data.tasks.last.status, TaskStatus.done);
    },
  );
  testWidgets('project field preserves a selected deleted project', (
    tester,
  ) async {
    final store = FlowStore(
      FlowData(
        projects: [
          Project(id: 'p', title: 'Deleted', deletedAt: DateTime(2026)),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: projectField(store, 'p', (_) {}))),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Deleted'), findsOneWidget);
  });
  testWidgets(
    'workflow rejects stale selected ids on initial build and replacement',
    (tester) async {
      final store = FlowStore(
        FlowData(
          projects: [Project(id: 'p', title: 'Current')],
        ),
      );
      Widget page() => MaterialApp(
        home: Scaffold(
          body: WorkflowPage(store: store, projectId: 'missing'),
        ),
      );
      await tester.pumpWidget(page());
      expect(tester.takeException(), isNull);
      expect(find.text('Current'), findsOneWidget);
      store.data = FlowData(
        projects: [Project(id: 'new', title: 'New project')],
      );
      await tester.pumpWidget(page());
      expect(tester.takeException(), isNull);
      expect(find.text('New project'), findsOneWidget);
    },
  );
  testWidgets('resolved save error does not crash delayed notification', (
    tester,
  ) async {
    final store = FlowStore(FlowData());
    await tester.pumpWidget(FlowDayApp(store: store));
    await tester.pumpAndSettle();
    store.error = 'Transient failure';
    store.changed();
    store.error = null;
    store.changed();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Transient failure'), findsNothing);
  });
  testWidgets('exit request waits for final save', (tester) async {
    final gate = Completer<void>();
    final store = FlowStore(FlowData(), save: (_) => gate.future);
    await tester.pumpWidget(FlowDayApp(store: store));
    await tester.pumpAndSettle();
    var finished = false;
    final exit = tester.binding.handleRequestAppExit().then((value) {
      finished = true;
      return value;
    });
    await tester.pump();
    expect(finished, isFalse);
    gate.complete();
    expect(await exit, AppExitResponse.exit);
  });
}
