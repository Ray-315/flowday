import { Select } from './Select';
import { useEffect, useState } from 'react';
import {
  FlowApi,
  ApiException,
  object,
  rows,
  textField,
  versionField,
  type AuthSession,
  type JsonObject,
  type SyncController,
} from './api';
import type { Workspace } from './workspace';
import './services.css';
import { instantInZone, zoneFor } from './timezone';

export type ServiceSection = 'AI' | '提醒' | '备份' | '附件' | 'Apple 日历' | '飞书';
const serviceNames: Record<ServiceSection, string> = { AI: 'AI 助手', 提醒: '提醒管理', 备份: '云备份', 附件: '附件管理', 'Apple 日历': 'iCloud 日历', 飞书: '飞书通知' };
const serviceDescriptions: Record<ServiceSection, string> = {
  AI: '把想法变成任务与日程。先预览结果，再由你确认应用。',
  提醒: '集中管理提醒时间、重复频率和完成状态。',
  备份: '在 FlowDay 服务器保存工作区快照，需要时恢复到此前的版本。',
  附件: '管理任务与日程相关的文件、链接和笔记。',
  'Apple 日历': '连接 iCloud 日历，双向同步日程；不包含任务和整个工作区。',
  飞书: '将提醒发送到你的飞书机器人。',
};

export type ServicesProps = {
  section?: ServiceSection;
  api: FlowApi;
  session: AuthSession;
  sync: SyncController;
  workspace: Workspace;
  initialText?: string;
  onExport?: (name: string, content: Blob | string) => Promise<void>;
};
type Preview = { previewId: string; baseVersion: number; candidates: JsonObject[]; expiresAt: string };
const displayDate = (value: unknown, zone: string) =>
  typeof value === 'string' ? new Date(value).toLocaleString(undefined, { timeZone: zone }) : '';
