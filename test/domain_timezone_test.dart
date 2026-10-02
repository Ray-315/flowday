import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';

void main() {
  test('all persisted instants use explicit UTC and deserialize locally', () {
    final local = DateTime(2026, 10, 1, 9, 30);
    final rule = RepeatRule(frequency: RepeatFrequency.daily, until: local);
    final data = FlowData(
      projects: [
        Project(id: 'p', title: '项目', deadline: local, deletedAt: local),
      ],
      tasks: [
        Task(
          id: 't',
          title: '任务',
          projectId: 'p',
          plannedStart: local,
          occurrenceDate: local,
          deadline: local,
          completedAt: local,
          deletedAt: local,
          repeatRule: rule,
        ),
      ],
      events: [
        CalendarEvent(
          id: 'e',
          title: '日程',
          start: local,
          end: local.add(const Duration(hours: 1)),
          deletedAt: local,
          occurrenceDate: local,
        ),
      ],
      nodes: [
        FlowNode(id: 'n', projectId: 'p', title: '节点', completedAt: local),
      ],
      edges: [
        FlowEdge(
          id: 'edge',
          projectId: 'p',
          sourceId: 'n',
          targetId: 'n',
          availableAt: local,
        ),
      ],
      captures: [Capture(id: 'c', text: '收集', createdAt: local)],
      notices: [
        AppNotice(id: 'notice', title: '通知', body: '', createdAt: local),
      ],
    );
    final json = data.toJson();
    void inspect(dynamic value) {
      if (value is Map) {
        for (final entry in value.entries) {
          if (const [
                'deadline',
                'deletedAt',
                'plannedStart',
                'occurrenceDate',
                'completedAt',
                'start',
                'end',
                'availableAt',
                'createdAt',
                'until',
              ].contains(entry.key) &&
              entry.value != null) {
            expect(entry.value, endsWith('Z'), reason: '${entry.key}');
          }
          inspect(entry.value);
        }
      } else if (value is List) {
        value.forEach(inspect);
      }
    }

    inspect(json);
    final restored = FlowData.fromJson(json);
    expect(restored.events.single.start.isUtc, isFalse);
    expect(restored.events.single.start, local);
    expect(restored.tasks.single.plannedStart, local);
    expect(restored.tasks.single.repeatRule!.until, local);
    expect(restored.captures.single.createdAt, local);
    expect(restored.notices.single.createdAt, local);
  });

  test('offset timestamps preserve the same instant in local model', () {
    final event = CalendarEvent.fromJson({
      'id': 'e',
      'title': '会议',
      'start': '2026-10-01T09:00:00+08:00',
      'end': '2026-10-01T10:00:00+08:00',
    });
    expect(event.start.isAtSameMomentAs(DateTime.utc(2026, 10, 1, 1)), isTrue);
    expect(event.toJson()['start'], '2026-10-01T01:00:00.000Z');
    expect(event.start.isUtc, isFalse);
  });

  test('legacy naive dates retain local wall times and recurrence anchor', () {
    final task = Task.fromJson({
      'id': 't',
      'title': '重复',
      'plannedStart': '2026-01-31T09:15:00',
      'occurrenceDate': '2026-01-31T09:15:00',
      'repeatRule': {'frequency': 'monthly', 'interval': 1, 'count': 3},
    });
    expect(task.plannedStart, DateTime(2026, 1, 31, 9, 15));
    final restored = Task.fromJson(task.toJson());
    final next = restored.repeatRule!.occurrence(restored.occurrenceDate!, 1);
    expect(next, DateTime(2026, 2, 28, 9, 15));
    expect(next.isUtc, isFalse);
  });
}
