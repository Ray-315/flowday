import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/calendar_page.dart';
import 'package:flowday/ui/mini_calendar.dart';
import 'package:flowday/ui/theme.dart';

Future<void> selectDay(
  WidgetTester tester,
  FlowStore store,
  DateTime date,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: flowTheme(),
      home: Scaffold(body: CalendarPage(store: store)),
    ),
  );
  tester.widget<MiniCalendar>(find.byType(MiniCalendar)).onSelected(date);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  setUp(() => DisplayPreferences.timezone = 'America/New_York');
  tearDown(() => DisplayPreferences.timezone = 'system');
  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'DST day excludes following midnight and locates nine oclock event at nine',
    (tester) async {
      desktop(tester);
      final store = FlowStore(
        FlowData(
          events: [
            CalendarEvent(
              id: 'morning',
              title: '九点日程',
              start: DateTime.utc(2026, 3, 8, 13),
              end: DateTime.utc(2026, 3, 8, 14),
            ),
            CalendarEvent(
              id: 'next',
              title: '次日凌晨',
              start: DateTime.utc(2026, 3, 9, 4, 30),
              end: DateTime.utc(2026, 3, 9, 5),
            ),
          ],
          preferences: {'calendarView': '日'},
        ),
      );
      addTearDown(store.dispose);
      await selectDay(tester, store, DateTime(2026, 3, 8));
      expect(find.text('九点日程'), findsOneWidget);
      expect(find.text('次日凌晨'), findsNothing);
      final placement = tester.widget<Positioned>(
        find
            .ancestor(
              of: find.text('九点日程'),
              matching: find.byWidgetPredicate(
                (widget) => widget is Positioned && (widget.top ?? 0) > 0,
              ),
            )
            .first,
      );
      expect(placement.top, 9 * 64 + 2);
      expect(placement.height, 60 / 60 * 64 - 4);
      await tester.tap(find.byIcon(Icons.chevron_right).first);
      await tester.pumpAndSettle();
      expect(find.text('3月9日'), findsNWidgets(2));
    },
  );

  testWidgets('day creation and task drop use wall time after DST switch', (
    tester,
  ) async {
    desktop(tester);
    final task = Task(id: 't', title: '拖入任务', estimateMinutes: 60);
    final store = FlowStore(
      FlowData(tasks: [task], preferences: {'calendarView': '日'}),
    );
    addTearDown(store.dispose);
    await selectDay(tester, store, DateTime(2026, 3, 8));
    final target = tester.widget<DragTarget<Object>>(
      find.byKey(const Key('calendar-slot-0-9')),
    );
    target.onAcceptWithDetails!(
      DragTargetDetails<Object>(data: task, offset: Offset.zero),
    );
    await tester.pump();
    expect(store.events.single.start.toUtc(), DateTime.utc(2026, 3, 8, 13));
    await tester.tap(find.text('新建日程').first);
    await tester.pumpAndSettle();
    final startField = find.byKey(const ValueKey('event-time-开始时间'));
    expect(
      find.descendant(of: startField, matching: find.text('2026年3月8日')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: startField, matching: find.text('09:00')),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextFormField).first, '新建九点');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.events.last.start.toUtc(), DateTime.utc(2026, 3, 8, 13));
  });

  testWidgets(
    'month move preserves selected timezone clock time across DST boundary',
    (tester) async {
      desktop(tester);
      final event = CalendarEvent(
        id: 'e',
        title: '移动会议',
        start: DateTime.utc(2026, 3, 7, 14, 30),
        end: DateTime.utc(2026, 3, 7, 16),
      );
      final store = FlowStore(
        FlowData(events: [event], preferences: {'calendarView': '日'}),
      );
      addTearDown(store.dispose);
      await selectDay(tester, store, DateTime(2026, 3, 7));
      await tester.tap(find.text('月').first);
      await tester.pumpAndSettle();
      final target = tester.widget<DragTarget<CalendarEvent>>(
        find.byKey(const Key('calendar-day-2026-3-9')),
      );
      target.onAcceptWithDetails!(
        DragTargetDetails<CalendarEvent>(data: event, offset: Offset.zero),
      );
      await tester.pump();
      expect(displayTime(event.start).hour, 9);
      expect(displayTime(event.start).minute, 30);
      expect(event.start.toUtc(), DateTime.utc(2026, 3, 9, 13, 30));
      expect(event.end.difference(event.start).inMinutes, 90);
    },
  );

  testWidgets('week date labels and slots remain midnight anchored over DST', (
    tester,
  ) async {
    desktop(tester);
    final task = Task(id: 't', title: '本周任务');
    final store = FlowStore(
      FlowData(
        tasks: [task],
        preferences: {'calendarView': '日', 'weekStartsMonday': true},
      ),
    );
    addTearDown(store.dispose);
    await selectDay(tester, store, DateTime(2026, 3, 8));
    await tester.tap(find.text('周').first);
    await tester.pumpAndSettle();
    final target = tester.widget<DragTarget<Object>>(
      find.byKey(const Key('calendar-slot-6-9')),
    );
    target.onAcceptWithDetails!(
      DragTargetDetails<Object>(data: task, offset: Offset.zero),
    );
    await tester.pump();
    expect(store.events.single.start.toUtc(), DateTime.utc(2026, 3, 8, 13));
    expect(displayTime(store.events.single.start).hour, 9);
  });
}
