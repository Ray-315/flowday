import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/theme.dart';
import 'package:flowday/ui/today_page.dart';
import 'package:flowday/ui/today_customization.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);
  tearDown(() {
    DisplayPreferences.timezone = 'system';
    DisplayPreferences.dateFormat = 'chinese';
    DisplayPreferences.timeFormat = '24';
  });
  test('display formatting and day comparison honor selected timezone', () {
    final instant = DateTime.utc(2026, 10, 1);
    DisplayPreferences.timezone = 'Asia/Shanghai';
    expect(clockText(instant), '08:00');
    expect(dateText(instant), '2026年10月1日');
    DisplayPreferences.timezone = 'America/New_York';
    expect(clockText(instant), '20:00');
    expect(dateText(instant), '2026年9月30日');
    expect(
      sameDay(DateTime.utc(2026, 10, 1, 2), DateTime.utc(2026, 10, 1, 8)),
      isFalse,
    );
    final day = displayDate(2026, 3, 8);
    final nextDay = displayDate(2026, 3, 9);
    expect(nextDay.difference(day).inHours, 23);
    expect(dayOnly(day), day);
  });

  testWidgets(
    'Today module visibility and reordered layout persist across export',
    (tester) async {
      final store = FlowStore(FlowData());
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: flowTheme(),
          home: Scaffold(
            body: Column(
              children: [
                Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showTodayCustomization(context, store),
                    child: const Text('定制'),
                  ),
                ),
                Expanded(
                  child: TodayPage(store: store, navigate: (_) {}),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('定制'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('today-module-toggle-timeline')),
      );
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(4, 0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('today-timeline')), findsNothing);
      expect(find.text('本日概览'), findsOneWidget);
      expect(
        (store.data.preferences['todayModuleOrder'] as List).first,
        'overview',
      );
      expect(todayHiddenModules(store), contains('timeline'));
      final restored = FlowStore(FlowData.fromJson(store.data.toJson()));
      addTearDown(restored.dispose);
      expect(todayModuleOrder(restored).first, 'overview');
      expect(todayHiddenModules(restored), contains('timeline'));
      expect(
        tester.getTopLeft(find.text('本日概览')).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('today-capture'))).dy),
      );
    },
  );

  testWidgets(
    'enabled extra modules show real nodes overdue tasks and notices',
    (tester) async {
      final store = FlowStore(
        FlowData(
          projects: [Project(id: 'p', title: '项目甲')],
          tasks: [
            Task(
              id: 't',
              title: '延期任务',
              deadline: DateTime.now().subtract(const Duration(days: 1)),
            ),
          ],
          nodes: [FlowNode(id: 'n', projectId: 'p', title: '可开始节点')],
          notices: [
            AppNotice(
              id: 'notice',
              title: '新提醒',
              body: '任务待确认',
              createdAt: DateTime.now(),
            ),
          ],
          preferences: {
            'todayModuleOrder': ['workflow', 'overdue', 'notices'],
            'todayHiddenModules': [
              'capture',
              'timeline',
              'todo',
              'calendar',
              'overview',
              'pressure',
            ],
          },
        ),
      );
      addTearDown(store.dispose);
      String? project;
      await tester.pumpWidget(
        MaterialApp(
          theme: flowTheme(),
          home: Scaffold(
            body: TodayPage(
              store: store,
              navigate: (_) {},
              onOpenWorkflow: (value) => project = value,
            ),
          ),
        ),
      );
      expect(find.text('可开始节点'), findsOneWidget);
      expect(find.text('延期任务'), findsOneWidget);
      expect(find.text('新提醒'), findsOneWidget);
      await tester.tap(find.text('可开始节点'));
      expect(project, 'p');
      await tester.tap(find.text('已知晓'));
      await tester.pump();
      expect(store.data.notices.single.acknowledged, isTrue);
      expect(find.text('新提醒'), findsNothing);
    },
  );

  testWidgets(
    'Today timeline places UTC events in chosen local date and time',
    (tester) async {
      DisplayPreferences.timezone = 'Asia/Shanghai';
      final now = displayTime(DateTime.now());
      final start = displayDate(now.year, now.month, now.day, 9).toUtc();
      final store = FlowStore(
        FlowData(
          events: [
            CalendarEvent(
              id: 'e',
              title: '时区事件',
              start: start,
              end: start.add(const Duration(hours: 1)),
            ),
          ],
        ),
      );
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: flowTheme(),
          home: Scaffold(
            body: TodayPage(store: store, navigate: (_) {}),
          ),
        ),
      );
      expect(find.textContaining('09:00 - 10:00  时区事件'), findsOneWidget);
    },
  );
}