const label = (value: unknown) => (typeof value === 'string' ? value : '');
const actionNames: Record<string, string> = {
  todo: '创建任务',
  event: '创建日程',
  todo_update: '修改任务',
  event_update: '修改日程',
  event_delete: '删除日程',
  reminder: '创建提醒',
  reminder_update: '修改提醒',
};
function describe(value: unknown, zone: string) {
  if (value == null) return '';
  const entry = object(value);
  return [
    label(entry.title),
    displayDate(entry.start, zone),
    displayDate(entry.end, zone),
    label(entry.location),
    label(entry.note),
  ]
    .filter(Boolean)
    .join(' · ');
}
function parsePreview(result: JsonObject): Preview {
  const candidates = rows(result.candidates);
  if (!candidates.length) throw new Error('服务器没有返回候选方案');
  for (const candidate of candidates) {
    textField(candidate.id);
    textField(candidate.label);
    rows(object(candidate.intent).actions);
  }
  return {
    previewId: textField(result.previewId),
    baseVersion: versionField(result.baseVersion),
    candidates,
    expiresAt: textField(result.expiresAt),
  };
}
export function Services({ api, session, sync, workspace, onExport, initialText = '', section: tab = 'AI' }: ServicesProps) {
  const zone = zoneFor(workspace);
  const date = (value: unknown) => displayDate(value, zone);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [appliedMessage, setAppliedMessage] = useState('');
  const [applying, setApplying] = useState(false);
  const [items, setItems] = useState<JsonObject[]>([]);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [candidate, setCandidate] = useState(0);
  const [indexes, setIndexes] = useState<number[]>([]);
  const [input, setInput] = useState(initialText);
  const [taskIds, setTaskIds] = useState<string[]>([]);
  const [rangeStart, setRangeStart] = useState('');
  const [rangeEnd, setRangeEnd] = useState('');
  const [replan, setReplan] = useState(false);
  const [excluded, setExcluded] = useState<{ start: string; end: string }[]>([]);
  const [excludeStart, setExcludeStart] = useState('');
  const [excludeEnd, setExcludeEnd] = useState('');
  const [title, setTitle] = useState('');
  const [dueAt, setDueAt] = useState('');
  const [taskId, setTaskId] = useState('');
  const [strong, setStrong] = useState(true);
  const [interval, setInterval] = useState(5);
  const [maximum, setMaximum] = useState(3);
  const [minutes, setMinutes] = useState(10);
  const [signed, setSigned] = useState<{
    token: string;
    title: string;
    action: string;
    minutes: number;
    event?: JsonObject;
  } | null>(null);
  const [restoreAt, setRestoreAt] = useState('');
  const [restore, setRestore] = useState<JsonObject | null>(null);
  const [attachmentOwner, setAttachmentOwner] = useState('');
  const [attachmentKind, setAttachmentKind] = useState('url');
  const [attachmentName, setAttachmentName] = useState('');
  const [attachmentContent, setAttachmentContent] = useState('');
  const [attachmentFile, setAttachmentFile] = useState<File | null>(null);
  const [apple, setApple] = useState<JsonObject>({});
  const [username, setUsername] = useState('');
  const [applePassword, setApplePassword] = useState('');
  const [calendars, setCalendars] = useState<JsonObject[]>([]);
  const [calendarUrl, setCalendarUrl] = useState('');
  const [feishu, setFeishu] = useState(false);
  const [webhook, setWebhook] = useState('');
  const [secret, setSecret] = useState('');
  const [archive, setArchive] = useState<JsonObject | null>(null);
  const call = (method: string, path: string, data?: JsonObject) =>
    api.feature(session.token, method, path, data);
  async function load(active = tab) {
    if (active === '提醒') setItems(rows((await call('GET', '/reminders')).reminders));
    if (active === '备份') setItems(rows((await call('GET', '/backups')).backups));
    if (active === '附件') setItems(rows((await call('GET', '/attachments')).attachments));
    if (active === 'Apple 日历') setApple(await call('GET', '/integrations/apple'));
    if (active === '飞书') setFeishu((await call('GET', '/integrations/feishu')).configured === true);
  }
  async function run(operation: () => Promise<unknown>) {
    if (busy) return;
    setBusy(true);
    setError('');
    setAppliedMessage('');
    try {
      await operation();
    } catch (failure) {
      setError(failure instanceof ApiException && failure.code === 'AI_NOT_CONFIGURED' ? 'AI 分析尚未配置，请联系服务管理员启用。' : failure instanceof Error ? failure.message : typeof failure === 'string' ? failure : '操作失败');
    } finally {
      setBusy(false);
    }
  }
  useEffect(() => {
    setItems([]);
    setError('');
    setPreview(null);
    setRestore(null);
    setSigned(null);
    void run(() => load(tab));
  }, [tab, session.user.id]);
  useEffect(() => {
    setApplePassword('');
    setSecret('');
    setWebhook('');
  }, [session.user.id]);
  function choose(next: number, nextPreview = preview) {
    setCandidate(next);
    const intent = object(nextPreview?.candidates[next]?.intent);
    setIndexes(rows(intent.actions).map((_, index) => index));
  }
  async function makePreview(schedule = false) {
    await sync.sync();
    if (sync.conflict || sync.error || sync.localDirty) throw new Error('请先完成同步或处理版本冲突');
    const timezone = zoneFor(workspace);
    const result = await call(
      'POST',
      schedule ? '/ai/schedule' : '/ai/preview',
      schedule
        ? {
            taskIds,
            start: instantInZone(rangeStart, timezone),
            end: instantInZone(rangeEnd, timezone),
            timezone,
            replan,
            excluded,
          }
        : { text: input, timezone },
    );
    const next = parsePreview(result);
    setPreview(next);
    choose(0, next);
  }
  async function exportData(name: string, content: Blob | string) {
    if (onExport) return onExport(name, content);
    const url = URL.createObjectURL(
      typeof content === 'string' ? new Blob([content], { type: 'application/json' }) : content,
    );
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = name;
    anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  const actions = preview ? rows(object(preview.candidates[candidate]?.intent).actions) : [];
  const createsEvents = indexes.length > 0 && indexes.every(index => actions[index]?.type === 'event');
  return (
    <section className="service-panel" aria-label={serviceNames[tab]}>
      <p className="section-description">{serviceDescriptions[tab]}</p>
      {tab === 'AI' && (
        <>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              void run(() => makePreview());
            }}
          >
            <label>
              想安排什么？
              <textarea placeholder="例如：明天下午三点整理实验结果，预计一小时" required value={input} onChange={(event) => setInput(event.target.value)} />
            </label>
            <button className="primary-button" disabled={busy}>分析并预览</button>
          </form>
          <details className="service-disclosure">
            <summary>自动排程<span>选择待办任务，生成时间安排</span></summary>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              void run(() => makePreview(true));
            }}
          >
            <label>
              排程开始
              <input
                required
                type="datetime-local"
                value={rangeStart}
                onChange={(event) => setRangeStart(event.target.value)}
              />
            </label>
            <label>
              排程结束
              <input
                required
                type="datetime-local"
                value={rangeEnd}
                onChange={(event) => setRangeEnd(event.target.value)}
              />
            </label>
            {workspace.tasks
              .filter((task) => !task.deletedAt && !['done', 'cancelled'].includes(task.status))
              .map((task) => (
                <label className="service-choice" key={task.id}>
                  <input
                    type="checkbox"
                    checked={taskIds.includes(task.id)}
                    onChange={(event) =>
                      setTaskIds(
                        event.target.checked ? [...taskIds, task.id] : taskIds.filter((id) => id !== task.id),
                      )
                    }
                  />
                  {task.title}
                </label>
              ))}
            <label className="service-choice">
              <input type="checkbox" checked={replan} onChange={(event) => setReplan(event.target.checked)} />
              重新安排未完成任务
            </label>
            <button disabled={busy || taskIds.length === 0}>生成排程方案</button>
          </form>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              void run(async () => {
                const start = instantInZone(excludeStart, zone);
                const end = instantInZone(excludeEnd, zone);
                if (Date.parse(end) <= Date.parse(start)) throw new Error('排除结束时间必须晚于开始时间');
                setExcluded([...excluded, { start, end }]);
                setExcludeStart('');
                setExcludeEnd('');
              });
            }}
          >
            <label>
              排除开始
              <input
                type="datetime-local"
                required
                value={excludeStart}
                onChange={(event) => setExcludeStart(event.target.value)}
              />
            </label>
            <label>
              排除结束
              <input
                type="datetime-local"
                required
                value={excludeEnd}
                onChange={(event) => setExcludeEnd(event.target.value)}
              />
            </label>
            <button disabled={busy}>添加排除时段</button>
          </form>
          {excluded.map((range, index) => (
            <div className="service-actions" key={`${range.start}:${index}`}>
              <span>
                {date(range.start)} — {date(range.end)}
              </span>
              <button disabled={busy} onClick={() => setExcluded(excluded.filter((_, row) => row !== index))}>
                移除
              </button>
            </div>
          ))}
          </details>
          {preview && (
            <>
              <p className="section-description">以下是预览，尚未保存。勾选要执行的内容，再点击下方按钮。</p>
              <div className="service-actions">
                {preview.candidates.map((item, index) => (
                  <button
                    key={String(item.id)}
                    disabled={busy}
                    aria-pressed={candidate === index}
                    onClick={() => choose(index)}
                  >
                    {String(item.label)}
                  </button>
                ))}
              </div>
              {actions.map((action, index) => (
                <label className="service-choice" key={index}>
                  <input
                    type="checkbox"
                    aria-label={`选择：${label(action.title) || actionNames[String(action.type)]}`}
                    disabled={busy}
                    checked={indexes.includes(index)}
                    onChange={(event) =>
                      setIndexes(
                        event.target.checked
                          ? [...indexes, index]
                          : indexes.filter((value) => value !== index),
                      )
                    }
                  />
                  {action.type === 'event' ? '日程' : actionNames[String(action.type)] ?? String(action.type)} ·{' '}
                  {label(action.title) ||
                    workspace.tasks.find((task) => task.id === action.id)?.title ||
                    workspace.events.find((event) => event.id === action.id)?.title ||
                    String(action.id ?? '')}
                  {action.start ? ` · ${date(action.start)} — ${date(action.end)}` : ''}
                  {action.dueAt ? ` · ${date(action.dueAt)}` : ''}
                  {action.deadline ? ` · ${date(action.deadline)}` : ''}
                </label>
              ))}
              {indexes.length === 0 && <p role="status">请先勾选至少一项。</p>}
              <button
                className="primary-button"
                disabled={busy || indexes.length === 0 || Date.parse(preview.expiresAt) <= Date.now()}
                onClick={() =>
                  void run(async () => {
                    setApplying(true);
                    try {
                      await sync.remoteMutation((version) => {
                        if (version !== preview.baseVersion) throw new Error('预览已过期，请重新生成');
                        return call('POST', '/ai/apply', {
                          previewId: preview.previewId,
                          baseVersion: preview.baseVersion,
                          candidateId: preview.candidates[candidate].id,
                          actionIndexes: indexes,
                        });
                      });
                      setAppliedMessage(createsEvents ? `已创建 ${indexes.length} 个日程，可在日历中查看。` : `已应用 ${indexes.length} 项更改。`);
                      setPreview(null);
                    } finally {
                      setApplying(false);
                    }
                  })
                }
              >
                {applying ? '正在保存…' : createsEvents ? '创建日程' : '确认应用'}
              </button>
            </>
          )}
        </>
      )}
      {tab === '提醒' && (
        <>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              void run(async () => {
                await call('POST', '/reminders', {
                  title,
                  dueAt: instantInZone(dueAt, zoneFor(workspace)),
                  ...(taskId ? { taskId } : {}),
                  strong,
                  intervalMinutes: interval,
                  maxReminders: maximum,
                });
                setTitle('');
                await load();
              });
            }}
          >
            <label>
              标题
              <input required value={title} onChange={(event) => setTitle(event.target.value)} />
            </label>
            <label>
              提醒时间
              <input
                required
                type="datetime-local"
                value={dueAt}
                onChange={(event) => setDueAt(event.target.value)}
              />
            </label>
            <label>
              任务
              <Select value={taskId} onChange={(event) => setTaskId(event.target.value)}>
                <option value="">无</option>
                {workspace.tasks
                  .filter((task) => !task.deletedAt)
                  .map((task) => (
                    <option key={task.id} value={task.id}>
                      {task.title}
                    </option>
                  ))}
              </Select>
            </label>
            <label className="service-choice">
              <input type="checkbox" checked={strong} onChange={(event) => setStrong(event.target.checked)} />
              强提醒
            </label>
            <label>
              间隔（分钟）
              <input
                type="number"
                min={1}
                max={10080}
                value={interval}
                onChange={(event) => setInterval(Number(event.target.value))}
              />
            </label>
            <label>
              最多次数
              <input
                type="number"
                min={1}
                max={100}
                value={maximum}
                onChange={(event) => setMaximum(Number(event.target.value))}
              />
            </label>
            <button disabled={busy}>创建提醒</button>
          </form>
          <label>
            稍后／推迟（分钟）
            <input
              type="number"
              min={1}
              max={10080}
              value={minutes}
              onChange={(event) => setMinutes(Number(event.target.value))}
            />
          </label>
          {items.map((item) => (
            <div className="service-row" key={String(item.id)}>
              <p>
                {String(item.title)} · {date(item.dueAt)} · {item.acknowledged ? '已确认' : '未确认'}
              </p>
              {Boolean(item.lastError) && <p>{String(item.lastError)}</p>}
              <div className="service-actions">
                {(
                  [
                    ['ack', '确认'],
                    ['start', '开始'],
                    ['complete', '完成'],
                    ['snooze', '稍后提醒'],
                    ['postpone', '推迟日程'],
                  ] as const
                ).map(([action, caption]) => (
                  <button
                    disabled={
                      busy ||
                      (item.acknowledged === true && action === 'ack') ||
                      (['start', 'complete'].includes(action) && !item.taskId) ||
                      (action === 'postpone' && !item.eventId)
                    }
                    key={action}
                    onClick={() =>
                      void run(async () => {
                        if (['start', 'complete', 'postpone'].includes(action)) {
                          await sync.sync();
                          if (sync.error || sync.conflict || sync.localDirty)
                            throw new Error('请先完成同步或处理版本冲突');
                        }
                        const event =
                          action === 'postpone'
                            ? (await api.getWorkspace(session.token)).data.events.find(
                                (event) => event.id === item.eventId,
                              )
                            : undefined;
                        const signedAction = await call(
                          'POST',
                          `/reminders/${encodeURIComponent(String(item.id))}/actions`,
                          { action, ...(['snooze', 'postpone'].includes(action) ? { minutes } : {}) },
                        );
                        setSigned({
                          token: textField(signedAction.token),
                          title: String(item.title),
                          action,
                          minutes,
                          event,
                        });
                      })
                    }
                  >
                    {caption}
                  </button>
                ))}
              </div>
            </div>
          ))}
          {signed && (
            <div className="service-row">
              <p>
                {signed.title} ·{' '}
                {signed.action === 'postpone'
                  ? '推迟日程'
                  : ({ ack: '确认', start: '开始', complete: '完成', snooze: '稍后提醒' }[signed.action] ??
                    signed.action)}
              </p>
              {signed.event && (
                <>
                  <p>
                    {date(signed.event.start)} — {date(signed.event.end)}
                  </p>
                  <p>
                    {date(
                      new Date(Date.parse(String(signed.event.start)) + signed.minutes * 60000).toISOString(),
                    )}{' '}
                    —{' '}
                    {date(
                      new Date(Date.parse(String(signed.event.end)) + signed.minutes * 60000).toISOString(),
                    )}
                  </p>
                </>
              )}
              <div className="service-actions">
                <button
                  disabled={busy}
                  onClick={() =>
                    void run(async () => {
                      if (['start', 'complete', 'postpone'].includes(signed.action))
                        await sync.remoteMutation(() =>
                          api.request('POST', '/reminder-actions', undefined, { token: signed.token }),
                        );
                      else await api.request('POST', '/reminder-actions', undefined, { token: signed.token });
                      setSigned(null);
                      await load();
                    })
                  }
                >
                  确认执行
                </button>
                <button onClick={() => setSigned(null)}>取消</button>
              </div>
            </div>
          )}
        </>
      )}
      {tab === '备份' && (
        <>
          <div className="service-actions">
            <button
              disabled={busy}
              onClick={() =>
                void run(async () => {
                  await sync.sync();
                  if (sync.conflict || sync.error || sync.localDirty) throw new Error('请先完成同步');
                  await call('POST', '/backups');
                  await load();
                })
              }
            >
              立即备份
            </button>
            <button
              disabled={busy}
              onClick={() =>
                void run(async () =>
                  exportData(
                    'flowday-archive.json',
                    JSON.stringify(await call('GET', '/export/archive'), null, 2),
                  ),
                )
              }
            >
              导出完整归档
            </button>
            <button
              disabled={busy}
              onClick={() =>
                void run(async () =>
                  exportData(
                    'flowday-workspace.json',
                    JSON.stringify(await call('GET', '/export/json'), null, 2),
                  ),
                )
              }
            >
              导出 JSON
            </button>
            {['tasks', 'events', 'statistics'].map((collection) => (
              <button
                disabled={busy}
                key={collection}
                onClick={() =>
                  void run(async () =>
                    exportData(
                      `flowday-${collection}.csv`,
                      await api.download(session.token, `/export/csv?collection=${collection}`),
                    ),
                  )
                }
              >
                {{ tasks: '任务', events: '日程', statistics: '统计' }[collection]} CSV
              </button>
            ))}
          </div>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              void run(async () => {
                await sync.sync();
                if (sync.conflict || sync.error || sync.localDirty) throw new Error('请先完成同步');
                setRestore(
                  await call('POST', '/backups/restore-preview', {
                    at: instantInZone(restoreAt, zoneFor(workspace)),
                  }),
                );
              });
            }}
          >
            <label>
              恢复至
              <input
                type="datetime-local"
                required
                value={restoreAt}
                onChange={(event) => setRestoreAt(event.target.value)}
              />
            </label>
            <button disabled={busy}>预览恢复</button>
          </form>
          {restore && (
            <div className="service-row">
              <p>{date(restore.createdAt)}</p>
              {rows(restore.changes).map((change) => (
                <p key={String(change.collection)}>
                  {{
                    projects: '项目',
                    tasks: '任务',
                    events: '日程',
                    nodes: '节点',
                    edges: '连线',
                    captures: '速记',
                    notices: '通知',
                    attachments: '附件',
                  }[String(change.collection)] ?? String(change.collection)}
                  ：{String(change.currentCount)} → {String(change.restoredCount)}，变更{' '}
                  {String(change.changed)}
                </p>
              ))}
              <button
                disabled={busy}
                onClick={() =>
                  void run(async () => {
                    await sync.remoteMutation((baseVersion) => {
                      if (baseVersion !== restore.baseVersion) throw new Error('恢复预览已过期，请重新预览');
                      return call(
                        'POST',
                        `/backups/${encodeURIComponent(String(restore.backupId))}/restore`,
                        { baseVersion },
                      );
                    });
                    setRestore(null);
                    await load();
                  })
                }
              >
                确认恢复
              </button>
            </div>
          )}
          {items.map((item) => (
            <div className="service-row" key={String(item.id)}>
              <p>
                {date(item.createdAt)} · 版本 {String(item.version)} · {String(item.reason)}
              </p>
              <button
                disabled={busy}
                onClick={() =>
                  void run(async () => {
                    await sync.sync();
                    if (sync.conflict || sync.error || sync.localDirty) throw new Error('请先完成同步');
                    setRestore(await call('POST', '/backups/restore-preview', { at: item.createdAt }));
                  })
                }
              >
                预览
              </button>
            </div>
          ))}
          <label>
            导入完整归档
            <input
              type="file"
              accept="application/json,.json"
              onChange={(event) => {
                const file = event.target.files?.[0];
                if (file)
                  void run(async () => {
                    const value = object(JSON.parse(await file.text()));
                    if (value.schemaVersion !== 1 || !Array.isArray(value.attachments))
                      throw new Error('归档格式无效');
                    setArchive(value);
                  });
              }}
            />
          </label>
          {archive && (
            <div className="service-row">
              <p>附件 {rows(archive.attachments).length} 个</p>
              {['tasks', 'projects', 'events'].map((collection) => (
                <p key={collection}>
                  {{ tasks: '任务', projects: '项目', events: '日程' }[collection]}{' '}
                  {rows(object(archive.workspace)[collection]).length} 个
                </p>
              ))}
              <button
                disabled={busy}
                onClick={() => {
                  if (window.confirm('先创建保护备份，再以归档替换工作区及附件？'))
                    void run(async () => {
                      await sync.remoteMutation((baseVersion) =>
                        call('POST', '/import/archive', { baseVersion, archive }),
                      );
                      setArchive(null);
                      await load();
                    });
                }}
              >
                确认导入
              </button>
            </div>
          )}
        </>
      )}
      {tab === '附件' && (
        <>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              void run(async () => {
                const [ownerType, ...ownerParts] = attachmentOwner.split(':');
                const data: JsonObject = {
                  ownerType,
                  ownerId: ownerParts.join(':'),
                  kind: attachmentKind,
                  name: attachmentName,
                };
                if (attachmentKind === 'file') {
                  if (!attachmentFile || attachmentFile.size > 1024 * 1024) throw new Error('文件最大 1 MiB');
                  const bytes = new Uint8Array(await attachmentFile.arrayBuffer());
                  let binary = '';
                  for (const byte of bytes) binary += String.fromCharCode(byte);
                  data.contentBase64 = btoa(binary);
                  data.mediaType = attachmentFile.type || 'application/octet-stream';
                } else data[attachmentKind === 'url' ? 'url' : 'markdown'] = attachmentContent;
                await call('POST', '/attachments', data);
                setAttachmentContent('');
                setAttachmentFile(null);
                await load();
              });
            }}
          >
            <label>
              所属对象
              <Select
                required
                value={attachmentOwner}
                onChange={(event) => setAttachmentOwner(event.target.value)}
              >
                <option value="">选择对象</option>
                {workspace.tasks
                  .filter((item) => !item.deletedAt)
                  .map((item) => (
                    <option value={`task:${item.id}`} key={item.id}>
                      {item.title}
                    </option>
                  ))}
                {workspace.projects
                  .filter((item) => !item.deletedAt)
                  .map((item) => (
                    <option value={`project:${item.id}`} key={item.id}>
                      {item.title}
                    </option>
                  ))}
              </Select>
            </label>
            <label>
              名称
              <input
                required
                value={attachmentName}
                onChange={(event) => setAttachmentName(event.target.value)}
              />
            </label>
            <label>
              类型
              <Select value={attachmentKind} onChange={(event) => setAttachmentKind(event.target.value)}>
                <option value="url">链接</option>
                <option value="markdown">Markdown</option>
                <option value="file">文件</option>
              </Select>
            </label>
            {attachmentKind === 'file' ? (
              <label>
                文件
                <input
                  required
                  type="file"
                  onChange={(event) => setAttachmentFile(event.target.files?.[0] ?? null)}
                />
              </label>
            ) : (
              <label>
                {attachmentKind === 'url' ? '链接' : 'Markdown'}
                <textarea
                  required
                  maxLength={attachmentKind === 'markdown' ? 100000 : undefined}
                  value={attachmentContent}
                  onChange={(event) => setAttachmentContent(event.target.value)}
                />
              </label>
            )}
            <button disabled={busy}>添加附件</button>
          </form>
          {items.map((item) => (
            <div className="service-row" key={String(item.id)}>
              <p>
                {String(item.name)} · {item.deletedAt ? '回收站' : String(item.kind)}
              </p>
              {item.kind === 'url' && /^https?:\/\//i.test(String(item.url)) && (
                <a href={String(item.url)} target="_blank" rel="noreferrer">
                  打开链接
                </a>
              )}
              {item.kind === 'markdown' && <p style={{ whiteSpace: 'pre-wrap' }}>{String(item.markdown)}</p>}
              <div className="service-actions">
                {item.kind === 'file' && !item.deletedAt && (
                  <button
                    disabled={busy}
                    onClick={() =>
                      void run(async () =>
                        exportData(
                          String(item.name),
                          await api.download(
                            session.token,
                            `/attachments/${encodeURIComponent(String(item.id))}/download`,
                          ),
                        ),
                      )
                    }
                  >
                    下载
                  </button>
                )}
                <button
                  disabled={busy}
                  onClick={() =>
                    void run(async () => {
                      await call(
                        'POST',
                        `/attachments/${encodeURIComponent(String(item.id))}/${item.deletedAt ? 'restore' : 'delete'}`,
                      );
                      await load();
                    })
                  }
                >
                  {item.deletedAt ? '恢复' : '删除'}
                </button>
              </div>
            </div>
          ))}
        </>
      )}
      {tab === 'Apple 日历' && (
        <>
          <p>
            {apple.configured ? '已连接' : '未连接'}
            {apple.lastSyncAt ? ` · ${date(apple.lastSyncAt)}` : ''}
          </p>
          {Boolean(apple.lastError) && <p role="alert">{String(apple.lastError)}</p>}
          {!apple.configured && (
            <form
              onSubmit={(event) => {
                event.preventDefault();
                void run(async () => {
                  setCalendars(
                    rows(
                      (
                        await call('POST', '/integrations/apple/discover', {
                          username,
                          password: applePassword,
                        })
                      ).calendars,
                    ),
                  );
                });
              }}
            >
              <label>
                Apple ID
                <input
                  required
                  type="email"
                  value={username}
                  onChange={(event) => setUsername(event.target.value)}
                  autoComplete="username"
                />
              </label>
              <label>
                应用专用密码
                <input
                  required
                  type="password"
                  value={applePassword}
                  onChange={(event) => setApplePassword(event.target.value)}
                  autoComplete="off"
                />
              </label>
              <button disabled={busy}>读取日历</button>
              {calendars.length > 0 && (
                <>
                  <label>
                    日历
                    <Select value={calendarUrl} onChange={(event) => setCalendarUrl(event.target.value)}>
                      <option value="">选择日历</option>
                      {calendars.map((item) => (
                        <option value={String(item.url)} key={String(item.url)}>
                          {String(item.displayName)}
                        </option>
                      ))}
                    </Select>
                  </label>
                  <button
                    type="button"
                    disabled={busy || !calendarUrl}
                    onClick={() =>
                      void run(async () => {
                        await call('PUT', '/integrations/apple', {
                          username,
                          password: applePassword,
                          calendarUrl,
                        });
                        setApplePassword('');
                        setCalendars([]);
                        await load();
                      })
                    }
                  >
                    连接
                  </button>
                </>
              )}
            </form>
          )}
          {apple.configured && (
            <div className="service-actions">
              <button
                disabled={busy}
                onClick={() =>
                  void run(async () => {
                    await sync.remoteMutation(() => call('POST', '/integrations/apple/sync', {}));
                    await load();
                  })
                }
              >
                立即同步
              </button>
              <button
                disabled={busy}
                onClick={() => {
                  if (window.confirm('断开 Apple 日历并保留本地副本？'))
                    void run(async () => {
                      await call('POST', '/integrations/apple/disconnect', { keepLocal: true });
                      await load();
                    });
                }}
              >
                断开
              </button>
            </div>
          )}
          {Array.isArray(apple.records) &&
            rows(apple.records).map((item) => (
              <p key={String(item.eventId)}>
                {workspace.events.find((event) => event.id === item.eventId)?.title ?? String(item.eventId)} ·{' '}
                {item.source === 'apple' ? 'Apple' : '本地'} ·{' '}
                {{ synced: '已同步', pending: '待同步', conflict: '冲突' }[String(item.status)] ??
                  String(item.status)}
              </p>
            ))}
          {Array.isArray(apple.conflicts) &&
            rows(apple.conflicts).map((conflict) => (
              <div className="service-row" key={String(conflict.id)}>
                <div className="service-preview">
                  <div>
                    <h3>本地</h3>
                    <p>{describe(conflict.local, zone)}</p>
                  </div>
                  <div>
                    <h3>Apple</h3>
                    <p>{conflict.remoteDeleted ? '已删除' : describe(conflict.remote, zone)}</p>
                  </div>
                </div>
                <div className="service-actions">
                  {(['local', 'remote'] as const).map((choice) => (
                    <button
                      disabled={busy}
                      key={choice}
                      onClick={() =>
                        void run(async () => {
                          await sync.remoteMutation((baseVersion) =>
                            call(
                              'POST',
                              `/integrations/apple/conflicts/${encodeURIComponent(String(conflict.id))}/resolve`,
                              { choice, baseVersion },
                            ),
                          );
                          await load();
                        })
                      }
                    >
                      {choice === 'local' ? '保留本地' : '保留 Apple'}
                    </button>
                  ))}
                </div>
              </div>
            ))}
        </>
      )}
      {tab === '飞书' && (
        <>
          <p>{feishu ? '已连接' : '未连接'}</p>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              void run(async () => {
                await call('PUT', '/integrations/feishu', {
                  webhookUrl: webhook,
                  ...(secret ? { secret } : {}),
                });
                setWebhook('');
                setSecret('');
                await load();
              });
            }}
          >
            <label>
              机器人 Webhook
              <input
                required
                type="url"
                value={webhook}
                onChange={(event) => setWebhook(event.target.value)}
                autoComplete="off"
              />
            </label>
            <label>
              签名密钥
              <input
                type="password"
                value={secret}
                onChange={(event) => setSecret(event.target.value)}
                autoComplete="off"
              />
            </label>
            <button disabled={busy}>保存</button>
          </form>
          <div className="service-actions">
            <button
              disabled={busy || !feishu}
              onClick={() => void run(() => call('POST', '/integrations/feishu/test'))}
            >
              发送测试
            </button>
            <button
              disabled={busy || !feishu}
              onClick={() =>
                void run(async () => {
                  await call('POST', '/integrations/feishu/disconnect');
                  await load();
                })
              }
            >
              断开
            </button>
          </div>
        </>
      )}
      {appliedMessage && <p role="status">{appliedMessage}</p>}
      {error && <p role="alert">{error}</p>}
    </section>
  );
}
