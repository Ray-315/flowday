import { useState } from 'react';
import { ArrowDown, ArrowUp, ArrowUpRight, Check, Send } from './icons';
import type { Editing } from './App';
import { ToolsDialog } from './Tools';
import {
  activeEvents,
  activeTasks,
  isProjectHidden,
  setEventCompleted,
  setTaskStatus,
  workflowNodes,
} from './domain';
import { dayBounds, dayInZone, zoneFor } from './timezone';
import { saveTask, shiftDay, type Workspace } from './workspace';
import './today-extras.css';

export const todayModules = {
  capture: '快速输入',
  timeline: '今日日程',
  todo: '今日任务',
  calendar: '日历',
  overview: '本日概览',
  workflow: '工作流当前节点',
  overdue: '逾期',
  pressure: '本周压力',
  notices: '通知摘要',
} as const;
export type TodayModule = keyof typeof todayModules;
export const defaultTodayHidden: TodayModule[] = ['workflow', 'overdue', 'pressure', 'notices'];
const moduleIds = Object.keys(todayModules) as TodayModule[];
const isModule = (value: unknown): value is TodayModule =>
  typeof value === 'string' && Object.hasOwn(todayModules, value);
export function todayModuleOrder(data: Workspace): TodayModule[] {
  const setting = data.preferences.todayModuleOrder;
  const order = Array.isArray(setting) ? [...new Set(setting.filter(isModule))] : moduleIds;
  return [...order, ...moduleIds.filter((id) => !order.includes(id))];
}
export function todayHiddenModules(data: Workspace): Set<TodayModule> {
  const setting = data.preferences.todayHiddenModules;
  return new Set(Array.isArray(setting) ? setting.filter(isModule) : defaultTodayHidden);
}
export function isDefaultTodayLayout(data: Workspace): boolean {
  const hidden = todayHiddenModules(data);
  return (
    todayModuleOrder(data).join(',') === moduleIds.join(',') &&
    hidden.size === defaultTodayHidden.length &&
    defaultTodayHidden.every((id) => hidden.has(id))
  );
}
export type Capture = { id: string; text: string; createdAt: string; processed: boolean };
const capturesFor = (data: Workspace) => (Array.isArray(data.captures) ? data.captures : []) as Capture[];
export function saveCapture(data: Workspace, text: string, now = new Date()): Workspace {
  if (!text.trim()) throw new Error('内容不能为空');
  if (text.trim().length > 20000) throw new Error('内容超过长度限制');
  if (capturesFor(data).length >= 10000) throw new Error('记录数量超过限制');
  return {
    ...data,
    captures: [
      ...capturesFor(data),
      { id: crypto.randomUUID(), text: text.trim(), createdAt: now.toISOString(), processed: false },
    ],
  };
}
export function captureToTask(data: Workspace, captureId: string): Workspace {
  const capture = capturesFor(data).find((value) => value.id === captureId);
  if (!capture || capture.processed) throw new Error('记录已处理或不存在');
  const next = saveTask(data, { title: capture.text, priority: 'normal', deadline: null, projectId: null });
  return {
    ...next,
    captures: capturesFor(data).map((value) =>
      value.id === captureId ? { ...value, processed: true } : value,
    ),
  };
}
export function QuickCapture({
  data,
  onSave,
  onParse,
  onEdit,
}: {
  data: Workspace;
  onSave: (data: Workspace) => boolean;
  onParse?: (text: string) => void;
  onEdit?: (editing: Editing) => void;
}) {
  const [text, setText] = useState('');
  const [error, setError] = useState('');
  const pending = capturesFor(data).filter((capture) => !capture.processed);
  function submit() {
    if (!text.trim()) return;
    try {
      if (!onSave(saveCapture(data, text))) throw new Error('保存失败');
      const value = text.trim();
      setText('');
      setError('');
      onParse?.(value);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : '保存失败');
    }
  }
  return (
    <section className="panel today-capture-panel">
      <form
        className="quick-add"
        onSubmit={(event) => {
          event.preventDefault();
          submit();
        }}
      >
        <input
          aria-label="快速输入"
          placeholder="快速记录任务、日程或灵感…"
          value={text}
          onChange={(event) => setText(event.target.value)}
        />
        <button type="submit" aria-label="保存快速输入">
          <Send size={17} />
        </button>
      </form>
      {!!pending.length && (
        <details className="today-captures">
          <summary>记录（{pending.length}）</summary>
          {pending.map((capture) => (
            <div className="today-extra-row" key={capture.id}>
              <span>{capture.text}</span>
              {onParse && (
                <button className="secondary-button" onClick={() => onParse(capture.text)}>
                  分析
                </button>
              )}
              <button
                className="secondary-button"
                onClick={() => {
                  try {
                    const next = captureToTask(data, capture.id);
                    if (!onSave(next)) throw new Error('保存失败');
                    setError('');
                    onEdit?.({ kind: 'task', item: next.tasks[next.tasks.length - 1] });
                  } catch (failure) {
                    setError(failure instanceof Error ? failure.message : '保存失败');
                  }
                }}
              >
                转为任务
              </button>
            </div>
          ))}
        </details>
      )}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </section>
  );
}
export function TodayCustomization({
  data,
  onSave,
  onClose,
}: {
  data: Workspace;
  onSave: (data: Workspace) => boolean;
  onClose: () => void;
}) {
  const [order, setOrder] = useState(() => todayModuleOrder(data));
  const [hidden, setHidden] = useState(() => todayHiddenModules(data));
  const [error, setError] = useState('');
  function move(id: TodayModule, to: number) {
    const next = order.filter((value) => value !== id);
    next.splice(Math.max(0, Math.min(next.length, to)), 0, id);
    setOrder(next);
  }
  return (
    <ToolsDialog title="自定义 Today" onClose={onClose}>
      <div className="today-customization">
        {order.map((id, index) => (
          <div
            className="today-extra-row"
            key={id}
            draggable
            onDragStart={(event) => event.dataTransfer.setData('application/flowday-today-module', id)}
            onDragOver={(event) => event.preventDefault()}
            onDrop={(event) => {
              event.preventDefault();
              const source = event.dataTransfer.getData('application/flowday-today-module');
              if (isModule(source)) move(source, index);
            }}
          >
            <label>
              <input
                type="checkbox"
                checked={!hidden.has(id)}
                onChange={(event) => {
                  const next = new Set(hidden);
                  if (event.target.checked) next.delete(id);
                  else next.add(id);
                  setHidden(next);
                }}
              />
              {todayModules[id]}
            </label>
            <button
              className="icon-button"
              aria-label={`上移${todayModules[id]}`}
              disabled={index === 0}
              onClick={() => move(id, index - 1)}
            >
              <ArrowUp size={15} />
            </button>
            <button
              className="icon-button"
              aria-label={`下移${todayModules[id]}`}
              disabled={index === order.length - 1}
              onClick={() => move(id, index + 1)}
            >
              <ArrowDown size={15} />
            </button>
          </div>
        ))}
      </div>
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      <div className="today-extra-actions">
        <button className="secondary-button" onClick={onClose}>
          取消
        </button>
        <button
          className="primary-button"
          onClick={() => {
            if (
              onSave({
                ...data,
                preferences: {
                  ...data.preferences,
                  todayModuleOrder: order,
                  todayHiddenModules: [...hidden],
                },
              })
            )
              onClose();
            else setError('保存失败');
          }}
        >
          保存
        </button>
      </div>
    </ToolsDialog>
  );
}
export function weekPressure(data: Workspace, day: string) {
  const zone = zoneFor(data);
  const weekday = new Date(`${day}T12:00:00Z`).getUTCDay();
  const first = shiftDay(day, -(data.preferences.weekStartsMonday === false ? weekday : (weekday + 6) % 7));
  const tasks = activeTasks(data).filter((task) => !task.parentId && task.status !== 'cancelled');
  const events = activeEvents(data);
  return Array.from({ length: 7 }, (_, index) => {
    const date = shiftDay(first, index),
      bounds = dayBounds(date, zone);
    const blocks = events.filter(
      (event) => Date.parse(event.start) < bounds.end && Date.parse(event.end) > bounds.start,
    );
    const scheduled = blocks.reduce(
      (sum, event) =>
        sum +
        Math.floor(
          (Math.min(bounds.end, Date.parse(event.end)) - Math.max(bounds.start, Date.parse(event.start))) /
            60000,
        ),
      0,
    );
    const estimated = tasks
      .filter(
        (task) =>
          task.status !== 'done' &&
          !blocks.some((event) => event.taskId === task.id) &&
          [task.plannedStart, task.deadline].some(
            (value) => typeof value === 'string' && dayInZone(new Date(value), zone) === date,
          ),
      )
      .reduce((sum, task) => sum + Number(task.estimateMinutes ?? 60), 0);
    return { day: date, scheduled, estimated };
  });
}
type ExtraModule = Extract<TodayModule, 'workflow' | 'overdue' | 'pressure' | 'notices'>;
export function TodayExtraModule({
  module,
  data,
  day,
  onSave,
  onEdit,
  onNavigate,
  onWorkflow,
  onAcknowledge,
  clock = new Date(),
}: {
  module: ExtraModule;
  data: Workspace;
  day: string;
  onSave: (data: Workspace) => boolean;
  onEdit: (editing: Editing) => void;
  onNavigate?: (page: string) => void;
  onWorkflow?: (projectId: string, nodeId?: string) => void;
  onAcknowledge?: (noticeId: string) => boolean | void | Promise<boolean | void>;
  clock?: Date;
}) {
  const [error, setError] = useState('');
  const zone = zoneFor(data);
  const format = (date: string) =>
    new Date(date).toLocaleString('zh-CN', {
      timeZone: zone,
      month: 'numeric',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  const persist = (next: Workspace) => {
    if (onSave(next)) setError('');
    else setError('保存失败');
  };
  const nodes = workflowNodes(data).filter(
    (node) => ['ready', 'doing', 'waiting'].includes(node.status) && !isProjectHidden(data, node.projectId),
  );
  const tasks = activeTasks(data).filter(
    (task) =>
      !task.parentId &&
      task.status !== 'done' &&
      task.status !== 'cancelled' &&
      task.deadline &&
      Date.parse(task.deadline) < clock.getTime(),
  );
  const events = activeEvents(data).filter(
    (event) => event.taskId && !event.completed && Date.parse(event.end) < clock.getTime(),
  );
  const notices = (Array.isArray(data.notices) ? data.notices : []) as Record<string, unknown>[];
  return (
    <section className="panel today-extra-panel">
      <div className="section-heading">
        <h2>{todayModules[module]}</h2>
        {module === 'notices' && (
          <button className="secondary-button" onClick={() => onNavigate?.('notices')}>
            查看全部
          </button>
        )}
      </div>
      {module === 'workflow' &&
        nodes.map((node) => (
          <div className="today-extra-row" key={node.id}>
            <button
              className="task-body"
              onClick={() => (onWorkflow ? onWorkflow(node.projectId, node.id) : onNavigate?.('workflow'))}
            >
              <span>{node.title}</span>
              <span className="task-meta">
                {data.projects.find((project) => project.id === node.projectId)?.title} ·{' '}
                {
                  { ready: '可开始', doing: '进行中', waiting: '等待' }[
                    node.status as 'ready' | 'doing' | 'waiting'
                  ]
                }
              </span>
            </button>
            <ArrowUpRight size={15} />
          </div>
        ))}
      {module === 'overdue' && (
        <>
          {tasks.map((task) => (
            <div className="today-extra-row" key={task.id}>
              <button className="task-body" onClick={() => onEdit({ kind: 'task', item: task })}>
                <span>{task.title}</span>
                <span className="task-meta">{format(task.deadline!)}</span>
              </button>
              <button
                className="icon-button"
                aria-label={`完成任务：${task.title}`}
                onClick={() => persist(setTaskStatus(data, task.id, 'done', clock))}
              >
                <Check size={17} />
              </button>
            </div>
          ))}
          {events.map((event) => (
            <div className="today-extra-row" key={event.id}>
              <button className="task-body" onClick={() => onEdit({ kind: 'event', item: event })}>
                <span>{event.title}</span>
                <span className="task-meta">
                  {format(event.start)} – {format(event.end)}
                </span>
              </button>
              <button
                className="icon-button"
                aria-label={`完成日程：${event.title}`}
                onClick={() => persist(setEventCompleted(data, event.id, true, clock))}
              >
                <Check size={17} />
              </button>
            </div>
          ))}
        </>
      )}
      {module === 'pressure' &&
        weekPressure(data, day).map((pressure) => (
          <div className="today-pressure" key={pressure.day}>
            <div>
              <span>{pressure.day.slice(5).replace('-', '/')}</span>
              <span>
                日程 {(pressure.scheduled / 60).toFixed(1)}h · 待办 {(pressure.estimated / 60).toFixed(1)}h
              </span>
            </div>
            <meter min="0" max="480" value={pressure.scheduled + pressure.estimated} />
          </div>
        ))}
      {module === 'notices' &&
        notices
          .filter((notice) => !notice.read || !notice.acknowledged)
          .slice(0, 5)
          .map((notice) => (
            <div className="today-extra-row" key={String(notice.id)}>
              <button className="task-body" onClick={() => onNavigate?.('notices')}>
                <span>{String(notice.title ?? '')}</span>
                <span className="task-meta">{String(notice.body ?? '')}</span>
              </button>
              {onAcknowledge && (
                <button
                  className="secondary-button"
                  onClick={async () => {
                    try {
                      if ((await onAcknowledge(String(notice.id))) === false) throw new Error('确认失败');
                      setError('');
                    } catch (failure) {
                      setError(failure instanceof Error ? failure.message : '确认失败');
                    }
                  }}
                >
                  已知晓
                </button>
              )}
            </div>
          ))}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
    </section>
  );
}
