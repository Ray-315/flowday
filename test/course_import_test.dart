import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/course_import.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/course_import_panel.dart';

void main() {
  test(
    'ICS fixed timezone is converted and unknown timezone fails explicitly',
    () {
      const source =
          'BEGIN:VEVENT\nSUMMARY:课程\nDTSTART;TZID=Asia/Shanghai:20260901T100000\nDTEND;TZID=Asia/Shanghai:20260901T110000\nEND:VEVENT';
      final lesson = CourseImport.parse(source, 'ics').single;
      expect(lesson.start, DateTime.utc(2026, 9, 1, 2).toLocal());
      expect(
        () => CourseImport.parse(
          source.replaceAll('Asia/Shanghai', 'America/New_York'),
          'ics',
        ),
        throwsFormatException,
      );
    },
  );
  test('invalid week and calendar values are rejected', () {
    expect(
      () => CourseImport.parse(
        '课程名,星期,开始时刻,结束时刻,起始周,结束周\n数学,1,08:00,09:00,no,4',
        'csv',
        semesterStart: DateTime(2026),
      ),
      throwsFormatException,
    );
    const source =
        'BEGIN:VEVENT\nSUMMARY:课程\nDTSTART:20261301T100000\nDTEND:20261301T110000\nEND:VEVENT';
    expect(() => CourseImport.parse(source, 'ics'), throwsFormatException);
  });
  test('CSV quotes and odd weeks expand against semester Monday', () {
    const text =
        '课程名,教师,地点,星期,开始时刻,结束时刻,起始周,结束周,单双周,备注\n"数学,基础",张老师,A101,星期一,08:00,09:30,1,4,单周,"第一行\n第二行"';
    final lessons = CourseImport.parse(
      text,
      'csv',
      semesterStart: DateTime(2026, 9, 2),
    );
    expect(lessons.length, 2);
    expect(lessons.first.title, '数学,基础');
    expect(lessons.first.start, DateTime(2026, 8, 31, 8));
    expect(lessons.last.start, DateTime(2026, 9, 14, 8));
    expect(lessons.first.notes, '第一行\n第二行');
  });
  test('custom mappings and even weeks are respected', () {
    const text =
        'subject,dayOfWeek,begin,finish,lastWeek,mode\n物理,2,10:00,11:00,4,even';
    final lessons = CourseImport.parse(
      text,
      'csv',
      semesterStart: DateTime(2026, 8, 31),
      mapping: {
        'title': 'subject',
        'weekday': 'dayOfWeek',
        'startTime': 'begin',
        'endTime': 'finish',
        'endWeek': 'lastWeek',
        'parity': 'mode',
      },
    );
    expect(lessons.map((l) => l.start), [
      DateTime(2026, 9, 8, 10),
      DateTime(2026, 9, 22, 10),
    ]);
  });
  test('JSON dated courses preserve teacher and location', () {
    final lessons = CourseImport.parse(
      jsonEncode({
        'courses': [
          {
            'title': '英语',
            'teacher': '王',
            'location': 'B',
            'start': '2026-09-01T10:00:00',
            'end': '2026-09-01T11:00:00',
          },
        ],
      }),
      'json',
    );
    expect(lessons.single.teacher, '王');
    expect(lessons.single.location, 'B');
  });
  test('invalid input fails before changes', () {
    expect(
      () =>
          CourseImport.parse('课程名,星期,开始时刻,结束时刻,结束周\n数学,1,08:00,09:00,4', 'csv'),
      throwsFormatException,
    );
    expect(
      () => CourseImport.parse(
        '课程名,开始时间,结束时间\n数学,2026-09-01T10:00,2026-09-01T09:00',
        'csv',
      ),
      throwsFormatException,
    );
    expect(
      () => CourseImport.parse('课程名,开始时间\n数学,2026-09-01T10:00,extra', 'csv'),
      throwsFormatException,
    );
    expect(() => CourseImport.csv('"未闭合'), throwsFormatException);
  });
  test(
    'ICS weekly recurrence expands and exclusions omit cancelled instances',
    () {
      const ics =
          'BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:化学\nDTSTART:20260901T100000\nDTEND:20260901T113000\nRRULE:FREQ=WEEKLY;COUNT=3;BYDAY=TU\nEXDATE:20260908T100000\nLOCATION:C101\nEND:VEVENT\nEND:VCALENDAR';
      final lessons = CourseImport.parse(ics, 'ics');
      expect(lessons.length, 2);
      expect(lessons.last.start, DateTime(2026, 9, 15, 10));
      expect(
        lessons.first.end.difference(lessons.first.start),
        const Duration(minutes: 90),
      );
    },
  );
  test('ICS unbounded recurrence fails rather than dropping repeats', () {
    const ics =
        'BEGIN:VEVENT\nSUMMARY:数学\nDTSTART:20260901T100000\nDTEND:20260901T110000\nRRULE:FREQ=WEEKLY\nEND:VEVENT';
    expect(() => CourseImport.parse(ics, 'ics'), throwsFormatException);
  });
  test(
    'preview finds existing and intra-import overlap while adjacent events remain valid',
    () {
      final a = CourseLesson(
        title: '数学',
        start: DateTime(2026, 9, 1, 10),
        end: DateTime(2026, 9, 1, 11),
      );
      final b = CourseLesson(
        title: '英语',
        start: DateTime(2026, 9, 1, 10, 30),
        end: DateTime(2026, 9, 1, 11, 30),
      );
      final existing = [
        CalendarEvent(
          id: 'e',
          title: '会议',
          start: DateTime(2026, 9, 1, 9),
          end: DateTime(2026, 9, 1, 10),
        ),
      ];
      expect(CourseImport.conflicts([a], existing), isEmpty);
      expect(CourseImport.conflicts([a, b], existing).single.title, '数学');
    },
  );
  test(
    'commit creates course hierarchy and atomically rejects invalid lessons',
    () {
      final store = FlowStore(FlowData());
      final lessons = [
        CourseLesson(
          title: '数学',
          teacher: '张',
          start: DateTime(2026, 9, 1, 10),
          end: DateTime(2026, 9, 1, 11),
        ),
        CourseLesson(
          title: '数学',
          teacher: '张',
          start: DateTime(2026, 9, 8, 10),
          end: DateTime(2026, 9, 8, 11),
        ),
      ];
      CourseImport.commit(store, lessons);
      expect(store.projects.length, 2);
      expect(store.projects.first.title, '课程');
      expect(store.projects.last.parentId, store.projects.first.id);
      expect(store.events.map((e) => e.projectId).toSet().length, 1);
      final before = store.exportJson();
      expect(
        () => CourseImport.commit(store, [
          CourseLesson(title: '错误', start: DateTime(2026), end: DateTime(2025)),
        ]),
        throwsFormatException,
      );
      expect(store.exportJson(), before);
      store.dispose();
    },
  );
  testWidgets('course preview makes no data changes until import', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = FlowStore(FlowData());
    const source =
        '[{"title":"课程预览","start":"2026-09-01T10:00:00","end":"2026-09-01T11:00:00"}]';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => Dialog(
                  child: SizedBox(
                    width: 720,
                    height: 700,
                    child: CourseImportPanel(
                      store: store,
                      initialSource: source,
                      initialFormat: 'json',
                    ),
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览'));
    await tester.pumpAndSettle();
    expect(find.text('课程预览'), findsOneWidget);
    expect(store.events, isEmpty);
    expect(store.projects, isEmpty);
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(store.events.single.title, '课程预览');
    expect(store.projects.first.title, '课程');
    expect(tester.takeException(), isNull);
    store.dispose();
  });
}
