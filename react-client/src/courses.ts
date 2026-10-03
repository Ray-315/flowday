import ICAL from 'ical.js';
import { instantInZone } from './timezone';
import { type Workspace, type CalendarEvent, type Project } from './workspace';
export type CourseLesson = {
  title: string;
  start: string;
  end: string;
  teacher: string;
  location: string;
  notes: string;
};
export type CourseChoice = 'keep' | 'skip' | 'replace';
const aliases: Record<string, string[]> = {
  title: ['title', 'name', 'course', '课程名', '课程名称', '课程'],
  teacher: ['teacher', '教师', '老师'],
  location: ['location', 'room', '地点', '教室'],
  notes: ['notes', '备注'],
  start: ['start', '开始时间'],
  end: ['end', '结束时间'],
  weekday: ['weekday', 'day', '星期'],
  startTime: ['starttime', '开始时刻'],
  endTime: ['endtime', '结束时刻'],
  startWeek: ['startweek', '起始周', '开始周'],
  endWeek: ['endweek', '结束周'],
  parity: ['parity', '单双周'],
};
export function parseCSV(source: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [],
    cell = '',
    quoted = false;
  for (let i = 0; i < source.length; i++) {
    const char = source[i];
    if (char === '"') {
      if (quoted && source[i + 1] === '"') {
        cell += '"';
        i++;
      } else quoted = !quoted;
    } else if (!quoted && [',', '\r', '\n'].includes(char)) {
      row.push(cell);
      cell = '';
      if (char !== ',') {
        if (row.some((value) => value.trim())) rows.push(row);
        row = [];
        if (char === '\r' && source[i + 1] === '\n') i++;
      }
    } else cell += char;
  }
  if (quoted) throw new Error('CSV 引号未闭合');
  row.push(cell);
  if (row.some((value) => value.trim())) rows.push(row);
  return rows;
}
export function parseCourses(
  source: string,
  format: string,
  semesterStart?: string,
  mapping: Record<string, string> = {},
  timezone = Intl.DateTimeFormat().resolvedOptions().timeZone,
): CourseLesson[] {
  if (source.length > 5 * 1024 * 1024) throw new Error('课程文件超过 5MB');
  const result: CourseLesson[] = [];
  const add = (record: Omit<CourseLesson, 'start' | 'end'>, start: string, end: string) => {
    if (
      !record.title.trim() ||
      !Number.isFinite(Date.parse(start)) ||
      !Number.isFinite(Date.parse(end)) ||
      Date.parse(end) <= Date.parse(start)
    )
      throw new Error('课程名称或时间无效');
    const normalize = (value: string) =>
      /(?:Z|[+-]\d{2}:?\d{2})$/i.test(value) ? new Date(value).toISOString() : instantInZone(value, timezone);
    result.push({ ...record, start: normalize(start), end: normalize(end) });
    if (result.length > 5000) throw new Error('课程实例超过 5000 条');
  };
  if (format.toLowerCase() === 'ics') {
    const wrapped = source.includes('BEGIN:VCALENDAR')
      ? source
      : 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n' + source + '\r\nEND:VCALENDAR';
    const calendar = new ICAL.Component(ICAL.parse(wrapped));
    const registered: string[] = [];
    try {
      for (const component of calendar.getAllSubcomponents('vtimezone')) {
        const tzid = String(component.getFirstPropertyValue('tzid'));
        ICAL.TimezoneService.register(new ICAL.Timezone({ component, tzid }));
        registered.push(tzid);
      }
      const instant = (value: InstanceType<typeof ICAL.Time>, tzid?: string) => {
        if (value.zone.tzid === 'UTC' || registered.includes(value.zone.tzid))
          return value.toJSDate().toISOString();
        const wall =
          String(value.year).padStart(4, '0') +
          '-' +
          String(value.month).padStart(2, '0') +
          '-' +
          String(value.day).padStart(2, '0') +
          'T' +
          String(value.hour).padStart(2, '0') +
          ':' +
          String(value.minute).padStart(2, '0') +
          ':' +
          String(value.second).padStart(2, '0');
        return instantInZone(wall, tzid || timezone);
      };
      for (const component of calendar.getAllSubcomponents('vevent')) {
        if (component.getFirstPropertyValue('status') === 'CANCELLED') continue;
        const event = new ICAL.Event(component);
        if (component.hasProperty('recurrence-id')) throw new Error('ICS 调课实例请导出为独立课程');
        const rules = component
          .getAllProperties('rrule')
          .map((property) => property.getFirstValue() as InstanceType<typeof ICAL.Recur>);
        if (rules.some((rule) => !rule.count && !rule.until))
          throw new Error('ICS 重复课程必须有有效结束范围');
        if (!component.hasProperty('dtstart') || !component.hasProperty('dtend') || !event.summary)
          throw new Error('ICS 课程缺少名称或起止时间');
        const zone = component.getFirstProperty('dtstart')?.getParameter('tzid') as string | undefined;
        const iterator = event.iterator();
        let iterations = 0;
        for (let occurrence = iterator.next(); occurrence; occurrence = iterator.next()) {
          if (++iterations > 20000) throw new Error('ICS 重复展开超过限制');
          const details = event.getOccurrenceDetails(occurrence);
          add(
            {
              title: event.summary,
              teacher: '',
              location: String(component.getFirstPropertyValue('location') ?? ''),
              notes: String(component.getFirstPropertyValue('description') ?? ''),
            },
            instant(details.startDate, zone),
            instant(details.endDate, zone),
          );
          if (!event.isRecurring()) break;
        }
      }
    } finally {
      for (const id of registered) ICAL.TimezoneService.remove(id);
    }
  } else {
    let records: Record<string, unknown>[];
    if (format.toLowerCase() === 'csv') {
      const [headers, ...rows] = parseCSV(source.replace(/^\ufeff/, ''));
      if (!headers || !rows.length) throw new Error('课程文件没有记录');
      if (new Set(headers.map((header) => header.trim().toLowerCase())).size !== headers.length)
        throw new Error('CSV 列名不能重复');
      records = rows.map((row) => {
        if (row.length !== headers.length) throw new Error('CSV 列数不一致');
        return Object.fromEntries(headers.map((header, index) => [header, row[index]]));
      });
    } else if (format.toLowerCase() === 'json') {
      const decoded: unknown = JSON.parse(source);
      const values = Array.isArray(decoded) ? decoded : (decoded as { courses?: unknown })?.courses;
      if (
        !Array.isArray(values) ||
        values.some((value) => !value || typeof value !== 'object' || Array.isArray(value))
      )
        throw new Error('JSON 需要课程数组');
      records = values as Record<string, unknown>[];
    } else throw new Error('不支持的课程格式');
    for (const record of records) {
      const lower = Object.fromEntries(
        Object.entries(record).map(([key, value]) => [key.trim().toLowerCase(), value]),
      );
      const field = (key: string) =>
        String(
          mapping[key]
            ? (record[mapping[key]] ?? '')
            : (aliases[key].map((alias) => lower[alias]).find((value) => value != null) ?? ''),
        ).trim();
      const course = {
        title: field('title'),
        teacher: field('teacher'),
        location: field('location'),
        notes: field('notes'),
      };
      if (field('start')) {
        add(course, field('start'), field('end'));
        continue;
      }
      if (!semesterStart || !Number.isFinite(Date.parse(semesterStart)))
        throw new Error('请选择学期第一周开始日期');
      const weekdayText = field('weekday')
        .replace(/星期|周/g, '')
        .replace('天', '日');
      const weekday =
        Number(weekdayText) || ['一', '二', '三', '四', '五', '六', '日'].indexOf(weekdayText) + 1;
      const first = Number(field('startWeek') || 1),
        last = Number(field('endWeek'));
      if (
        weekday < 1 ||
        weekday > 7 ||
        !Number.isInteger(first) ||
        !Number.isInteger(last) ||
        first < 1 ||
        last < first ||
        last > 60
      )
        throw new Error('星期或周次范围无效');
      for (const clock of [field('startTime'), field('endTime')])
        if (!/^([01]?\d|2[0-3]):[0-5]\d$/.test(clock)) throw new Error('课程时间必须为有效时刻');
      const parity = field('parity').toLowerCase();
      if (!['', 'all', '每周', '全部', 'odd', '单', '单周', 'even', '双', '双周'].includes(parity))
        throw new Error('单双周无效');
      const monday = new Date(`${semesterStart}T12:00:00`);
      monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7));
      for (let week = first; week <= last; week++) {
        if (
          (['odd', '单', '单周'].includes(parity) && week % 2 === 0) ||
          (['even', '双', '双周'].includes(parity) && week % 2 !== 0)
        )
          continue;
        const day = new Date(monday);
        day.setDate(day.getDate() + (week - 1) * 7 + weekday - 1);
        const date = `${day.getFullYear()}-${String(day.getMonth() + 1).padStart(2, '0')}-${String(day.getDate()).padStart(2, '0')}`;
        add(course, `${date}T${field('startTime')}`, `${date}T${field('endTime')}`);
      }
    }
  }
  if (!result.length) throw new Error('课程文件没有可导入记录');
  return result.sort((a, b) => Date.parse(a.start) - Date.parse(b.start));
}
const overlap = (a: { start: string; end: string }, b: { start: string; end: string }) =>
  Date.parse(a.start) < Date.parse(b.end) && Date.parse(a.end) > Date.parse(b.start);
