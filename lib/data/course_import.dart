import 'dart:convert';
import '../domain/models.dart';
import '../domain/store.dart';

class CourseLesson {
  const CourseLesson({
    required this.title,
    required this.start,
    required this.end,
    this.teacher = '',
    this.location = '',
    this.notes = '',
  });
  final String title, teacher, location, notes;
  final DateTime start, end;
}

class CourseConflict {
  const CourseConflict(this.lesson, this.title);
  final CourseLesson lesson;
  final String title;
}

class CourseImport {
  static const aliases = {
    'title': ['title', 'name', 'course', '课程名', '课程名称', '课程'],
    'teacher': ['teacher', '教师', '老师'],
    'location': ['location', 'room', '地点', '教室'],
    'notes': ['notes', '备注'],
    'start': ['start', '开始时间'],
    'end': ['end', '结束时间'],
    'weekday': ['weekday', 'day', '星期'],
    'startTime': ['starttime', '开始时刻'],
    'endTime': ['endtime', '结束时刻'],
    'startWeek': ['startweek', '起始周', '开始周'],
    'endWeek': ['endweek', '结束周'],
    'parity': ['parity', '单双周'],
  };

  static List<List<String>> csv(String source) {
    final rows = <List<String>>[], row = <String>[];
    var cell = StringBuffer(), quoted = false;
    for (var i = 0; i < source.length; i++) {
      final c = source[i];
      if (c == '"') {
        if (quoted && i + 1 < source.length && source[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (!quoted && (c == ',' || c == '\n' || c == '\r')) {
        row.add(cell.toString());
        cell = StringBuffer();
        if (c != ',') {
          if (row.any((value) => value.trim().isNotEmpty)) {
            rows.add(List.of(row));
          }
          row.clear();
          if (c == '\r' && i + 1 < source.length && source[i + 1] == '\n') i++;
        }
      } else {
        cell.write(c);
      }
    }
    if (quoted) throw const FormatException('CSV 引号未闭合');
    row.add(cell.toString());
    if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
    return rows;
  }

  static List<CourseLesson> parse(
    String source,
    String format, {
    DateTime? semesterStart,
    Map<String, String> mapping = const {},
  }) {
    if (source.length > 5 * 1024 * 1024) {
      throw const FormatException('课程文件超过 5 MB');
    }
    if (format.toLowerCase() == 'ics') return _ics(source);
    List<Map<String, dynamic>> records;
    if (format.toLowerCase() == 'csv') {
      final rows = csv(source.replaceFirst('\ufeff', ''));
      if (rows.length < 2) throw const FormatException('课程文件没有记录');
      final headers = rows.first;
      if (headers.map((h) => h.trim().toLowerCase()).toSet().length !=
          headers.length) {
        throw const FormatException('CSV 列名不能重复');
      }
      records = rows.skip(1).map((row) {
        if (row.length != headers.length) {
          throw const FormatException('CSV 列数不一致');
        }
        return {for (var i = 0; i < headers.length; i++) headers[i]: row[i]};
      }).toList();
    } else if (format.toLowerCase() == 'json') {
      final decoded = jsonDecode(source);
      final values = decoded is Map ? decoded['courses'] : decoded;
      if (values is! List) throw const FormatException('JSON 需要课程数组');
      records = values.map((value) {
        if (value is! Map) throw const FormatException('课程记录格式不正确');
        return Map<String, dynamic>.from(value);
      }).toList();
    } else {
      throw const FormatException('不支持的课程格式');
    }
    final result = <CourseLesson>[];
    for (final record in records) {
      final lower = {
        for (final entry in record.entries)
          entry.key.trim().toLowerCase(): entry.value,
      };
      String field(String key) {
        if (mapping.containsKey(key)) {
          return '${record[mapping[key]] ?? ''}'.trim();
        }
        for (final alias in aliases[key]!) {
          if (lower.containsKey(alias)) return '${lower[alias] ?? ''}'.trim();
        }
        return '';
      }

      final title = field('title');
      if (title.isEmpty) throw const FormatException('课程名称不能为空');
      void add(DateTime start, DateTime end) {
        if (!end.isAfter(start)) throw FormatException('$title：结束时间必须晚于开始时间');
        result.add(
          CourseLesson(
            title: title,
            start: start,
            end: end,
            teacher: field('teacher'),
            location: field('location'),
            notes: field('notes'),
          ),
        );
        if (result.length > 5000) throw const FormatException('课程实例超过 5000 条');
      }

      if (field('start').isNotEmpty) {
        final start = DateTime.tryParse(field('start')),
            end = DateTime.tryParse(field('end'));
        if (start == null || end == null) {
          throw FormatException('$title：日期时间无效');
        }
        add(start, end);
        continue;
      }
      if (semesterStart == null) throw const FormatException('请选择学期第一周开始日期');
      final weekday = _weekday(field('weekday'));
      final first = field('startWeek').isEmpty
              ? 1
              : int.tryParse(field('startWeek')) ?? 0,
          last = int.tryParse(field('endWeek'));
      if (last == null || first < 1 || last < first || last > 60) {
        throw FormatException('$title：周次范围无效');
      }
      final startClock = _clock(field('startTime')),
          endClock = _clock(field('endTime'));
      final parity = field('parity').toLowerCase();
      if (![
        '',
        'all',
        '每周',
        '全部',
        'odd',
        '单',
        '单周',
        'even',
        '双',
        '双周',
      ].contains(parity)) {
        throw FormatException('$title：单双周无效');
      }
      final monday = DateTime(
        semesterStart.year,
        semesterStart.month,
        semesterStart.day - semesterStart.weekday + 1,
      );
      for (var week = first; week <= last; week++) {
        if (['odd', '单', '单周'].contains(parity) && week.isEven ||
            ['even', '双', '双周'].contains(parity) && week.isOdd) {
          continue;
        }
        final day = DateTime(
          monday.year,
          monday.month,
          monday.day + (week - 1) * 7 + weekday - 1,
        );
        add(
          DateTime(day.year, day.month, day.day, startClock.$1, startClock.$2),
          DateTime(day.year, day.month, day.day, endClock.$1, endClock.$2),
        );
      }
    }
    if (result.isEmpty) throw const FormatException('课程文件没有可导入记录');
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  static int _weekday(String value) {
    final names = ['一', '二', '三', '四', '五', '六', '日'];
    final normalized = value
        .replaceAll('星期', '')
        .replaceAll('周', '')
        .replaceAll('天', '日');
    final day = int.tryParse(normalized) ?? names.indexOf(normalized) + 1;
    if (day < 1 || day > 7) throw const FormatException('星期必须为 1 至 7');
    return day;
  }

  static (int, int) _clock(String value) {
    final parts = value.split(':');
    final hour = parts.length == 2 ? int.tryParse(parts[0]) : null,
        minute = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      throw const FormatException('课程时间必须为有效时刻');
    }
    return (hour, minute);
  }

  static List<CourseConflict> conflicts(
    List<CourseLesson> lessons,
    Iterable<CalendarEvent> events,
  ) {
    final result = <CourseConflict>[];
    for (var i = 0; i < lessons.length; i++) {
      final lesson = lessons[i];
      for (final event in events.where((e) => e.deletedAt == null)) {
        if (lesson.start.isBefore(event.end) &&
            lesson.end.isAfter(event.start)) {
          result.add(CourseConflict(lesson, event.title));
        }
      }
      for (final earlier in lessons.take(i)) {
        if (lesson.start.isBefore(earlier.end) &&
            lesson.end.isAfter(earlier.start)) {
          result.add(CourseConflict(lesson, earlier.title));
        }
      }
    }
    return result;
  }

  static void commit(
    FlowStore store,
    List<CourseLesson> lessons, {
    int? reminderLeadMinutes,
  }) {
    final setting = store.data.preferences['courseReminderLeadMinutes'];
    final reminder = reminderLeadMinutes ?? (setting is int ? setting : 15);
    if (reminder < 0 || reminder > 10080) {
      throw const FormatException('提醒提前时间须在 0–10080 分钟之间');
    }
    if (lessons.isEmpty) throw const FormatException('未选择课程');
    final projects = <Project>[], events = <CalendarEvent>[];
    final root =
        store.projects
            .where((p) => p.title == '课程' && p.parentId == null)
            .firstOrNull ??
        Project(id: store.newId(), title: '课程');
    if (!store.data.projects.contains(root)) projects.add(root);
    final courseIds = <String, String>{};
    for (final lesson in lessons) {
      final key = '${lesson.title}\u0000${lesson.teacher}';
      final projectId = courseIds.putIfAbsent(key, () {
        final project = Project(
          id: store.newId(),
          title: lesson.title,
          parentId: root.id,
          description: lesson.teacher,
        );
        projects.add(project);
        return project.id;
      });
      events.add(
        CalendarEvent(
          id: store.newId(),
          title: lesson.title,
          start: lesson.start,
          end: lesson.end,
          projectId: projectId,
          location: lesson.location,
          reminderLeadMinutes: reminder,
          notes: [
            if (lesson.teacher.isNotEmpty) lesson.teacher,
            if (lesson.notes.isNotEmpty) lesson.notes,
          ].join('\n'),
        ),
      );
    }
    final next = FlowData.fromJson(
      jsonDecode(jsonEncode(store.data.toJson())) as Map<String, dynamic>,
    );
    next.projects.addAll(projects);
    next.events.addAll(events);
    next.validate();
    store.data.projects.addAll(projects);
    store.data.events.addAll(events);
    store.changed();
  }

  static DateTime _icsDate(String value, {String? timezone}) {
    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$',
    ).firstMatch(value);
    if (match == null) throw const FormatException('ICS 日期无效');
    final parts = [
      for (var i = 1; i <= 6; i++) int.parse(match.group(i) ?? '0'),
    ];
    if (parts[1] < 1 ||
        parts[1] > 12 ||
        parts[2] < 1 ||
        parts[2] > DateTime(parts[0], parts[1] + 1, 0).day ||
        parts[3] > 23 ||
        parts[4] > 59 ||
        parts[5] > 59) {
      throw const FormatException('ICS 日期无效');
    }
    if (timezone != null && timezone.isNotEmpty && match.group(7) != 'Z') {
      final date = DateTime.utc(
        parts[0],
        parts[1],
        parts[2],
        parts[3],
        parts[4],
        parts[5],
      );
      if (timezone == 'Asia/Shanghai' || timezone == 'Asia/Chongqing') {
        return date.subtract(const Duration(hours: 8)).toLocal();
      }
      if (timezone == 'UTC' || timezone == 'Etc/UTC') return date.toLocal();
      throw FormatException('暂不支持课程时区：$timezone');
    }
    return match.group(7) == 'Z'
        ? DateTime.utc(
            parts[0],
            parts[1],
            parts[2],
            parts[3],
            parts[4],
            parts[5],
          ).toLocal()
        : DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
  }

  static List<CourseLesson> _ics(String source) {
    final lines = source
        .replaceAll(RegExp(r'\r?\n[ \t]'), '')
        .split(RegExp(r'\r?\n'));
    final result = <CourseLesson>[];
    Map<String, String>? record;
    for (final line in lines) {
      if (line == 'BEGIN:VEVENT') {
        record = {};
        continue;
      }
      if (line == 'END:VEVENT' && record != null) {
        final title = record['SUMMARY'] ?? '';
        if (title.trim().isEmpty ||
            record['DTSTART'] == null ||
            record['DTEND'] == null) {
          throw const FormatException('ICS 课程缺少名称或起止时间');
        }
        if (record['RECURRENCE-ID'] != null) {
          throw const FormatException('ICS 调课实例请导出为独立课程');
        }
        if (record['STATUS'] == 'CANCELLED') {
          record = null;
          continue;
        }
        final start = _icsDate(
              record['DTSTART']!,
              timezone: record['_DTSTARTZONE'],
            ),
            end = _icsDate(record['DTEND']!, timezone: record['_DTENDZONE']);
        final rule = {
          for (final part
              in (record['RRULE'] ?? '')
                  .split(';')
                  .where((s) => s.contains('=')))
            part.split('=').first: part.substring(part.indexOf('=') + 1),
        };
        var count = 1, interval = 1;
        DateTime? until;
        if (rule.isNotEmpty) {
          if (rule['FREQ'] != 'WEEKLY' ||
              rule.keys.any(
                (k) => ![
                  'FREQ',
                  'COUNT',
                  'UNTIL',
                  'INTERVAL',
                  'BYDAY',
                ].contains(k),
              )) {
            throw const FormatException('ICS 当前支持每周重复课程');
          }
          count = rule['COUNT'] == null
              ? 5000
              : int.tryParse(rule['COUNT']!) ?? 0;
          interval = int.tryParse(rule['INTERVAL'] ?? '1') ?? 0;
          until = rule['UNTIL'] == null ? null : _icsDate(rule['UNTIL']!);
          if (count < 1 ||
              count > 5000 ||
              interval < 1 ||
              (rule['COUNT'] == null && until == null)) {
            throw const FormatException('ICS 重复课程必须有有效结束范围');
          }
          final dayName = [
            'MO',
            'TU',
            'WE',
            'TH',
            'FR',
            'SA',
            'SU',
          ][start.weekday - 1];
          if (rule['BYDAY'] != null && rule['BYDAY'] != dayName) {
            throw const FormatException('ICS 多星期重复请导出为独立课程');
          }
        }
        final excluded = (record['EXDATE'] ?? '')
            .split(',')
            .where((s) => s.isNotEmpty)
            .map((value) => _icsDate(value, timezone: record!['_EXDATEZONE']))
            .toSet();
        for (var i = 0; i < count; i++) {
          final date = DateTime(
            start.year,
            start.month,
            start.day + i * 7 * interval,
            start.hour,
            start.minute,
            start.second,
          );
          if (until != null && date.isAfter(until)) break;
          if (excluded.contains(date)) continue;
          final finish = date.add(end.difference(start));
          if (!finish.isAfter(date)) {
            throw const FormatException('ICS 课程结束时间无效');
          }
          String unescape(String value) => value
              .replaceAll(r'\n', '\n')
              .replaceAll(r'\,', ',')
              .replaceAll(r'\;', ';')
              .replaceAll(r'\\', '\\');
          result.add(
            CourseLesson(
              title: unescape(title),
              start: date,
              end: finish,
              location: unescape(record['LOCATION'] ?? ''),
              notes: unescape(record['DESCRIPTION'] ?? ''),
            ),
          );
          if (result.length > 5000) {
            throw const FormatException('课程实例超过 5000 条');
          }
        }
        record = null;
      } else if (record != null && line.contains(':')) {
        final separator = line.indexOf(':');
        final key = line.substring(0, separator).split(';').first;
        final value = line.substring(separator + 1);
        final zone = RegExp(
          r'TZID=([^;:]+)',
        ).firstMatch(line.substring(0, separator))?.group(1);
        if (zone != null) record['_${key}ZONE'] = zone;
        record[key] = key == 'EXDATE' && record.containsKey(key)
            ? '${record[key]},$value'
            : value;
      }
    }
    if (record != null || result.isEmpty) {
      throw const FormatException('ICS 课程文件不完整');
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }
}
