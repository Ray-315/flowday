import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/editors.dart';
import 'package:flowday/ui/theme.dart';

Future<void> open(WidgetTester tester, Widget editor) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: flowTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => openEditor(context, editor),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'new editors consume repeat and difficulty defaults without changing existing tasks',
    (tester) async {
      final store = FlowStore(
        FlowData(
          preferences: {'defaultRepeat': 'weekly', 'defaultDifficulty': 'high'},
        ),
      );
      addTearDown(store.dispose);
      await open(tester, TaskEditor(store: store));
      expect(
        tester
            .widget<FlowSelect<Difficulty>>(
              find.byKey(const Key('task-difficulty')),
            )
            .initialValue,
        Difficulty.high,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('repeat-frequency')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<FlowSelect<RepeatFrequency>>(
              find.byKey(const Key('repeat-frequency')),
            )
            .initialValue,
        RepeatFrequency.weekly,
      );
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      await open(tester, EventEditor(store: store));
      await tester.tap(find.text('更多设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('repeat-frequency')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<FlowSelect<RepeatFrequency>>(
              find.byKey(const Key('repeat-frequency')),
            )
            .initialValue,
        RepeatFrequency.weekly,
      );
    },
  );
  testWidgets(
    'task editor edits difficulty and actual time preserving new model fields',
    (tester) async {
      final task = Task(
        id: 't',
        title: '任务',
        plannedStart: DateTime(2026, 10, 1, 9),
        attachments: [
          Attachment(
            id: 'a',
            title: '资料',
            kind: AttachmentKind.url,
            content: 'https://example.com',
          ),
        ],
      );
      final store = FlowStore(FlowData(tasks: [task]));
      addTearDown(store.dispose);
      await open(tester, TaskEditor(store: store, task: task));
      tester
          .widget<FlowSelect<Difficulty>>(
            find.byKey(const Key('task-difficulty')),
          )
          .onChanged!(Difficulty.high);
      await tester.scrollUntilVisible(
        find.byKey(const Key('task-actual')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byKey(const Key('task-actual')), '42');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.tasks.single.difficulty, Difficulty.high);
      expect(store.tasks.single.actualMinutes, 42);
      expect(store.tasks.single.plannedStart, DateTime(2026, 10, 1, 9));
      expect(store.tasks.single.attachments.single.title, '资料');
    },
  );

  testWidgets('repeat task creation uses custom interval and count', (
    tester,
  ) async {
    final store = FlowStore(FlowData());
    addTearDown(store.dispose);
    await open(tester, TaskEditor(store: store));
    await tester.enterText(find.byKey(const Key('task-title')), '复习');
    await tester.scrollUntilVisible(
      find.byKey(const Key('repeat-frequency')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    tester
        .widget<FlowSelect<RepeatFrequency>>(
          find.byKey(const Key('repeat-frequency')),
        )
        .onChanged!(RepeatFrequency.weekly);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('repeat-interval')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('repeat-interval')), '2');
    await tester.enterText(find.byKey(const Key('repeat-count')), '3');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.tasks.length, 3);
    expect(
      store.tasks[1].occurrenceDate!
          .difference(store.tasks[0].occurrenceDate!)
          .inDays,
      14,
    );
  });

  testWidgets(
    'repeat event edit prompts exactly two scopes and preserves metadata',
    (tester) async {
      final store = FlowStore(FlowData());
      addTearDown(store.dispose);
      store.addEvent(
        CalendarEvent(
          id: 'e',
          title: '学习',
          start: DateTime(2026, 10, 1, 9),
          end: DateTime(2026, 10, 1, 10),
          tags: ['课程'],
          attachments: [
            Attachment(
              id: 'a',
              title: '笔记',
              kind: AttachmentKind.markdown,
              content: '# 笔记',
            ),
          ],
          repeatRule: RepeatRule(frequency: RepeatFrequency.daily, count: 3),
        ),
      );
      await open(tester, EventEditor(store: store, event: store.events[1]));
      await tester.enterText(find.byType(TextFormField).first, '调整后的学习');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('仅本次'), findsOneWidget);
      expect(find.text('本次及以后'), findsOneWidget);
      expect(find.byType(SimpleDialogOption), findsNWidgets(2));
      await tester.tap(find.text('本次及以后'));
      await tester.pumpAndSettle();
      expect(store.events.map((x) => x.title), ['学习', '调整后的学习', '调整后的学习']);
      expect(store.events[1].tags, ['课程']);
      expect(store.events[1].attachments.single.content, '# 笔记');
    },
  );
}