export function courseConflicts(lessons: CourseLesson[], data: Workspace) {
  return lessons.flatMap((lesson, index) =>
    [
      ...data.events.filter((event) => !event.deletedAt && overlap(lesson, event)),
      ...lessons.slice(0, index).filter((earlier) => overlap(lesson, earlier)),
    ].map((other) => ({ index, title: other.title })),
  );
}
export function importCourses(
  data: Workspace,
  lessons: CourseLesson[],
  choice: CourseChoice,
  reminder = 15,
): Workspace {
  if (!Number.isInteger(reminder) || reminder < 0 || reminder > 10080)
    throw new Error('提醒提前时间须在 0–10080 分钟之间');
  const conflicts = new Set(courseConflicts(lessons, data).map((conflict) => conflict.index));
  const accepted = choice === 'skip' ? lessons.filter((_, index) => !conflicts.has(index)) : lessons;
  if (!accepted.length) return data;
  if (
    choice === 'replace' &&
    data.events.some(
      (event) => !event.deletedAt && event.locked && accepted.some((lesson) => overlap(lesson, event)),
    )
  )
    throw new Error('不能替换锁定日程');
  const projects: Project[] = [...data.projects];
  const root = projects.find(
    (project) => project.title === '课程' && !project.parentId && !project.deletedAt && !project.archived,
  ) ?? {
    id: crypto.randomUUID(),
    title: '课程',
    color: 0xff4b70e8,
    description: '',
    parentId: null,
    archived: false,
    attachments: [],
  };
  if (!projects.includes(root)) projects.push(root);
  const courseIds = new Map<string, string>();
  const events: CalendarEvent[] = accepted.map((lesson) => {
    const key = `${lesson.title}\u0000${lesson.teacher}`;
    let projectId = courseIds.get(key);
    if (!projectId) {
      projectId = crypto.randomUUID();
      projects.push({
        id: projectId,
        title: lesson.title,
        parentId: root.id,
        description: lesson.teacher,
        color: root.color,
        archived: false,
        attachments: [],
      });
      courseIds.set(key, projectId);
    }
    return {
      id: crypto.randomUUID(),
      title: lesson.title,
      start: lesson.start,
      end: lesson.end,
      color: root.color,
      projectId,
      location: lesson.location,
      notes: [lesson.teacher, lesson.notes].filter(Boolean).join('\n'),
      reminderLeadMinutes: reminder,
      completed: false,
      locked: false,
      allDay: false,
      actualMinutes: 0,
      attachments: [],
      tags: [],
    };
  });
  return {
    ...data,
    projects,
    events: [
      ...data.events.map((event) =>
        choice === 'replace' && !event.deletedAt && accepted.some((lesson) => overlap(lesson, event))
          ? { ...event, deletedAt: new Date().toISOString() }
          : event,
      ),
      ...events,
    ],
  };
}
