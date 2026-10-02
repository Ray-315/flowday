import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/overview_pages.dart';
import 'package:flowday/ui/theme.dart';

FlowStore noticeFixture() => FlowStore(
  FlowData(
    projects: [Project(id: 'p', title: '项目')],
    tasks: [Task(id: 't', title: '任务')],
    events: [
      CalendarEvent(
        id: 'e',
        title: '日程',
        start: DateTime(2026),
        end: DateTime(2026, 1, 1, 1),
      ),
    ],
    nodes: [FlowNode(id: 'n', projectId: 'p', title: '节点')],
    notices: [
      AppNotice(
        id: 'task',
        title: '任务提醒',
        body: '',
        createdAt: DateTime(2026),
        type: 'reminder',
        taskId: 't',
      ),
      AppNotice(
        id: 'event',
        title: '日程同步冲突',
        body: '',
        createdAt: DateTime(2026),
        eventId: 'e',
      ),
      AppNotice(
        id: 'node',
        title: '节点可开始',
        body: '',
        createdAt: DateTime(2026),
        type: 'workflow',
        nodeId: 'n',
      ),
      AppNotice(
        id: 'project',
        title: '项目归档',
        body: '',
        createdAt: DateTime(2026),
        type: 'system',
        projectId: 'p',
      ),
      AppNotice(
        id: 'ai',
        title: '候选已生成',
        body: '',
        createdAt: DateTime(2026),
        type: 'ai',
      ),
      AppNotice(
        id: 'override',
        title: '节点提醒',
        body: '',
        createdAt: DateTime(2026),
        type: 'system',
      ),
    ],
  ),
);

void main() {
  testWidgets(
    'notification type filters use explicit types and infer legacy titles',
    (tester) async {
      final store = noticeFixture();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: flowTheme(),
          home: Scaffold(body: NoticesPage(store: store)),
        ),
      );
      await tester.tap(find.text('提醒'));
      await tester.pump();
      expect(find.text('任务提醒'), findsOneWidget);
      expect(find.text('节点提醒'), findsNothing);
      await tester.tap(find.text('同步'));
      await tester.pump();
      expect(find.text('日程同步冲突'), findsOneWidget);
      expect(find.text('任务提醒'), findsNothing);
      await tester.tap(find.text('系统'));
      await tester.pump();
      expect(find.text('节点提醒'), findsOneWidget);
      expect(find.text('项目归档'), findsOneWidget);
      await tester.tap(find.text('AI'));
      await tester.pump();
      expect(find.text('候选已生成'), findsOneWidget);
    },
  );

  testWidgets(
    'notification callbacks open correct objects and marking read preserves acknowledgement',
    (tester) async {
      final store = noticeFixture();
      addTearDown(store.dispose);
      final opened = <String>[];
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: flowTheme(),
          home: Scaffold(
            body: NoticesPage(
              store: store,
              onOpenTask: (task) => opened.add('task:${task.id}'),
              onOpenEvent: (event) => opened.add('event:${event.id}'),
              onOpenNode: (node) => opened.add('node:${node.id}'),
              onOpenProject: (id) => opened.add('project:$id'),
            ),
          ),
        ),
      );
      for (final title in ['任务提醒', '日程同步冲突', '节点可开始', '项目归档']) {
        await tester.tap(find.text(title));
        await tester.pump();
      }
      expect(opened, ['task:t', 'event:e', 'node:n', 'project:p']);
      expect(
        store.data.notices
            .where(
              (n) => const ['task', 'event', 'node', 'project'].contains(n.id),
            )
            .every((n) => n.read && !n.acknowledged),
        isTrue,
      );
      await tester.tap(find.text('全部标为已读'));
      await tester.pump();
      expect(store.data.notices.every((n) => n.read), isTrue);
      expect(store.data.notices.every((n) => !n.acknowledged), isTrue);
      final restored = FlowData.fromJson(store.data.toJson());
      expect(restored.notices.first.type, 'reminder');
      expect(restored.notices[1].eventId, 'e');
      expect(restored.notices[2].nodeId, 'n');
      expect(restored.notices[3].projectId, 'p');
    },
  );

  testWidgets(
    'reports pressure and evening review count actual work and next-day content',
    (tester) async {
      final day = DateTime(2026, 10, 1);
      final store = FlowStore(
        FlowData(
          tasks: [
            Task(
              id: 'done',
              title: '完成任务',
              status: TaskStatus.done,
              completedAt: day.add(const Duration(hours: 18)),
              actualMinutes: 90,
            ),
            Task(
              id: 'pending',
              title: '今日未完成',
              plannedStart: day.add(const Duration(hours: 12)),
              estimateMinutes: 120,
            ),
            Task(
              id: 'tomorrow',
              title: '次日待办',
              plannedStart: day.add(const Duration(days: 1, hours: 9)),
              estimateMinutes: 30,
            ),
          ],
          events: [
            CalendarEvent(
              id: 'block',
              title: '已完成时间块',
              taskId: 'done',
              start: day.add(const Duration(hours: 9)),
              end: day.add(const Duration(hours: 10)),
              completed: true,
              actualMinutes: 60,
            ),
            CalendarEvent(
              id: 'next',
              title: '次日会议',
              start: day.add(const Duration(days: 1, hours: 10)),
              end: day.add(const Duration(days: 1, hours: 11)),
            ),
          ],
        ),
      );
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: flowTheme(),
          home: Scaffold(
            body: ReportsPage(store: store, initialDate: day),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('reports-pressure-curve')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('reports-pressure-curve')),
                  )
                  .painter!
              as PressureCurvePainter;
      expect(painter.values[3], 3);
      expect(painter.values[4], 1.5);
      await tester.scrollUntilVisible(
        find.byKey(const Key('report-review-actual')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('完成 1 项'), findsOneWidget);
      expect(find.text('未完成 1 项'), findsOneWidget);
      expect(find.text('实际投入 1.5h'), findsOneWidget);
      expect(find.text('次日会议'), findsOneWidget);
      expect(find.text('次日待办'), findsOneWidget);
    },
  );

  test(
    'event reminder rules distinguish inheritance and explicit off and validate overrides',
    () {
      CalendarEvent event({int? lead, List<Map<String, dynamic>>? rules}) =>
          CalendarEvent(
            id: 'e',
            title: '日程',
            start: DateTime(2026),
            end: DateTime(2026, 1, 1, 1),
            reminderLeadMinutes: lead,
            reminderRules: rules,
          );
      expect(CalendarEvent.fromJson(event().toJson()).reminderRules, isNull);
      expect(
        CalendarEvent.fromJson(event(rules: []).toJson()).reminderRules,
        isEmpty,
      );
      final absolute = event(
        rules: [
          {'dueAt': '2026-01-01T09:00:00+08:00'},
        ],
      );
      expect(
        (absolute.toJson()['reminderRules'] as List).single['dueAt'],
        '2026-01-01T01:00:00.000Z',
      );
      FlowData(
        events: [
          event(
            lead: 0,
            rules: [
              {'leadMinutes': 15},
            ],
          ),
        ],
        preferences: {'courseReminderLeadMinutes': 60},
      ).validate();
      expect(
        () => FlowData(events: [event(lead: -1)]).validate(),
        throwsFormatException,
      );
      expect(
        () => FlowData(
          events: [
            event(
              rules: [
                {'dueAt': 'bad'},
              ],
            ),
          ],
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => FlowData(
          events: [
            event(rules: List.generate(11, (_) => {'leadMinutes': 15})),
          ],
        ).validate(),
        throwsFormatException,
      );
    },
  );
}
