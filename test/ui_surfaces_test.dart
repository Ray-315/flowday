import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/task_pages.dart';
import 'package:flowday/ui/mini_calendar.dart';
import 'package:flowday/ui/theme.dart';
import 'package:flowday/ui/calendar_page.dart';

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
}

void main() {
  testWidgets(
    'dark calendar event labels stay readable for dark event colors',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day, 10);
      final event = CalendarEvent(
        id: 'event',
        title: '深色日程',
        start: start,
        end: start.add(const Duration(hours: 1)),
        color: 0xff15203a,
      );
      final theme = flowTheme(brightness: Brightness.dark);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: CalendarPage(store: FlowStore(FlowData(events: [event]))),
          ),
        ),
      );
      final finder = find.text('10:00  深色日程');
      expect(finder, findsOneWidget);
      final label = tester.widget<Text>(finder);
      final container = tester.widget<Container>(
        find.ancestor(of: finder, matching: find.byType(Container)).first,
      );
      final fill = (container.decoration! as BoxDecoration).color!;
      final background = Color.alphaBlend(fill, theme.colorScheme.surface);
      expect(
        contrast(label.style!.color!, background),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('dark task titles and calendar labels remain readable', (
    tester,
  ) async {
    final theme = flowTheme(brightness: Brightness.dark);
    final task = Task(id: 'dark-task', title: '深色任务');
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              TaskRow(
                store: FlowStore(FlowData(tasks: [task])),
                task: task,
              ),
              SizedBox(
                width: 300,
                child: MiniCalendar(
                  selected: DateTime(2026, 9, 30),
                  onSelected: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final title = tester.widget<Text>(find.text('深色任务'));
    expect(
      contrast(title.style!.color!, theme.colorScheme.surface),
      greaterThanOrEqualTo(4.5),
    );
    final label = tester.widget<Text>(find.text('一'));
    expect(
      contrast(label.style!.color!, theme.colorScheme.surface),
      greaterThanOrEqualTo(4.5),
    );
  });
}
