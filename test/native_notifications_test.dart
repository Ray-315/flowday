import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/api_client.dart';
import 'package:flowday/data/native_notifications.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';

class FakeNotifications implements NotificationAdapter {
  FakeNotifications({this.supportsScheduling = true});
  @override
  final bool supportsScheduling;
  bool granted = true, fail = false;
  final shown = <NotificationPlan>[],
      scheduled = <NotificationPlan>[],
      cancelled = <int>[];
  final pending = <int, NotificationPlan>{};
  @override
  Future<bool> initialize() async {
    if (fail) throw StateError('unavailable');
    return true;
  }

  @override
  Future<bool?> permission() async => granted;
  @override
  Future<bool?> requestPermission() async => granted;
  @override
  Future<List<int>> pendingIds() async => pending.keys.toList();
  @override
  Future<void> show(NotificationPlan plan) async {
    if (fail) throw StateError('unavailable');
    shown.add(plan);
  }

  @override
  Future<void> schedule(NotificationPlan plan) async {
    if (fail) throw StateError('unavailable');
    scheduled.add(plan);
    pending[plan.id] = plan;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    pending.remove(id);
  }
}

FlowStore data(DateTime now) => FlowStore(
  FlowData(
    events: [
      CalendarEvent(
        id: 'e',
        title: '会议',
        start: now.add(const Duration(hours: 1)),
        end: now.add(const Duration(hours: 2)),
      ),
    ],
    tasks: [
      Task(id: 't', title: '任务', deadline: now.add(const Duration(hours: 3))),
    ],
  ),
);
void main() {
  test('Linux does not show a deleted or completed pending reminder', () async {
    var now = DateTime(2026, 10, 1);
    final store = data(now),
        adapter = FakeNotifications(supportsScheduling: false);
    final service = NativeNotifications(adapter: adapter, clock: () => now);
    await service.attach(store);
    store.data.events.first.completed = true;
    now = now.add(const Duration(hours: 1));
    await service.refresh();
    expect(adapter.shown, isEmpty);
    service.dispose();
    store.dispose();
  });
  test(
    'plans honor zero reminder offsets, remove completed objects and cap iOS requests',
    () {
      final now = DateTime(2026, 10, 1), store = data(now);
      store.data.preferences['reminderMinutes'] = 0;
      expect(
        NativeNotifications.plan(store, now).first.due,
        store.events.first.start,
      );
      store.data.events.first.completed = true;
      store.data.tasks.first.status = TaskStatus.done;
      expect(NativeNotifications.plan(store, now), isEmpty);
      for (var i = 0; i < 70; i++) {
        store.data.events.add(
          CalendarEvent(
            id: 'more$i',
            title: '计划',
            start: now.add(Duration(days: i + 1)),
            end: now.add(Duration(days: i + 1, hours: 1)),
          ),
        );
      }
      expect(NativeNotifications.plan(store, now).length, 60);
      store.dispose();
    },
  );
  test(
    'schedules update edited due times and cancel deleted objects',
    () async {
      final now = DateTime(2026, 10, 1),
          store = data(now),
          adapter = FakeNotifications();
      final service = NativeNotifications(adapter: adapter, clock: () => now);
      await service.attach(store);
      expect(adapter.scheduled.length, 2);
      await service.refresh();
      expect(adapter.scheduled.length, 2);
      store.data.events.first.start = now.add(const Duration(hours: 2));
      await service.refresh();
      expect(adapter.scheduled.length, 3);
      store.data.events.clear();
      await service.refresh();
      expect(adapter.cancelled, contains(stableNotificationId('event:e')));
      expect(adapter.pending.length, 1);
      service.dispose();
      store.dispose();
    },
  );
  test(
    'online reminder receipt prevents repeated delivery across app restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'flowday-native-receipts-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final now = DateTime(2026, 10, 1), store = FlowStore(FlowData());
      final api = FlowApi(
        Uri.parse('https://example.test'),
        transport: (method, url, headers, body) async => ApiResponse(
          200,
          jsonEncode({
            'reminders': [
              {
                'id': 'r',
                'title': '提醒',
                'dueAt': now
                    .subtract(const Duration(minutes: 1))
                    .toIso8601String(),
                'sentCount': 1,
                'acknowledged': false,
                'channel': 'in_app',
              },
            ],
          }),
        ),
      );
      final first = FakeNotifications(),
          service = NativeNotifications(adapter: first, clock: () => now);
      await service.attach(
        store,
        api: api,
        token: 'synthetic',
        directory: directory,
      );
      await service.refresh();
      expect(first.shown.length, 1);
      service.dispose();
      final second = FakeNotifications(),
          restarted = NativeNotifications(adapter: second, clock: () => now);
      await restarted.attach(
        store,
        api: api,
        token: 'synthetic',
        directory: directory,
      );
      expect(second.shown, isEmpty);
      restarted.dispose();
      store.dispose();
    },
  );
  test(
    'permission denial and initialization failure preserve data without crashing',
    () async {
      final now = DateTime(2026, 10, 1),
          store = data(now),
          before = store.exportJson();
      final adapter = FakeNotifications()..granted = false,
          service = NativeNotifications(adapter: adapter, clock: () => now);
      await service.attach(store);
      expect(adapter.scheduled, isEmpty);
      expect(await service.requestPermission(), isFalse);
      expect(service.error, isNotNull);
      expect(store.exportJson(), before);
      service.dispose();
      final failed = NativeNotifications(
        adapter: FakeNotifications()..fail = true,
      );
      await failed.attach(store);
      expect(failed.ready, isFalse);
      expect(failed.error, isNotNull);
      expect(store.exportJson(), before);
      failed.dispose();
      store.dispose();
    },
  );
  test('Linux emits due reminders only while the application runs', () async {
    var now = DateTime(2026, 10, 1);
    final store = data(now),
        adapter = FakeNotifications(supportsScheduling: false);
    final service = NativeNotifications(adapter: adapter, clock: () => now);
    await service.attach(store);
    expect(adapter.scheduled, isEmpty);
    now = now.add(const Duration(hours: 1));
    await service.refresh();
    expect(adapter.shown.single.title, '会议');
    await service.refresh();
    expect(adapter.shown.length, 1);
    service.dispose();
    store.dispose();
  });
}
