import { describe, expect, it } from 'vitest';
import { emptyWorkspace } from './workspace';
import { parseCourses, courseConflicts, importCourses } from './courses';

describe('course import', () => {
  it('parses quoted Chinese CSV and explicit dates', () => {
    const lessons = parseCourses(
      '课程名称,开始时间,结束时间,教室\n"数学,一",2026-10-05T09:00,2026-10-05T10:00,A1',
      'csv',
    );
    expect(lessons[0].title).toBe('数学,一');
    expect(lessons[0].location).toBe('A1');
  });
  it('expands semester weeks with odd parity', () => {
    const lessons = parseCourses(
      '[{"title":"数学","weekday":1,"startTime":"09:00","endTime":"10:00","endWeek":4,"parity":"odd"}]',
      'json',
      '2026-10-05',
    );
    expect(lessons).toHaveLength(2);
    expect(new Date(lessons[1].start).getDate()).toBe(19);
  });
  it('rejects unsupported recurrence rather than silently losing ICS data', () => {
    expect(() =>
      parseCourses(
        'BEGIN:VEVENT\nSUMMARY:数学\nDTSTART:20261005T090000Z\nDTEND:20261005T100000Z\nRRULE:FREQ=WEEKLY\nEND:VEVENT',
        'ics',
      ),
    ).toThrow();
  });
  it('expands bounded weekly ICS and honors EXDATE', () => {
    const lessons = parseCourses(
      'BEGIN:VEVENT\nSUMMARY:数学\nDTSTART:20261005T090000Z\nDTEND:20261005T100000Z\nRRULE:FREQ=WEEKLY;COUNT=3\nEXDATE:20261012T090000Z\nEND:VEVENT',
      'ics',
    );
    expect(lessons).toHaveLength(2);
    expect(lessons[1].start).toBe('2026-10-19T09:00:00.000Z');
  });
  it('expands multiple weekdays in a named timezone', () => {
    const lessons = parseCourses(
      'BEGIN:VEVENT\nUID:test\nSUMMARY:数学\nDTSTART;TZID=America/New_York:20261005T090000\nDTEND;TZID=America/New_York:20261005T100000\nRRULE:FREQ=WEEKLY;COUNT=4;BYDAY=MO,WE\nEND:VEVENT',
      'ics',
    );
    expect(lessons).toHaveLength(4);
    expect(lessons[0].start).toBe('2026-10-05T13:00:00.000Z');
    expect(lessons[1].start).toBe('2026-10-07T13:00:00.000Z');
  });
  it('detects overlaps, supports skip and preserves original workspace', () => {
    const data = emptyWorkspace();
    data.events = [
      { id: 'busy', title: '忙碌', start: '2026-10-05T09:00Z', end: '2026-10-05T10:00Z', color: 0xff000000 },
    ];
    const lessons = parseCourses(
      '[{"title":"数学","start":"2026-10-05T09:30Z","end":"2026-10-05T10:30Z"}]',
      'json',
    );
    expect(courseConflicts(lessons, data)).toHaveLength(1);
    expect(importCourses(data, lessons, 'skip').events).toHaveLength(1);
    const result = importCourses(data, lessons, 'keep');
    expect(result.events).toHaveLength(2);
    expect(result.projects).toHaveLength(2);
    expect(data.projects).toHaveLength(0);
  });
});
