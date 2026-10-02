import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';

void main() {
  CalendarEvent event() => CalendarEvent(
    id: 'e',
    title: '日程',
    start: DateTime(2026, 10, 1, 9),
    end: DateTime(2026, 10, 1, 10),
  );

  test(
    'reminder overrides preserve inheritance and explicit values in JSON',
    () {
      final task = Task(id: 't', title: '任务');
      final appointment = event();
      expect(Task.fromJson(task.toJson()).strongReminder, isNull);
      expect(
        CalendarEvent.fromJson(appointment.toJson()).reminderInterval,
        isNull,
      );
      task.strongReminder = false;
      task.reminderInterval = 10080;
      task.maxReminders = 50;
      appointment.strongReminder = true;
      appointment.reminderInterval = 1;
      appointment.maxReminders = 1;
      final restored = FlowData.fromJson(
        FlowData(tasks: [task], events: [appointment]).toJson(),
      );
      restored.validate();
      expect(restored.tasks.single.strongReminder, isFalse);
      expect(restored.tasks.single.reminderInterval, 10080);
      expect(restored.tasks.single.maxReminders, 50);
      expect(restored.events.single.strongReminder, isTrue);
      expect(restored.events.single.reminderInterval, 1);
      expect(restored.events.single.maxReminders, 1);
    },
  );

  test('task and event reminder overrides reject out of range values', () {
    for (final interval in [0, 10081]) {
      final task = Task(id: 't', title: '任务', reminderInterval: interval);
      final appointment = event()..reminderInterval = interval;
      expect(() => FlowData(tasks: [task]).validate(), throwsFormatException);
      expect(
        () => FlowData(events: [appointment]).validate(),
        throwsFormatException,
      );
    }
    for (final maximum in [0, 51]) {
      final task = Task(id: 't', title: '任务', maxReminders: maximum);
      final appointment = event()..maxReminders = maximum;
      expect(() => FlowData(tasks: [task]).validate(), throwsFormatException);
      expect(
        () => FlowData(events: [appointment]).validate(),
        throwsFormatException,
      );
    }
  });

  test(
    'future event edits propagate overrides and can restore inheritance',
    () {
      final store = FlowStore(FlowData());
      store.addEvent(
        event()
          ..repeatRule = RepeatRule(frequency: RepeatFrequency.daily, count: 3),
      );
      final second = store.events[1];
      final edited = CalendarEvent.fromJson(second.toJson())
        ..strongReminder = false
        ..reminderInterval = 20
        ..maxReminders = 4;
      store.updateEvent(edited, scope: RepeatScope.thisAndFuture);
      expect(store.events.first.strongReminder, isNull);
      expect(store.events.last.strongReminder, isFalse);
      expect(store.events.last.reminderInterval, 20);
      expect(store.events.last.maxReminders, 4);
      store.updateEvent(
        CalendarEvent.fromJson(edited.toJson())
          ..strongReminder = null
          ..reminderInterval = null
          ..maxReminders = null,
        scope: RepeatScope.thisAndFuture,
      );
      expect(store.events.last.strongReminder, isNull);
      expect(store.events.last.reminderInterval, isNull);
      expect(store.events.last.maxReminders, isNull);
    },
  );
}
