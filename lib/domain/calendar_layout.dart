import 'models.dart';

Map<String, ({int lane, int count})> calendarLanes(List<CalendarEvent> events) {
  final sorted = [...events]..sort((a, b) => a.start.compareTo(b.start));
  final result = <String, ({int lane, int count})>{};
  final group = <CalendarEvent>[];
  DateTime? groupEnd;
  void layout() {
    final ends = <DateTime>[];
    final lanes = <String, int>{};
    for (final event in group) {
      var lane = ends.indexWhere((end) => !end.isAfter(event.start));
      if (lane == -1) {
        lane = ends.length;
        ends.add(event.end);
      } else {
        ends[lane] = event.end;
      }
      lanes[event.id] = lane;
    }
    for (final event in group) {
      result[event.id] = (lane: lanes[event.id]!, count: ends.length);
    }
    group.clear();
  }

  for (final event in sorted) {
    if (groupEnd != null && !event.start.isBefore(groupEnd)) {
      layout();
      groupEnd = null;
    }
    group.add(event);
    if (groupEnd == null || event.end.isAfter(groupEnd)) {
      groupEnd = event.end;
    }
  }
  layout();
  return result;
}
