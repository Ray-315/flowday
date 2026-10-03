import { isTauri } from '@tauri-apps/api/core';
import type { Workspace } from './workspace';
export type Receipt = {
  sentCount: number;
  lastSent: string;
  acknowledged?: boolean;
  snoozedUntil?: string;
  noticeId?: string;
  noticeIds?: string[];
};
export type ReminderReceipts = Record<string, Receipt>;
export function recordReminderDelivery(
  previous: Receipt | undefined,
  noticeId: string,
  now = new Date(),
): Receipt {
  const noticeIds = [
    ...new Set([
      ...(previous?.noticeIds ?? []),
      ...(previous?.noticeId ? [previous.noticeId] : []),
      noticeId,
    ]),
  ];
  return {
    ...previous,
    sentCount: (previous?.sentCount ?? 0) + 1,
    lastSent: now.toISOString(),
    snoozedUntil: undefined,
    noticeId,
    noticeIds,
  };
}
export function readReminderReceipts(source: string | null): ReminderReceipts {
  if (source === null) return {};
  const value: unknown = JSON.parse(source);
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('提醒记录格式无效');
  for (const receipt of Object.values(value)) {
    if (
      !receipt ||
      typeof receipt !== 'object' ||
      !Number.isInteger(receipt.sentCount) ||
      receipt.sentCount < 0 ||
      typeof receipt.lastSent !== 'string' ||
      !Number.isFinite(Date.parse(receipt.lastSent))
    )
      throw new Error('提醒记录格式无效');
    if (
      receipt.snoozedUntil !== undefined &&
      (typeof receipt.snoozedUntil !== 'string' || !Number.isFinite(Date.parse(receipt.snoozedUntil)))
    )
      throw new Error('提醒记录格式无效');
    if (receipt.noticeId !== undefined && typeof receipt.noticeId !== 'string')
      throw new Error('提醒记录格式无效');
    if (
      receipt.noticeIds !== undefined &&
      (!Array.isArray(receipt.noticeIds) || receipt.noticeIds.some((id: unknown) => typeof id !== 'string'))
    )
      throw new Error('提醒记录格式无效');
  }
  return value as ReminderReceipts;
}
export type Reminder = {
  key: string;
  title: string;
  taskId?: string;
  eventId?: string;
  dueAt: string;
  strong: boolean;
  interval: number;
  maximum: number;
};
export function dueReminders(
  data: Workspace,
  receipts: Record<string, Receipt>,
  now = new Date(),
): Reminder[] {
  const candidates: Reminder[] = [];
  const add = (item: Record<string, unknown>, due: number, rule: string, event = false) => {
    const task = event ? data.tasks.find((task) => task.id === item.taskId) : undefined;
    const strong = Boolean(
      item.strongReminder ?? task?.strongReminder ?? data.preferences.strongReminder ?? false,
    );
    const interval = Math.max(
      1,
      Number(item.reminderInterval ?? task?.reminderInterval ?? data.preferences.reminderInterval ?? 5),
    );
    const maximum = strong
      ? Math.min(
          100,
          Math.max(1, Number(item.maxReminders ?? task?.maxReminders ?? data.preferences.maxReminders ?? 3)),
        )
      : 1;
    const key = `${event ? 'event' : 'task'}:${item.id}:${rule}:${due}:${strong}:${interval}:${maximum}`;
    const receipt = receipts[key];
    if (
      !Number.isFinite(due) ||
      now.getTime() < due ||
      receipt?.acknowledged ||
      (!receipt?.snoozedUntil && (receipt?.sentCount ?? 0) >= maximum)
    )
      return;
    if (receipt?.snoozedUntil && now.getTime() < Date.parse(receipt.snoozedUntil)) return;
    if (receipt && !receipt.snoozedUntil && now.getTime() < Date.parse(receipt.lastSent) + interval * 60000)
      return;
    candidates.push({
      key,
      title: String(item.title),
      dueAt: new Date(due).toISOString(),
      strong,
      interval,
      maximum,
      ...(event
        ? { eventId: String(item.id), taskId: typeof item.taskId === 'string' ? item.taskId : undefined }
        : { taskId: String(item.id) }),
    });
  };
  for (const task of data.tasks)
    if (!task.deletedAt && !task.archived && !['done', 'cancelled'].includes(task.status) && task.deadline)
      add(task, Date.parse(task.deadline), 'deadline');
  for (const event of data.events) {
    const task = data.tasks.find((task) => task.id === event.taskId);
    if (
      event.deletedAt ||
      event.completed ||
      task?.status === 'done' ||
      task?.status === 'cancelled' ||
      now.getTime() >= Date.parse(event.end)
    )
      continue;
    const rules = Array.isArray(event.reminderRules)
      ? event.reminderRules
      : [{ leadMinutes: event.reminderLeadMinutes ?? data.preferences.reminderMinutes ?? 10 }];
    for (const raw of rules) {
      const rule = raw as Record<string, unknown>;
      const due =
        typeof rule.dueAt === 'string'
          ? Date.parse(rule.dueAt)
          : Date.parse(event.start) - Number(rule.leadMinutes) * 60000;
      add(event, due, typeof rule.dueAt === 'string' ? `at:${rule.dueAt}` : `lead:${rule.leadMinutes}`, true);
    }
  }
  return candidates;
}
export async function requestNotifications(): Promise<boolean> {
  if (isTauri()) {
    const plugin = await import('@tauri-apps/plugin-notification');
    return (await plugin.isPermissionGranted()) || (await plugin.requestPermission()) === 'granted';
  }
  return (
    'Notification' in window &&
    (Notification.permission === 'granted' || (await Notification.requestPermission()) === 'granted')
  );
}
export async function showNotification(title: string, body: string) {
  if (isTauri()) {
    const plugin = await import('@tauri-apps/plugin-notification');
    if (await plugin.isPermissionGranted()) plugin.sendNotification({ title, body });
  } else if ('Notification' in window && Notification.permission === 'granted')
    new Notification(title, { body });
}
