import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/api_client.dart';
import 'package:flowday/data/course_import.dart';
import 'package:flowday/data/native_notifications.dart';
import 'package:flowday/data/sync_controller.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/editors.dart';
import 'package:flowday/ui/event_sync_status.dart';
import 'package:flowday/ui/event_reminder_rules.dart';
import 'package:flowday/ui/theme.dart';

void main() {
  test(
    'all explicit reminder rules schedule, empty disables, null inherits',
    () {
      final date = DateTime(2026, 11, 1, 10);
      final store = FlowStore(
        FlowData(
          events: [
            CalendarEvent(
              id: 'rules',
              title: 'Rules',
              start: date,
              end: date.add(const Duration(hours: 1)),
              reminderRules: [
                {'leadMinutes': 30},
                {'dueAt': DateTime(2026, 11, 1, 8).toUtc().toIso8601String()},
              ],
            ),
            CalendarEvent(
              id: 'disabled',
              title: 'Disabled',
              start: date,
              end: date.add(const Duration(hours: 1)),
              reminderRules: [],
            ),
            CalendarEvent(
              id: 'inherit',
              title: 'Default',
              start: date,
              end: date.add(const Duration(hours: 1)),
            ),
          ],
        ),
      );
      final plans = NativeNotifications.plan(store, DateTime(2026, 10));
      expect(plans.length, 3);
      expect(plans.map((p) => p.key), [
        'event:rules:rule:1',
        'event:rules:rule:0',
        'event:inherit',
      ]);
      expect(plans[0].due.toLocal(), DateTime(2026, 11, 1, 8));
      expect(plans[1].due, date.subtract(const Duration(minutes: 30)));
      store.dispose();
    },
  );

  testWidgets(
    'rules editor preserves null, explicit off and absolute time; caps ten',
    (tester) async {
      List<Map<String, dynamic>>? changed;
      final date = DateTime(2026, 11, 1, 8);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              child: SingleChildScrollView(
                child: EventReminderRules(
                  initialRules: null,
                  onChanged: (v) => changed = v,
                  pickDate: (_) async => date,
                ),
              ),
            ),
          ),
        ),
      );
      void mode(String value) => tester
          .widget<FlowSelect<String>>(find.byType(FlowSelect<String>))
          .onChanged!(value);
      mode('custom');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.swap_horiz));
      await tester.pump();
      expect(changed, [
        {'dueAt': date.toUtc().toIso8601String()},
      ]);
      mode('off');
      await tester.pump();
      expect(changed, isEmpty);
      mode('inherit');
      await tester.pump();
      expect(changed, isNull);
      mode('custom');
      await tester.pump();
      for (var i = 1; i < 10; i++) {
        await tester.ensureVisible(find.text('添加提醒'));
        await tester.tap(find.text('添加提醒'));
        await tester.pump();
      }
      expect(changed!.length, 10);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '添加提醒'))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'course import inherits default and accepts override without changing default',
    () {
      final store = FlowStore(FlowData());
      store.data.preferences['courseReminderLeadMinutes'] = 20;
      final lessons = CourseImport.parse(
        'title,start,end\nMath,2026-11-01T10:00:00,2026-11-01T11:00:00',
        'csv',
      );
      CourseImport.commit(store, lessons);
      CourseImport.commit(store, lessons, reminderLeadMinutes: 5);
      expect(store.events.map((e) => e.reminderLeadMinutes), [20, 5]);
      expect(store.data.preferences['courseReminderLeadMinutes'], 20);
      expect(
        () => CourseImport.commit(store, lessons, reminderLeadMinutes: -1),
        throwsFormatException,
      );
      expect(store.events.length, 2);
      final plans = NativeNotifications.plan(store, DateTime(2026, 10));
      expect(
        plans.first.due,
        lessons.first.start.subtract(const Duration(minutes: 20)),
      );
      expect(
        plans.last.due,
        lessons.first.start.subtract(const Duration(minutes: 5)),
      );
      store.dispose();
    },
  );

  testWidgets('event override saves and blank reverts to inherited reminder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final event = CalendarEvent(
      id: 'e',
      title: 'Lesson',
      start: DateTime(2026, 11, 1, 10),
      end: DateTime(2026, 11, 1, 11),
    );
    final store = FlowStore(FlowData(events: [event]));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openEditor(
                context,
                EventEditor(store: store, event: store.events.single),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    for (final value in ['30', '']) {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('更多设置'));
      await tester.tap(find.text('更多设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('event-reminder')));
      await tester.enterText(find.byKey(const Key('event-reminder')), value);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(
        store.events.single.reminderLeadMinutes,
        value.isEmpty ? null : 30,
      );
    }
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
    'Apple status displays only actual event mapping; failed fetch never shows success',
    (tester) async {
      var fail = false;
      final store = FlowStore(FlowData());
      final api = FlowApi(
        Uri.parse('https://example.com'),
        transport: (method, url, headers, body) async {
          expect(headers['Authorization'], 'Bearer fixture');
          expect(url.path, endsWith('/integrations/apple'));
          if (fail) throw const ApiException(0, 'OFFLINE', 'Offline');
          return ApiResponse(
            200,
            jsonEncode({
              'records': [
                {
                  'eventId': 'e',
                  'source': 'apple',
                  'status': 'conflict',
                  'conflictId': 'c',
                  'lastSyncAt': '2026-10-01T10:00:00Z',
                },
                {'eventId': 'other', 'source': 'local', 'status': 'synced'},
              ],
            }),
          );
        },
      );
      final sync = SyncController(
        api: api,
        store: store,
        session: const AuthSession(
          token: 'fixture',
          user: AccountUser(id: 'u', email: 'u@example.com', displayName: 'U'),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventSyncStatus(sync: sync, eventId: 'e'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Apple 日历 · 同步冲突'), findsOneWidget);
      expect(find.textContaining('上次同步'), findsOneWidget);
      expect(find.textContaining('已同步'), findsNothing);
      fail = true;
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(find.text('Apple 日历状态读取失败'), findsOneWidget);
      expect(find.textContaining('已同步'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      sync.dispose();
      store.dispose();
    },
  );
}
