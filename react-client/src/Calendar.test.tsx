import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { Calendar, MiniCalendar, calendarOverlapGroups } from './Calendar';
import { emptyWorkspace, type Workspace } from './workspace';
let root: Root;
let container: HTMLDivElement;
beforeEach(() => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  container = document.createElement('div');
  document.body.append(container);
  root = createRoot(container);
});
afterEach(async () => {
  await act(() => root.unmount());
  container.remove();
  vi.unstubAllGlobals();
});
it('drops a task into the selected timezone and links its task/project', async () => {
  const data = emptyWorkspace();
  data.preferences.timezone = 'America/New_York';
  data.preferences.calendarView = '日';
  data.tasks = [{ id: 't', title: '拖放任务', status: 'todo', priority: 'normal', estimateMinutes: 45 }];
  let saved: Workspace | undefined;
  await act(() =>
    root.render(
      <Calendar
        data={data}
        day="2026-10-05"
        onDay={() => {}}
        onEdit={() => {}}
        query=""
        clock={new Date('2026-10-05T13:00Z')}
        full
        onSave={(next) => {
          saved = next;
          return true;
        }}
      />,
    ),
  );
  const event = new Event('drop', { bubbles: true, cancelable: true });
  Object.assign(event, {
    clientY: 12,
    dataTransfer: { getData: (type: string) => (type === 'application/flowday-task' ? 't' : '') },
  });
  await act(() => container.querySelector('.timeline')!.dispatchEvent(event));
  expect(saved?.events[0]).toMatchObject({
    taskId: 't',
    title: '拖放任务',
    start: '2026-10-05T12:00:00.000Z',
    end: '2026-10-05T12:45:00.000Z',
  });
  expect(data.events).toHaveLength(0);
});
it('keeps a locked event in place when a drag payload attempts to move it', async () => {
  const data = emptyWorkspace();
  data.preferences.timezone = 'UTC';
  data.preferences.calendarView = '日';
  data.events = [
    {
      id: 'e',
      title: '锁定',
      start: '2026-10-05T09:00Z',
      end: '2026-10-05T10:00Z',
      color: 0xff000000,
      locked: true,
    },
  ];
  const save = vi.fn(() => true);
  await act(() =>
    root.render(
      <Calendar
        data={data}
        day="2026-10-05"
        onDay={() => {}}
        onEdit={() => {}}
        query=""
        clock={new Date('2026-10-05T13:00Z')}
        full
        onSave={save}
      />,
    ),
  );
  const event = new Event('drop', { bubbles: true, cancelable: true });
  Object.assign(event, {
    clientY: 12,
    dataTransfer: { getData: (type: string) => (type === 'application/flowday-event' ? 'e' : '') },
  });
  await act(() => container.querySelector('.timeline')!.dispatchEvent(event));
  expect(save).not.toHaveBeenCalled();
});
it('groups transitive overlaps while leaving adjacent events separate', () => {
  const event = (id: string, start: string, end: string) => ({
    id,
    title: id,
    start: `2026-10-05T${start}Z`,
    end: `2026-10-05T${end}Z`,
    color: 0xff000000,
  });
  expect(
    calendarOverlapGroups([
      event('a', '09:00', '10:00'),
      event('b', '09:30', '10:30'),
      event('c', '10:15', '11:00'),
      event('d', '11:00', '12:00'),
    ]).map((group) => group.map((value) => value.id)),
  ).toEqual([['a', 'b', 'c'], ['d']]);
});
it('reads and saves calendar view while Today ignores the saved full-calendar view', async () => {
  const data = emptyWorkspace();
  data.preferences.calendarView = '周';
  const save = vi.fn(() => true);
  const props = {
    data,
    day: '2026-10-05',
    onDay: () => {},
    onEdit: () => {},
    query: '',
    clock: new Date('2026-10-05T09:00Z'),
    onSave: save,
  };
  await act(() => root.render(<Calendar {...props} full />));
  expect(container.querySelectorAll('.calendar-range-week .calendar-range-day')).toHaveLength(7);
  await act(() =>
    [...container.querySelectorAll('.calendar-view-tabs button')]
      .find((element) => element.textContent === '时间轴')!
      .dispatchEvent(new MouseEvent('click', { bubbles: true })),
  );
  expect(save).toHaveBeenLastCalledWith(
    expect.objectContaining({ preferences: expect.objectContaining({ calendarView: '时间轴' }) }),
  );
  await act(() => root.render(<Calendar {...props} full={false} />));
  expect(container.querySelector('.timeline')).not.toBeNull();
  expect(container.querySelector('.calendar-view-tabs')).toBeNull();
});
it('aggregates overlapping blocks and lets the user open an individual event', async () => {
  HTMLDialogElement.prototype.showModal = vi.fn();
  HTMLDialogElement.prototype.close = vi.fn();
  const data = emptyWorkspace();
  data.preferences = { timezone: 'UTC', calendarView: '日', overlapStyle: '聚合' };
  data.events = [
    { id: 'a', title: '重叠一', start: '2026-10-05T09:00Z', end: '2026-10-05T10:00Z', color: 0xff000000 },
    { id: 'b', title: '重叠二', start: '2026-10-05T09:30Z', end: '2026-10-05T10:30Z', color: 0xff000000 },
  ];
  const edit = vi.fn();
  await act(() =>
    root.render(
      <Calendar
        data={data}
        day="2026-10-05"
        onDay={() => {}}
        onEdit={edit}
        query=""
        clock={new Date('2026-10-05T09:00Z')}
        full
        onSave={() => true}
      />,
    ),
  );
  expect(container.querySelectorAll('.event-block')).toHaveLength(1);
  await act(() => container.querySelector<HTMLButtonElement>('.event-block')!.click());
  await act(() =>
    [...container.querySelectorAll<HTMLButtonElement>('dialog .task-body')]
      .find((button) => button.textContent?.includes('重叠二'))!
      .click(),
  );
  expect(edit).toHaveBeenCalledWith({ kind: 'event', item: data.events[1] });
});
it('MiniCalendar uses Sunday-first headers and cells when configured', async () => {
  await act(() =>
    root.render(<MiniCalendar day="2026-10-05" onDay={() => {}} events={[]} weekStartsMonday={false} />),
  );
  expect(container.querySelector('.weekdays span')?.textContent).toBe('日');
  expect(container.querySelector('.month-grid:not(.weekdays) button')?.getAttribute('aria-label')).toBe(
    '2026-09-27',
  );
});

it('starts a new phone calendar in agenda view with an actionable empty state', async () => {
  vi.stubGlobal('matchMedia', () => ({matches:true}));
  const edit = vi.fn();
  await act(async()=>root.render(<Calendar data={emptyWorkspace()} day="2026-10-05" onDay={()=>{}} onEdit={edit} query="" clock={new Date('2026-10-05T12:00Z')} full/>));
  expect(container.querySelector('.calendar-range-list')).not.toBeNull();
  const add = [...container.querySelectorAll('button')].find(button=>button.textContent==='添加日程')!;
  await act(async()=>add.click());
  expect(edit).toHaveBeenCalledWith({kind:'event'});
});
