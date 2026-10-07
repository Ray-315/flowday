import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { beforeEach, afterEach, it, expect, vi } from 'vitest';
import { calendarRequest, type AppleCalendar, type AppleEvent } from './appleCalendar';
import { useAppleCalendars, projectAppleEvents, connectedId, type AppleCalendars } from './useAppleCalendars';
vi.mock('@tauri-apps/api/core', () => ({ isTauri: () => true }));
vi.mock('./appleCalendar', async original => ({ ...await original<typeof import('./appleCalendar')>(), calendarRequest: vi.fn() }));
const calendar: AppleCalendar = { id: 'c', title: '工作', account: 'iCloud', writable: true };
const event: AppleEvent = { identifier: 'e', externalId: 'e', occurrence: 1, recurring: false, title: '开会', start: Date.parse('2026-10-07T09:00Z'), end: Date.parse('2026-10-07T10:00Z'), allDay: false, location: '', notes: '', url: '' };
let root: Root, connection: AppleCalendars;
function Harness({ scope = 'guest' }: { scope?: string }) { connection = useAppleCalendars(scope, '2026-10-07'); return null; }
beforeEach(() => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  localStorage.clear();
  root = createRoot(document.createElement('div'));
  vi.mocked(calendarRequest).mockReset();
  vi.mocked(calendarRequest).mockImplementation(async args => {
    if (args.action === 'capability') return { supported: true, authorized: true };
    if (args.action === 'calendars') return { calendars: [calendar] };
    if (args.action === 'read') return { events: [event] };
    return { event };
  });
});
afterEach(async () => { await act(() => root.unmount()); vi.restoreAllMocks(); });
it('refreshes edits and deletions without creating workspace copies, and hides deselected calendars immediately', async () => {
  localStorage.setItem('flowday.apple-connected:guest', '["c"]');
  await act(async () => root.render(<Harness/>));
  expect(connection.events[0]).toMatchObject({ title: '开会', locked: true, appleCalendarTitle: '工作' });
  vi.mocked(calendarRequest).mockImplementation(async args => args.action === 'capability' ? { supported: true, authorized: true } : args.action === 'calendars' ? { calendars: [calendar] } : { events: [] });
  await act(async () => connection.refresh());
  expect(connection.events).toEqual([]);
  await act(async () => connection.select('c', false));
  expect(connection.selected).toEqual([]);
  expect(JSON.parse(localStorage.getItem('flowday.apple-connected:guest')!)).toEqual([]);
});
it('does not request permission on startup, and removes events after permission is revoked', async () => {
  localStorage.setItem('flowday.apple-connected:guest', '["c"]');
  await act(async () => root.render(<Harness/>));
  expect(connection.events).toHaveLength(1);
  vi.mocked(calendarRequest).mockClear().mockResolvedValue({ supported: true, authorized: false });
  await act(async () => connection.refresh());
  expect(connection.events).toEqual([]);
  expect(connection.error).toContain('允许访问');
  expect(vi.mocked(calendarRequest).mock.calls.every(([args]) => args.action === 'capability')).toBe(true);
});
it('ignores stale reads after switching accounts', async () => {
  localStorage.setItem('flowday.apple-connected:guest', '["c"]');
  let finish!: (value: unknown) => void;
  vi.mocked(calendarRequest).mockImplementation(async args => {
    if (args.action === 'capability') return { supported: true, authorized: true };
    if (args.action === 'calendars') return { calendars: [calendar] };
    return new Promise(resolve => { finish = resolve; });
  });
  await act(async () => root.render(<Harness/>));
  await act(async () => root.render(<Harness scope="another-account"/>));
  await act(async () => finish({ events: [event] }));
  expect(connection.events).toEqual([]);
  expect(connection.selected).toEqual([]);
});
it('passes the original version to native writes and keeps read-only calendars immutable', async () => {
  await act(async () => root.render(<Harness/>));
  const local = projectAppleEvents([{ calendar, event }])[0];
  await expect(connection.save({ ...calendar, writable: false }, local, event)).rejects.toThrow('只读');
  vi.mocked(calendarRequest).mockClear();
  await act(async () => connection.save(calendar, { ...local, title: '新标题' }, event));
  expect(calendarRequest).toHaveBeenCalledWith(expect.objectContaining({ action: 'save', calendarId: 'c', expected: event, event: expect.objectContaining({ title: '新标题', url: '' }) }));
});
it('identifies occurrences separately and distinguishes calendars with matching external IDs', () => {
  expect(connectedId('c', event)).not.toBe(connectedId('other', event));
  expect(connectedId('c', { ...event, recurring: true, occurrence: 1 })).not.toBe(connectedId('c', { ...event, recurring: true, occurrence: 2 }));
});
