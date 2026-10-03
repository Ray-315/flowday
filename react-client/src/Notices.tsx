import { useState } from 'react';
import type { Editing } from './App';
import type { Workspace } from './workspace';
import { setEventCompleted, setTaskStatus } from './domain';
import { readReminderReceipts, type ReminderReceipts } from './reminders';
import { zoneFor } from './timezone';
export type Notice = Record<string, unknown> & {
  id: string;
  title: string;
  body?: string;
  read?: boolean;
  acknowledged?: boolean;
  taskId?: string | null;
  eventId?: string | null;
  projectId?: string | null;
};
export type NoticeAction = 'read' | 'ack' | 'snooze' | 'start' | 'complete';
const notices = (data: Workspace): Notice[] =>
  Array.isArray(data.notices)
    ? data.notices.filter(
        (item): item is Notice =>
          typeof item === 'object' && item !== null && typeof (item as Notice).id === 'string',
      )
    : [];
export function applyNoticeAction(
  data: Workspace,
  receipts: ReminderReceipts,
  noticeId: string,
  action: NoticeAction,
  minutes = 5,
  now = new Date(),
): { data: Workspace; receipts: ReminderReceipts } {
  const notice = notices(data).find((item) => item.id === noticeId);
  if (!notice) throw new Error('通知已不存在');
  if (action === 'snooze' && (!Number.isInteger(minutes) || minutes < 1 || minutes > 10080))
    throw new Error('稍后提醒分钟数必须为 1–10080');
  const matching = Object.entries(receipts).filter(
    ([, receipt]) => receipt.noticeId === noticeId || receipt.noticeIds?.includes(noticeId),
  );
  if (action === 'snooze' && !matching.length) throw new Error('这条通知没有本地提醒记录');
  const nextReceipts = { ...receipts };
  for (const [key, receipt] of matching) {
    if (action === 'ack' || action === 'complete')
      nextReceipts[key] = { ...receipt, acknowledged: true, snoozedUntil: undefined };
    if (action === 'snooze')
      nextReceipts[key] = {
        ...receipt,
        acknowledged: false,
        snoozedUntil: new Date(now.getTime() + minutes * 60000).toISOString(),
      };
  }
  let next: Workspace = {
    ...data,
    notices: notices(data).map((item) =>
      item.id === noticeId
        ? {
            ...item,
            read: true,
            ...(action === 'ack' || action === 'complete'
              ? { acknowledged: true }
              : action === 'snooze'
                ? { acknowledged: false }
                : {}),
          }
        : item,
    ),
  };
  if (action === 'start') {
    if (!notice.taskId || !data.tasks.some((task) => task.id === notice.taskId && !task.deletedAt))
      throw new Error('通知没有可开始的任务');
    next = setTaskStatus(next, notice.taskId, 'doing', now);
  }
  if (action === 'complete') {
    if (notice.eventId && data.events.some((event) => event.id === notice.eventId && !event.deletedAt))
      next = setEventCompleted(next, notice.eventId, true, now);
    else if (notice.taskId && data.tasks.some((task) => task.id === notice.taskId && !task.deletedAt))
      next = setTaskStatus(next, notice.taskId, 'done', now);
    else throw new Error('通知没有可完成的任务或日程');
  }
  return { data: next, receipts: nextReceipts };
}
export type NoticesProps = {
  data: Workspace;
  onSave: (next: Workspace) => boolean;
  onEdit: (editing: Editing) => void;
  receiptKey: string;
};
export function Notices({ data, onSave, onEdit, receiptKey }: NoticesProps) {
  const [error, setError] = useState('');
  const [minutes, setMinutes] = useState(5);
  function act(notice: Notice, action: NoticeAction) {
    setError('');
    let original: string | null = null;
    let persisted = false;
    try {
      original = window.localStorage.getItem(receiptKey);
      const result = applyNoticeAction(data, readReminderReceipts(original), notice.id, action, minutes);
      window.localStorage.setItem(receiptKey, JSON.stringify(result.receipts));
      persisted = true;
      if (!onSave(result.data)) throw new Error('通知操作未保存');
      return true;
    } catch (failure) {
      if (persisted)
        try {
          if (original === null) window.localStorage.removeItem(receiptKey);
          else window.localStorage.setItem(receiptKey, original);
        } catch {
          setError('无法恢复提醒记录，请检查存储空间');
          return;
        }
      setError(failure instanceof Error ? failure.message : '操作失败');
      return false;
    }
  }
  function open(notice: Notice, kind: Editing['kind']) {
    const item =
      kind === 'task'
        ? data.tasks.find((task) => task.id === notice.taskId && !task.deletedAt)
        : kind === 'event'
          ? data.events.find((event) => event.id === notice.eventId && !event.deletedAt)
          : data.projects.find((project) => project.id === notice.projectId && !project.deletedAt);
    if (item && act(notice, 'read')) onEdit({ kind, item } as Editing);
  }
  let receipts: ReminderReceipts = {};
  try {
    receipts = readReminderReceipts(window.localStorage.getItem(receiptKey));
  } catch {
    /* Action handlers surface unreadable storage without replacing it. */
  }
  return (
    <div className="notice-list">
      <label className="service-choice">
        稍后提醒（分钟）
        <input
          type="number"
          min={1}
          max={10080}
          value={minutes}
          onChange={(event) => setMinutes(Number(event.target.value))}
        />
      </label>
      {notices(data)
        .slice()
        .reverse()
        .map((notice) => {
          const hasReceipt = Object.values(receipts).some(
            (receipt) => receipt.noticeId === notice.id || receipt.noticeIds?.includes(notice.id),
          );
          const task = data.tasks.find((item) => item.id === notice.taskId && !item.deletedAt);
          const event = data.events.find((item) => item.id === notice.eventId && !item.deletedAt);
          return (
            <article className="notice-item" key={notice.id}>
              <h3>{notice.title}</h3>
              <p>{notice.body}</p>
              {typeof notice.createdAt === 'string' && (
                <time dateTime={notice.createdAt}>
                  {new Date(notice.createdAt).toLocaleString(undefined, { timeZone: zoneFor(data) })}
                </time>
              )}
              <div className="notice-actions">
                <button disabled={notice.read} onClick={() => act(notice, 'read')}>
                  {notice.read ? '已读' : '标为已读'}
                </button>
                <button disabled={notice.acknowledged} onClick={() => act(notice, 'ack')}>
                  {notice.acknowledged ? '已知晓' : '知晓'}
                </button>
                {hasReceipt && <button onClick={() => act(notice, 'snooze')}>稍后提醒</button>}
                {task && !['done', 'cancelled'].includes(task.status) && (
                  <button disabled={task.status === 'doing'} onClick={() => act(notice, 'start')}>
                    开始
                  </button>
                )}
                {((event && !event.completed) ||
                  (!event && task && !['done', 'cancelled'].includes(task.status))) && (
                  <button onClick={() => act(notice, 'complete')}>完成</button>
                )}
                {task && <button onClick={() => open(notice, 'task')}>打开任务</button>}
                {event && <button onClick={() => open(notice, 'event')}>打开日程</button>}
                {notice.projectId &&
                  data.projects.some((project) => project.id === notice.projectId && !project.deletedAt) && (
                    <button onClick={() => open(notice, 'project')}>打开项目</button>
                  )}
              </div>
            </article>
          );
        })}
      {error && <p role="alert">{error}</p>}
    </div>
  );
}
