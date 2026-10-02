import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/native_notifications.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/editors.dart';
import 'package:flowday/ui/strong_reminder_options.dart';
import 'package:flowday/ui/theme.dart';

void main() {
  test(
    'object settings override defaults; completed/cancelled objects are excluded',
    () {
      final start = DateTime(2026, 11, 1, 10);
      final store = FlowStore(
        FlowData(
          events: [
            CalendarEvent(
              id: 'inherit',
              title: 'Inherited',
              start: start,
              end: start.add(const Duration(hours: 1)),
            ),
            CalendarEvent(
              id: 'off',
              title: 'Off',
              start: start,
              end: start.add(const Duration(hours: 1)),
              strongReminder: false,
            ),
            CalendarEvent(
              id: 'done',
              title: 'Done',
              start: start,
              end: start.add(const Duration(hours: 1)),
              completed: true,
            ),
          ],
          tasks: [
            Task(
              id: 'task',
              title: 'Task',
              deadline: start,
              strongReminder: true,
              reminderInterval: 2,
              maxReminders: 2,
            ),
            Task(
              id: 'done-task',
              title: 'Done task',
              deadline: start,
              status: TaskStatus.done,
            ),
            Task(
              id: 'cancelled',
              title: 'Cancelled',
              deadline: start,
              status: TaskStatus.cancelled,
            ),
          ],
        ),
      );
      store.data.preferences.addAll({
        'strongReminder': true,
        'reminderInterval': 5,
        'maxReminders': 3,
      });
      final plans = NativeNotifications.plan(store, DateTime(2026, 10));
      expect(plans.where((p) => p.key.startsWith('event:inherit')).length, 3);
      expect(plans.where((p) => p.key.startsWith('event:off')).length, 1);
      final taskPlans = plans
          .where((p) => p.key.startsWith('task:task'))
          .toList();
      expect(taskPlans.length, 2);
      expect(
        taskPlans[1].due.difference(taskPlans[0].due),
        const Duration(minutes: 2),
      );
      expect(
        plans.any((p) => p.title.contains('Done') || p.title == 'Cancelled'),
        false,
      );
      final later = NativeNotifications.plan(
        store,
        start.subtract(const Duration(minutes: 12)),
      );
      expect(
        later.every(
          (p) => p.due.isAfter(start.subtract(const Duration(minutes: 12))),
        ),
        true,
      );
      store.dispose();
    },
  );

  test('defensive limit bounds strong reminder count at fifty', () {
    final start = DateTime(2026, 11, 1, 10);
    final store = FlowStore(
      FlowData(
        tasks: [
          Task(id: 't', title: 'Task', deadline: start, strongReminder: true),
        ],
      ),
    );
    store.data.preferences['maxReminders'] = 100;
    expect(
      NativeNotifications.plan(
        store,
        DateTime(2026, 10),
        includePast: true,
      ).length,
      50,
    );
    store.dispose();
  });

  testWidgets(
    'task save preserves untouched latest settings and applies explicit overrides',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = FlowStore(
        FlowData(
          tasks: [Task(id: 't', title: 'Task')],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openEditor(
                  context,
                  TaskEditor(store: store, task: store.tasks.single),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final latest = Task.fromJson(store.tasks.single.toJson())
        ..strongReminder = true
        ..reminderInterval = 7
        ..maxReminders = 4;
      store.updateTask(latest);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.tasks.single.strongReminder, true);
      expect(store.tasks.single.reminderInterval, 7);
      expect(store.tasks.single.maxReminders, 4);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final control = tester.widget<StrongReminderOptions>(
        find.byType(StrongReminderOptions),
      );
      control.onStrong(false);
      control.onInterval(2);
      control.onMaximum(null);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.tasks.single.strongReminder, false);
      expect(store.tasks.single.reminderInterval, 2);
      expect(store.tasks.single.maxReminders, isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
