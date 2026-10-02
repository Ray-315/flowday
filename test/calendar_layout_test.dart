import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/calendar_layout.dart';

void main() {
  CalendarEvent event(String id, int from, int to) => CalendarEvent(
    id: id,
    title: id,
    start: DateTime(2026, 9, 29, from),
    end: DateTime(2026, 9, 29, to),
  );
  test('chain overlaps use stable lanes across entire group', () {
    final positions = calendarLanes([
      event('a', 9, 11),
      event('b', 10, 12),
      event('c', 11, 13),
    ]);
    expect(positions['a'], (lane: 0, count: 2));
    expect(positions['b'], (lane: 1, count: 2));
    expect(positions['c'], (lane: 0, count: 2));
  });
  test(
    'disjoint groups reclaim full width and nested overlaps get three lanes',
    () {
      final positions = calendarLanes([
        event('c', 10, 11),
        event('a', 8, 13),
        event('b', 9, 12),
        event('d', 14, 15),
      ]);
      expect(positions['a']!.count, 3);
      expect(positions['b']!.count, 3);
      expect(positions['c']!.count, 3);
      expect(positions['d'], (lane: 0, count: 1));
    },
  );
}
