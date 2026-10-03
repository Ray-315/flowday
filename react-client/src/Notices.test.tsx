import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { describe, expect, it, vi } from 'vitest';
import { Notices, applyNoticeAction } from './Notices';
import { dueReminders, recordReminderDelivery, type ReminderReceipts } from './reminders';
import { emptyWorkspace } from './workspace';
const now = new Date('2026-10-03T08:55:00Z');
const data = {
  ...emptyWorkspace(),
  events: [
    {
      id: 'e',
      title: '日程',
      start: '2026-10-03T09:00:00Z',
      end: '2026-10-03T10:00:00Z',
      color: 0xff2680ff,
      reminderRules: [{ leadMinutes: 10 }, { leadMinutes: 5 }],
    },
  ],
  notices: [{ id: 'n1', title: '日程', eventId: 'e', read: false }],
  preferences: { strongReminder: true, reminderInterval: 5, maxReminders: 3 },
};
describe('local notice actions', () => {
  it('reading does not stop strong reminders; acknowledging old delivery stops only its rule', () => {
    const due = dueReminders(data, {}, now);
    const receipts = {
      [due[0].key]: recordReminderDelivery(recordReminderDelivery(undefined, 'n1', now), 'n2', now),
      [due[1].key]: recordReminderDelivery(undefined, 'n3', now),
    };
    const read = applyNoticeAction(data, receipts, 'n1', 'read');
    expect(read.receipts[due[0].key].acknowledged).toBeUndefined();
    const acknowledged = applyNoticeAction(read.data, read.receipts, 'n1', 'ack');
    expect(
      dueReminders(acknowledged.data, acknowledged.receipts, new Date('2026-10-03T09:00:00Z')).map(
        (item) => item.key,
      ),
    ).toEqual([due[1].key]);
    expect((acknowledged.data.notices as { acknowledged: boolean }[])[0].acknowledged).toBe(true);
  });
  it('snooze schedules one more normal reminder without reopening its original repeat chain', () => {
    const taskData = {
      ...emptyWorkspace(),
      tasks: [{ id: 't', title: '任务', deadline: now.toISOString(), status: 'todo', priority: 'normal' }],
      notices: [{ id: 'n', title: '任务', taskId: 't' }],
    };
    const first = dueReminders(taskData, {}, now)[0];
    const receipts = { [first.key]: recordReminderDelivery(undefined, 'n', now) };
    const result = applyNoticeAction(taskData, receipts, 'n', 'snooze', 10, now);
    expect(dueReminders(result.data, result.receipts, new Date('2026-10-03T09:04:00Z'))).toHaveLength(0);
    const delayed = new Date('2026-10-03T09:05:00Z');
    expect(dueReminders(result.data, result.receipts, delayed)).toHaveLength(1);
    result.receipts[first.key] = recordReminderDelivery(result.receipts[first.key], 'delayed', delayed);
    expect(dueReminders(result.data, result.receipts, new Date('2026-10-03T09:10:00Z'))).toHaveLength(0);
    expect(result.data.tasks[0].deadline).toBe(now.toISOString());
  });
  it('start and complete use domain task/event transitions and stop automatic reminders', () => {
    const linked = {
      ...data,
      tasks: [{ id: 't', title: '任务', status: 'todo', priority: 'normal' }],
      events: [{ ...data.events[0], taskId: 't' }],
      notices: [{ id: 'n', title: '任务', taskId: 't', eventId: 'e' }],
    };
    const started = applyNoticeAction(linked, {}, 'n', 'start', 5, now);
    expect(started.data.tasks[0].status).toBe('doing');
    const completed = applyNoticeAction(started.data, started.receipts, 'n', 'complete', 5, now);
    expect(completed.data.events[0].completed).toBe(true);
    expect(completed.data.tasks[0].status).toBe('done');
    expect(dueReminders(completed.data, completed.receipts, now)).toHaveLength(0);
  });
  it('rejects snoozing remote notices without a matching local receipt', () => {
    expect(() => applyNoticeAction(data, {}, 'n1', 'snooze')).toThrow('没有本地提醒记录');
  });
  it('restores account receipts if workspace save fails', async () => {
    Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
    const storageDescriptor = Object.getOwnPropertyDescriptor(window, 'localStorage');
    const storageValues = new Map<string, string>();
    Object.defineProperty(window, 'localStorage', {
      configurable: true,
      value: {
        getItem: (key: string) => storageValues.get(key) ?? null,
        setItem: (key: string, value: string) => storageValues.set(key, value),
        removeItem: (key: string) => storageValues.delete(key),
      },
    });
    const receiptKey = 'test-notice-scope.receipts';
    const receipts: ReminderReceipts = { rule: recordReminderDelivery(undefined, 'n1', now) };
    const original = JSON.stringify(receipts);
    window.localStorage.setItem(receiptKey, original);
    const container = document.createElement('div');
    document.body.append(container);
    const root = createRoot(container);
    try {
      await act(async () =>
        root.render(<Notices data={data} onSave={() => false} onEdit={vi.fn()} receiptKey={receiptKey} />),
      );
      await act(async () =>
        [...container.querySelectorAll('button')].find((button) => button.textContent === '知晓')!.click(),
      );
      expect(window.localStorage.getItem(receiptKey)).toBe(original);
      expect(container.querySelector('[role=alert]')?.textContent).toBe('通知操作未保存');
    } finally {
      await act(async () => root.unmount());
      container.remove();
      window.localStorage.removeItem(receiptKey);
      if (storageDescriptor) Object.defineProperty(window, 'localStorage', storageDescriptor);
    }
  });
});
