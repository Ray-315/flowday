import { Select } from './Select';
import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { motion } from 'motion/react';
import { isTauri } from '@tauri-apps/api/core';
import { ArrowDownToLine, ArrowUpFromLine, Check, Moon, Sun, Monitor, Trash2, X } from './icons';
import type { Editing } from './App';
import './editor-advanced.css';
import { zoneFor, inputInZone, instantInZone } from './timezone';
import {
  editRecurring,
  materializeRecurring,
  setTaskStatus,
  setEventCompleted,
  trashItem,
  validateProjectParent,
} from './domain';
import {
  hexColor,
  parseWorkspace,
  saveTask,
  type CalendarEvent,
  type Project,
  type Workspace,
} from './workspace';

const colors = [0xff4b70e8, 0xff9878d0, 0xff309b87, 0xffc17c56, 0xffb39447, 0xffc96679];
type Attachment = { id: string; title: string; kind: 'url' | 'markdown' | 'file'; content: string };

export function Modal({
  title,
  onClose,
  children,
  className = '',
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
  className?: string;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current!;
    const opener = document.activeElement;
    dialog.showModal();
    dialog.querySelector<HTMLInputElement>('input:not([type=checkbox]):not([type=file])')?.focus();
    return () => {
      dialog.close();
      if (opener instanceof HTMLElement && opener.isConnected) opener.focus();
    };
  }, []);
  return (
    <motion.dialog
      ref={ref}
      className={`editor-dialog ${className}`}
      aria-label={title}
      onCancel={(event) => {
        event.preventDefault();
        onClose();
      }}
      onClick={(event) => {
        if (event.target === event.currentTarget) {
          const rect = event.currentTarget.getBoundingClientRect();
          if (
            event.clientX < rect.left ||
            event.clientX > rect.right ||
            event.clientY < rect.top ||
            event.clientY > rect.bottom
          )
            onClose();
        }
      }}
      initial={{ opacity: 0, y: 18, scale: 0.98 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      exit={{ opacity: 0, y: 10, scale: 0.99 }}
      transition={{ duration: 0.2, ease: [0.22, 1, 0.36, 1] }}
    >
      <div className="dialog-header">
        <h2>{title}</h2>
        <button className="icon-button" aria-label="关闭" onClick={onClose}>
          <X size={19} />
        </button>
      </div>
      {children}
    </motion.dialog>
  );
}

export function Editor({
  editing,
  data,
  day,
  defaultProject,
  onSave,
  onClose,
}: {
  editing: Editing;
  data: Workspace;
  day: string;
  defaultProject: string | null;
  onSave: (data: Workspace) => boolean;
  onClose: () => void;
}) {
  const zone = zoneFor(data);
  const dateTimeInput = (iso: string) => inputInZone(iso, zone);
  const instant = (wall: string) => instantInZone(wall, zone);
  const item = editing.item;
  const kind = editing.kind;
  const title = kind === 'task' ? '任务' : kind === 'event' ? '日程' : '项目';
  const [name, setName] = useState(item?.title ?? '');
  const [priority, setPriority] = useState(
    kind === 'task' && editing.item ? editing.item.priority : String(data.preferences.defaultTaskPriority ?? 'normal'),
  );
  const [projectId, setProjectId] = useState(
    kind !== 'project' && editing.item ? (editing.item.projectId ?? '') : (defaultProject ?? ''),
  );
  const [deadline, setDeadline] = useState(
    kind !== 'event' && editing.item?.deadline ? dateTimeInput(String(editing.item.deadline)) : '',
  );
  const startingTime =
    kind === 'event' && editing.item
      ? dateTimeInput(editing.item.start)
      : kind === 'event' && editing.start
        ? editing.start
        : `${day}T09:00`;
  const [start, setStart] = useState(startingTime);
  const [end, setEnd] = useState(
    kind === 'event' && editing.item
      ? dateTimeInput(editing.item.end)
      : dateTimeInput(new Date(Date.parse(instant(startingTime)) + Number(data.preferences.defaultEventMinutes ?? 60) * 60_000).toISOString()),
  );
  const [location, setLocation] = useState(
    kind === 'event' && editing.item ? (editing.item.location ?? '') : '',
  );
  const [allDay, setAllDay] = useState(
    kind === 'event' && editing.item ? (editing.item.allDay ?? false) : false,
  );
  const [color, setColor] = useState(kind !== 'task' && editing.item ? editing.item.color : colors[0]);
  const [error, setError] = useState('');
  const [deleting, setDeleting] = useState(false);
  const [advanced, setAdvanced] = useState<Record<string, unknown>>(() => ({
    description: '',
    notes: '',
    status: 'todo',
    difficulty: data.preferences.defaultDifficulty ?? 'normal',
    estimateMinutes: data.preferences.defaultEstimateMinutes ?? 60,
    actualMinutes: 0,
    parentId: null,
    plannedStart: null,
    splittable: true,
    archived: false,
    completed: false,
    locked: false,
    taskId: null,
    tags: [],
    strongReminder: null,
    reminderInterval: null,
    maxReminders: null,
    reminderLeadMinutes: null,
    reminderRules: null,
    ...item,
  }));
  const [attachments, setAttachments] = useState<Attachment[]>(
    () => (item?.attachments as Attachment[] | undefined) ?? [],
  );
  const [attachmentKind, setAttachmentKind] = useState<Attachment['kind']>('url');
  const [attachmentTitle, setAttachmentTitle] = useState('');
  const [attachmentContent, setAttachmentContent] = useState('');
  const initialRepeat = item?.repeatRule as Record<string, unknown> | undefined;
  const [frequency, setFrequency] = useState(String(initialRepeat?.frequency ?? ''));
  const [interval, setInterval] = useState(Number(initialRepeat?.interval ?? 1));
  const [count, setCount] = useState(String(initialRepeat?.count ?? ''));
  const [until, setUntil] = useState(initialRepeat?.until ? dateTimeInput(String(initialRepeat.until)) : '');
  const [scope, setScope] = useState('thisOnly');
  const [subtaskTitle, setSubtaskTitle] = useState('');
  const change = (key: string, value: unknown) => setAdvanced((previous) => ({ ...previous, [key]: value }));
  const fields = (keys: string[]) => Object.fromEntries(keys.map((key) => [key, advanced[key]]));
  function save() {
    setError('');
    try {
      if (!name.trim()) throw new Error(`请输入${title}名称`);
      const repeatRule = frequency
        ? { frequency, interval, count: count ? Number(count) : null, until: until ? instant(until) : null }
        : null;
      if (
        frequency &&
        (!Number.isInteger(interval) ||
          interval < 1 ||
          (count && (!Number.isInteger(Number(count)) || Number(count) < 1)))
      )
        throw new Error('重复间隔及次数必须为正整数');
      if (frequency && kind === 'task' && !deadline && !advanced.plannedStart)
        throw new Error('重复任务需要计划开始或截止时间');
      for (const key of ['estimateMinutes', 'actualMinutes'])
        if (!Number.isInteger(Number(advanced[key])) || Number(advanced[key]) < 0)
          throw new Error('耗时必须为非负整数');
      for (const key of ['reminderInterval', 'maxReminders', 'reminderLeadMinutes']) {
        const value = advanced[key];
        if (
          value != null &&
          (!Number.isInteger(value) ||
            Number(value) < (key === 'reminderLeadMinutes' ? 0 : 1) ||
            Number(value) > (key === 'maxReminders' ? 50 : 10080))
        )
          throw new Error('提醒配置超出允许范围');
      }
      if (Array.isArray(advanced.reminderRules)) {
        const rules = advanced.reminderRules as Record<string, unknown>[];
        const keys = rules.map((rule) =>
          rule.dueAt ? `at:${Date.parse(String(rule.dueAt))}` : `lead:${rule.leadMinutes}`,
        );
        if (
          rules.length > 10 ||
          new Set(keys).size !== rules.length ||
          rules.some((rule) =>
            rule.dueAt
              ? !Number.isFinite(Date.parse(String(rule.dueAt)))
              : !Number.isInteger(rule.leadMinutes) ||
                Number(rule.leadMinutes) < 0 ||
                Number(rule.leadMinutes) > 10080,
          )
        )
          throw new Error('提醒规则无效或重复');
      }
      let next: Workspace;
      if (kind === 'task') {
        next = saveTask(data, {
          id: item?.id || undefined,
          title: name,
          priority,
          deadline: deadline ? instant(deadline) : null,
          projectId: projectId || null,
        });
        const id = item?.id || next.tasks[next.tasks.length - 1].id;
        next = {
          ...next,
          tasks: next.tasks.map((task) =>
            task.id === id
              ? {
                  ...task,
                  ...fields([
                    'description',
                    'status',
                    'difficulty',
                    'estimateMinutes',
                    'actualMinutes',
                    'parentId',
                    'plannedStart',
                    'splittable',
                    'archived',
                    'tags',
                    'strongReminder',
                    'reminderInterval',
                    'maxReminders',
                  ]),
                  attachments,
                  repeatRule,
                  completedAt:
                    advanced.status === 'done' ? (task.completedAt ?? new Date().toISOString()) : null,
                }
              : task,
          ),
        };
      } else if (kind === 'event') {
        if (!start || !end || !Number.isFinite(Date.parse(start)) || !Number.isFinite(Date.parse(end)))
          throw new Error('请输入有效的日程时间');
        if (Date.parse(end) <= Date.parse(start)) throw new Error('结束时间必须晚于开始时间');
        const event: CalendarEvent = {
          id: crypto.randomUUID(),
          notes: '',
          completed: false,
          locked: false,
          actualMinutes: 0,
          tags: [],
          ...item,
          title: name.trim(),
          start: instant(start),
          end: instant(end),
          projectId: projectId || null,
          color,
          location,
          allDay,
          ...fields([
            'notes',
            'completed',
            'locked',
            'actualMinutes',
            'taskId',
            'tags',
            'strongReminder',
            'reminderInterval',
            'maxReminders',
            'reminderLeadMinutes',
            'reminderRules',
          ]),
          attachments,
          repeatRule,
        };
        next = {
          ...data,
          events: item
            ? data.events.map((existing) => (existing.id === item.id ? event : existing))
            : [...data.events, event],
        };
      } else {
        const project: Project = {
          id: crypto.randomUUID(),
          description: '',
          archived: false,
          ...item,
          title: name.trim(),
          color,
          ...fields(['description', 'parentId', 'archived']),
          deadline: deadline ? instant(deadline) : null,
          attachments,
        };
        next = {
          ...data,
          projects: item
            ? data.projects.map((existing) => (existing.id === item.id ? project : existing))
            : [...data.projects, project],
        };
      }
      if (kind !== 'event' && advanced.parentId) {
        const values = kind === 'task' ? next.tasks : next.projects;
        let parent = String(advanced.parentId);
        const ownId = item?.id || values[values.length - 1].id;
        const visited = new Set([ownId]);
        while (parent) {
          if (visited.has(parent)) throw new Error('父级不能形成循环');
          visited.add(parent);
          const ancestor = values.find((value) => value.id === parent);
          if (!ancestor || ancestor.deletedAt) throw new Error('父级不存在');
          parent = String(ancestor.parentId ?? '');
        }
      }
      if (kind === 'project')
        validateProjectParent(
          next,
          item?.id || next.projects[next.projects.length - 1].id,
          advanced.parentId ? String(advanced.parentId) : null,
        );
      if (kind !== 'project') {
        const collection = kind === 'task' ? 'tasks' : 'events';
        const value = item?.id
          ? next[collection].find((entry) => entry.id === item.id)!
          : next[collection][next[collection].length - 1];
        if (kind === 'event') value.completed = item?.completed ?? false;
        if (item?.id) next = editRecurring(data, collection, value, scope as 'thisOnly' | 'thisAndFuture');
        next = materializeRecurring(next, new Date(Date.now() + 366 * 86400000).toISOString());
        if (kind === 'task') next = setTaskStatus(next, value.id, String(advanced.status));
        else next = setEventCompleted(next, value.id, advanced.completed === true);
      }
      if (onSave(next)) onClose();
      else setError('保存失败，请检查可用存储空间。');
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : '保存失败');
    }
  }
  function remove() {
    if (!item?.id) return;
    const key = kind === 'task' ? 'tasks' : kind === 'event' ? 'events' : 'projects';
    const next = trashItem(data, key, item.id, scope as 'thisOnly' | 'thisAndFuture');
    if (onSave(next)) onClose();
    else setError('删除失败');
  }
  return (
    <Modal title={`${item?.id ? '编辑' : '新建'}${title}`} onClose={onClose}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          save();
        }}
      >
        <div className="editor-fields">
          <label className="field">
            <span>{title}名称</span>
            <input required maxLength={300} value={name} onChange={(event) => setName(event.target.value)} />
          </label>
          {kind !== 'project' && (
            <label className="field">
              <span>项目</span>
              <Select value={projectId} onChange={(event) => setProjectId(event.target.value)}>
                <option value="">无项目</option>
                {data.projects
                  .filter((project) => !project.archived && !project.deletedAt)
                  .map((project) => (
                    <option key={project.id} value={project.id}>
                      {project.title}
                    </option>
                  ))}
              </Select>
            </label>
          )}
          {kind === 'task' && (
            <>
              <div className="field">
                <span>优先级</span>
                <div className="choice-group">
                  {[
                    ['low', '低'],
                    ['normal', '普通'],
                    ['high', '高'],
                    ['urgent', '紧急'],
                  ].map(([value, label]) => (
                    <button
                      type="button"
                      key={value}
                      className={priority === value ? 'selected' : ''}
                      aria-pressed={priority === value}
                      onClick={() => setPriority(value)}
                    >
                      {label}
                    </button>
                  ))}
                </div>
              </div>
              <label className="field">
                <span>截止时间</span>
                <input
                  type="datetime-local"
                  value={deadline}
                  onChange={(event) => setDeadline(event.target.value)}
                />
              </label>
            </>
          )}
          {kind === 'event' && (
            <>
              <div className="field-pair">
                <label className="field">
                  <span>开始时间</span>
                  <input
                    required
                    type="datetime-local"
                    value={start}
                    onChange={(event) => setStart(event.target.value)}
                  />
                </label>
                <label className="field">
                  <span>结束时间</span>
                  <input
                    required
                    type="datetime-local"
                    value={end}
                    onChange={(event) => setEnd(event.target.value)}
                  />
                </label>
              </div>
              <label className="field">
                <span>地点</span>
                <input
                  value={location}
                  onChange={(event) => setLocation(event.target.value)}
                  maxLength={200}
                />
              </label>
              <label className="toggle-field">
                <span>全天</span>
                <input
                  type="checkbox"
                  checked={allDay}
                  onChange={(event) => setAllDay(event.target.checked)}
                />
                <span className="toggle" />
              </label>
            </>
          )}
          {kind !== 'task' && (
            <div className="field">
              <span>颜色</span>
              <div className="color-choices">
                {colors.map((value) => (
                  <button
                    type="button"
                    key={value}
                    style={{ '--swatch': hexColor(value) } as CSSProperties}
                    className={color === value ? 'selected' : ''}
                    aria-label={`颜色 ${hexColor(value)}`}
                    aria-pressed={color === value}
                    onClick={() => setColor(value)}
                  >
                    {color === value && <Check size={16} />}
                  </button>
                ))}
              </div>
            </div>
          )}
          <details className="editor-advanced">
            <summary>更多设置</summary>
            <label className="field">
              <span>{kind === 'event' ? '备注' : '描述'}</span>
              <textarea
                value={String(advanced[kind === 'event' ? 'notes' : 'description'] ?? '')}
                onChange={(event) => change(kind === 'event' ? 'notes' : 'description', event.target.value)}
              />
            </label>
            {kind !== 'project' && (
              <label className="field">
                <span>标签</span>
                <input
                  value={(advanced.tags as string[]).join(', ')}
                  onChange={(event) =>
                    change(
                      'tags',
                      event.target.value
                        .split(/[,，]/)
                        .map((tag) => tag.trim())
                        .filter(Boolean),
                    )
                  }
                />
              </label>
            )}
            {kind !== 'event' && (
              <>
                <label className="field">
                  <span>父级{title}</span>
                  <Select
                    value={String(advanced.parentId ?? '')}
                    onChange={(event) => change('parentId', event.target.value || null)}
                  >
                    <option value="">无</option>
                    {(kind === 'task' ? data.tasks : data.projects)
                      .filter((value) => value.id !== item?.id && !value.deletedAt)
                      .map((value) => (
                        <option key={value.id} value={value.id}>
                          {value.title}
                        </option>
                      ))}
                  </Select>
                </label>
                <label className="toggle-field">
                  <span>归档</span>
                  <input
                    type="checkbox"
                    checked={advanced.archived === true}
                    onChange={(event) => change('archived', event.target.checked)}
                  />
                  <span className="toggle" />
                </label>
              </>
            )}
            {kind === 'project' && (
              <label className="field">
                <span>截止时间</span>
                <input
                  type="datetime-local"
                  value={deadline}
                  onChange={(event) => setDeadline(event.target.value)}
                />
              </label>
            )}
            {kind === 'task' && (
              <>
                <div className="field-pair">
                  <label className="field">
                    <span>状态</span>
                    <Select
                      value={String(advanced.status)}
                      onChange={(event) => change('status', event.target.value)}
                    >
                      {[
                        ['todo', '待办'],
                        ['doing', '进行中'],
                        ['waiting', '等待中'],
                        ['done', '已完成'],
                        ['cancelled', '已取消'],
                      ].map(([value, label]) => (
                        <option key={value} value={value}>
                          {label}
                        </option>
                      ))}
                    </Select>
                  </label>
                  <label className="field">
                    <span>难度</span>
                    <Select
                      value={String(advanced.difficulty)}
                      onChange={(event) => change('difficulty', event.target.value)}
                    >
                      {[
                        ['low', '低'],
                        ['normal', '普通'],
                        ['high', '高'],
                      ].map(([value, label]) => (
                        <option key={value} value={value}>
                          {label}
                        </option>
                      ))}
                    </Select>
                  </label>
                </div>
                <label className="field">
                  <span>计划开始</span>
                  <input
                    type="datetime-local"
                    value={advanced.plannedStart ? dateTimeInput(String(advanced.plannedStart)) : ''}
                    onChange={(event) =>
                      change('plannedStart', event.target.value ? instant(event.target.value) : null)
                    }
                  />
                </label>
                <label className="field">
                  <span>预计耗时（分钟）</span>
                  <input
                    type="number"
                    min="0"
                    value={Number(advanced.estimateMinutes)}
                    onChange={(event) => change('estimateMinutes', Number(event.target.value))}
                  />
                </label>
                <label className="toggle-field">
                  <span>允许拆分</span>
                  <input
                    type="checkbox"
                    checked={advanced.splittable === true}
                    onChange={(event) => change('splittable', event.target.checked)}
                  />
                  <span className="toggle" />
                </label>
                {!!item?.id && (
                  <div className="field">
                    <span>子任务</span>
                    {data.tasks
                      .filter((task) => task.parentId === item.id && !task.deletedAt)
                      .map((task) => (
                        <div className="attachment-row" key={task.id}>
                          {task.title}
                        </div>
                      ))}
                    <input
                      aria-label="子任务名称"
                      value={subtaskTitle}
                      onChange={(event) => setSubtaskTitle(event.target.value)}
                    />
                    <button
                      type="button"
                      className="secondary-button"
                      onClick={() => {
                        if (!subtaskTitle.trim()) return;
                        const next = saveTask(data, {
                          title: subtaskTitle,
                          priority,
                          projectId: projectId || null,
                          deadline: null,
                        });
                        const child = next.tasks[next.tasks.length - 1];
                        if (
                          onSave({
                            ...next,
                            tasks: next.tasks.map((task) =>
                              task.id === child.id ? { ...task, parentId: item.id } : task,
                            ),
                          })
                        )
                          setSubtaskTitle('');
                        else setError('保存失败');
                      }}
                    >
                      添加子任务
                    </button>
                  </div>
                )}
              </>
            )}
            {kind !== 'project' && (
              <>
                <label className="field">
                  <span>实际耗时（分钟）</span>
                  <input
                    type="number"
                    min="0"
                    value={Number(advanced.actualMinutes)}
                    onChange={(event) => change('actualMinutes', Number(event.target.value))}
                  />
                </label>
                {kind === 'event' && (
                  <>
                    <label className="field">
                      <span>关联任务</span>
                      <Select
                        value={String(advanced.taskId ?? '')}
                        onChange={(event) => change('taskId', event.target.value || null)}
                      >
                        <option value="">无</option>
                        {data.tasks
                          .filter((task) => !task.deletedAt)
                          .map((task) => (
                            <option key={task.id} value={task.id}>
                              {task.title}
                            </option>
                          ))}
                      </Select>
                    </label>
                    {['completed', 'locked'].map((key) => (
                      <label className="toggle-field" key={key}>
                        <span>{key === 'completed' ? '已完成' : '锁定'}</span>
                        <input
                          type="checkbox"
                          checked={advanced[key] === true}
                          onChange={(event) => change(key, event.target.checked)}
                        />
                        <span className="toggle" />
                      </label>
                    ))}
                  </>
                )}
                <label className="field">
                  <span>重复</span>
                  <Select value={frequency} onChange={(event) => setFrequency(event.target.value)}>
                    {[
                      ['', '不重复'],
                      ['daily', '每天'],
                      ['weekly', '每周'],
                      ['monthly', '每月'],
                      ['yearly', '每年'],
                    ].map(([value, label]) => (
                      <option key={value} value={value}>
                        {label}
                      </option>
                    ))}
                  </Select>
                </label>
                {frequency && (
                  <>
                    <div className="field-pair">
                      <label className="field">
                        <span>间隔</span>
                        <input
                          type="number"
                          min="1"
                          value={interval}
                          onChange={(event) => setInterval(Number(event.target.value))}
                        />
                      </label>
                      <label className="field">
                        <span>次数</span>
                        <input
                          type="number"
                          min="1"
                          value={count}
                          onChange={(event) => setCount(event.target.value)}
                        />
                      </label>
                    </div>
                    <label className="field">
                      <span>重复截止</span>
                      <input
                        type="datetime-local"
                        value={until}
                        onChange={(event) => setUntil(event.target.value)}
                      />
                    </label>
                  </>
                )}
                {!!item?.seriesId && (
                  <label className="field">
                    <span>修改范围</span>
                    <Select value={scope} onChange={(event) => setScope(event.target.value)}>
                      <option value="thisOnly">仅本次</option>
                      <option value="thisAndFuture">本次及以后</option>
                    </Select>
                  </label>
                )}
                <label className="field">
                  <span>强提醒</span>
                  <Select
                    value={advanced.strongReminder == null ? '' : String(advanced.strongReminder)}
                    onChange={(event) =>
                      change(
                        'strongReminder',
                        event.target.value === '' ? null : event.target.value === 'true',
                      )
                    }
                  >
                    <option value="">继承默认</option>
                    <option value="true">开启</option>
                    <option value="false">关闭</option>
                  </Select>
                </label>
                {[
                  'reminderInterval',
                  'maxReminders',
                  ...(kind === 'event' ? ['reminderLeadMinutes'] : []),
                ].map((key) => (
                  <label className="field" key={key}>
                    <span>
                      {
                        (
                          {
                            reminderInterval: '提醒间隔（分钟）',
                            maxReminders: '最大提醒次数',
                            reminderLeadMinutes: '提前提醒（分钟）',
                          } as Record<string, string>
                        )[key]
                      }
                    </span>
                    <input
                      type="number"
                      min={key === 'reminderLeadMinutes' ? 0 : 1}
                      max={key === 'maxReminders' ? 50 : 10080}
                      value={advanced[key] == null ? '' : Number(advanced[key])}
                      onChange={(event) =>
                        change(key, event.target.value === '' ? null : Number(event.target.value))
                      }
                    />
                  </label>
                ))}
                {kind === 'event' && (
                  <>
                    <label className="field">
                      <span>提醒规则</span>
                      <Select
                        value={
                          Array.isArray(advanced.reminderRules)
                            ? advanced.reminderRules.length === 0
                              ? 'off'
                              : 'custom'
                            : 'default'
                        }
                        onChange={(event) =>
                          change(
                            'reminderRules',
                            event.target.value === 'off'
                              ? []
                              : event.target.value === 'custom'
                                ? [{ leadMinutes: 15 }]
                                : null,
                          )
                        }
                      >
                        <option value="default">默认规则</option>
                        <option value="off">关闭</option>
                        <option value="custom">自定义</option>
                      </Select>
                    </label>
                    {Array.isArray(advanced.reminderRules) &&
                      advanced.reminderRules.map((rule: Record<string, unknown>, index: number) => (
                        <div className="field-pair" key={index}>
                          <label className="field">
                            <span>提醒 {index + 1}</span>
                            <Select
                              value={rule.dueAt ? 'absolute' : 'relative'}
                              onChange={(event) =>
                                change(
                                  'reminderRules',
                                  (advanced.reminderRules as Record<string, unknown>[]).map((value, i) =>
                                    i === index
                                      ? event.target.value === 'relative'
                                        ? { leadMinutes: 15 }
                                        : { dueAt: new Date().toISOString() }
                                      : value,
                                  ),
                                )
                              }
                            >
                              <option value="relative">提前分钟</option>
                              <option value="absolute">指定时间</option>
                            </Select>
                          </label>
                          <label className="field">
                            <span>{rule.dueAt ? '时间' : '分钟'}</span>
                            <input
                              type={rule.dueAt ? 'datetime-local' : 'number'}
                              min="0"
                              max="10080"
                              value={
                                rule.dueAt ? dateTimeInput(String(rule.dueAt)) : Number(rule.leadMinutes)
                              }
                              onChange={(event) => {
                                if (rule.dueAt && !event.target.value) return;
                                change(
                                  'reminderRules',
                                  (advanced.reminderRules as Record<string, unknown>[]).map((value, i) =>
                                    i === index
                                      ? rule.dueAt
                                        ? { dueAt: instant(event.target.value) }
                                        : { leadMinutes: Number(event.target.value) }
                                      : value,
                                  ),
                                );
                              }}
                            />
                          </label>
                          <button
                            type="button"
                            className="icon-button"
                            aria-label={`删除提醒 ${index + 1}`}
                            onClick={() =>
                              change(
                                'reminderRules',
                                (advanced.reminderRules as unknown[]).filter((_, i) => i !== index),
                              )
                            }
                          >
                            <Trash2 size={15} />
                          </button>
                        </div>
                      ))}
                    {Array.isArray(advanced.reminderRules) && advanced.reminderRules.length < 10 && (
                      <button
                        type="button"
                        className="secondary-button"
                        onClick={() =>
                          change('reminderRules', [
                            ...(advanced.reminderRules as unknown[]),
                            { leadMinutes: 0 },
                          ])
                        }
                      >
                        添加提醒
                      </button>
                    )}
                  </>
                )}
              </>
            )}
          </details>
          <details className="editor-advanced">
            <summary>附件</summary>
            {attachments.map((attachment) => (
              <div key={attachment.id}>
                <div className="attachment-row">
                  {attachment.kind === 'url' && /^https?:\/\//i.test(attachment.content) ? (
                    <a href={attachment.content} target="_blank" rel="noopener noreferrer">
                      {attachment.title}
                    </a>
                  ) : attachment.kind === 'file' && /^data:[^,]*;base64,/i.test(attachment.content) ? (
                    <a href={attachment.content} download={attachment.title}>
                      {attachment.title}
                    </a>
                  ) : (
                    <span>{attachment.title}</span>
                  )}
                  <button
                    type="button"
                    className="icon-button"
                    aria-label={`删除附件 ${attachment.title}`}
                    onClick={() => setAttachments(attachments.filter((value) => value.id !== attachment.id))}
                  >
                    <Trash2 size={15} />
                  </button>
                </div>
                {attachment.kind === 'markdown' && (
                  <pre className="attachment-markdown">{attachment.content}</pre>
                )}
              </div>
            ))}
            <label className="field">
              <span>类型</span>
              <Select
                value={attachmentKind}
                onChange={(event) => setAttachmentKind(event.target.value as Attachment['kind'])}
              >
                <option value="url">链接</option>
                <option value="markdown">Markdown</option>
                <option value="file">文件</option>
              </Select>
            </label>
            {attachmentKind === 'file' ? (
              <input
                type="file"
                aria-label="添加本地附件"
                onChange={async (event) => {
                  const file = event.target.files?.[0];
                  if (!file) return;
                  if (file.size > 15000) {
                    setError('文件超过内嵌附件容量限制');
                    return;
                  }
                  const reader = new FileReader();
                  reader.onerror = () => setError('无法读取附件');
                  reader.onload = () => {
                    if (String(reader.result).length > 20000) {
                      setError('文件超过内嵌附件容量限制');
                      return;
                    }
                    if (attachments.length >= 100) {
                      setError('附件数量超过限制');
                      return;
                    }
                    setAttachments((values) => [
                      ...values,
                      {
                        id: crypto.randomUUID(),
                        title: file.name,
                        kind: 'file',
                        content: String(reader.result),
                      },
                    ]);
                  };
                  reader.readAsDataURL(file);
                }}
              />
            ) : (
              <>
                <label className="field">
                  <span>名称</span>
                  <input
                    value={attachmentTitle}
                    onChange={(event) => setAttachmentTitle(event.target.value)}
                  />
                </label>
                <label className="field">
                  <span>{attachmentKind === 'url' ? '网址' : '内容'}</span>
                  <textarea
                    value={attachmentContent}
                    onChange={(event) => setAttachmentContent(event.target.value)}
                  />
                </label>
                <button
                  type="button"
                  className="secondary-button"
                  onClick={() => {
                    if (!attachmentTitle.trim() || !attachmentContent.trim()) {
                      setError('请输入附件名称和内容');
                      return;
                    }
                    if (
                      attachmentTitle.length > 20000 ||
                      attachmentContent.length > 20000 ||
                      attachments.length >= 100
                    ) {
                      setError('附件内容或数量超过限制');
                      return;
                    }
                    if (attachmentKind === 'url') {
                      try {
                        const url = new URL(attachmentContent);
                        if (!['https:', 'http:'].includes(url.protocol)) throw new Error();
                      } catch {
                        setError('请输入 HTTP 或 HTTPS 链接');
                        return;
                      }
                    }
                    setAttachments([
                      ...attachments,
                      {
                        id: crypto.randomUUID(),
                        title: attachmentTitle.trim(),
                        kind: attachmentKind,
                        content: attachmentContent,
                      },
                    ]);
                    setAttachmentTitle('');
                    setAttachmentContent('');
                    setError('');
                  }}
                >
                  添加附件
                </button>
              </>
            )}
          </details>
          {error && (
            <p className="form-error" role="alert">
              {error}
            </p>
          )}
          {deleting && (
            <div className="delete-confirm">
              <span>删除此{title}？</span>
              <button type="button" onClick={() => setDeleting(false)}>
                取消
              </button>
              <button type="button" className="danger" onClick={remove}>
                确认删除
              </button>
            </div>
          )}
        </div>
        <div className="dialog-footer">
          {item?.id && (
            <button
              className="delete-button"
              type="button"
              aria-label={`删除${title}`}
              onClick={() => setDeleting(true)}
            >
              <Trash2 size={16} />
            </button>
          )}
          <div />
          <button className="secondary-button" type="button" onClick={onClose}>
            取消
          </button>
          <button className="primary-button" type="submit">
            保存
          </button>
        </div>
      </form>
    </Modal>
  );
}

async function download(source: string, name: string) {
  if (isTauri()) {
    const { save } = await import('@tauri-apps/plugin-dialog');
    const { writeTextFile } = await import('@tauri-apps/plugin-fs');
    const path = await save({ defaultPath: name, filters: [{ name: 'FlowDay 备份', extensions: ['json'] }] });
    if (path) await writeTextFile(path, source);
    return;
  }
  const url = URL.createObjectURL(new Blob([source], { type: 'application/json' }));
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = name;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function Settings({
  data,
  onSave,
  onImport,
  onClose,
  rawBackup,
  embedded = false,
  section = 'all',
}: {
  data: Workspace;
  onSave: (data: Workspace) => boolean;
  onImport: (data: Workspace) => boolean;
  onClose: () => void;
  rawBackup: () => string | null;
  embedded?: boolean;
  section?: 'all' | 'appearance' | 'data';
}) {
  const [error, setError] = useState('');
  const [pending, setPending] = useState<Workspace | null>(null);
  const file = useRef<HTMLInputElement>(null);
  const change = (key: string, value: unknown) => {
    if (!onSave({ ...data, preferences: { ...data.preferences, [key]: value } })) setError('设置保存失败');
  };
  async function selectBackup() {
    if (!isTauri()) {
      file.current?.click();
      return;
    }
    try {
      const { open } = await import('@tauri-apps/plugin-dialog');
      const { readTextFile, stat } = await import('@tauri-apps/plugin-fs');
      const path = await open({
        multiple: false,
        directory: false,
        filters: [{ name: 'FlowDay 备份', extensions: ['json'] }],
      });
      if (!path) return;
      if ((await stat(path)).size > 20 * 1024 * 1024) throw new Error('备份不能超过 20MB');
      setPending(parseWorkspace(await readTextFile(path)));
      setError('');
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : '无法读取备份');
    }
  }
  const contents = (
      <div className="settings-body">
        {section !== 'data' && <>
        <div className="field">
          <span>外观</span>
          <div className="theme-choices">
            <button
              className={!data.preferences.themeMode||data.preferences.themeMode==='light' ? 'selected' : ''}
              aria-pressed={!data.preferences.themeMode||data.preferences.themeMode==='light'}
              onClick={() => change('themeMode', 'light')}
            >
              <Sun size={20} />
              浅色
            </button>
            <button
              className={data.preferences.themeMode === 'dark' ? 'selected' : ''}
              aria-pressed={data.preferences.themeMode === 'dark'}
              onClick={() => change('themeMode', 'dark')}
            >
              <Moon size={20} />
              深色
            </button>
            <button className={data.preferences.themeMode==='system'?'selected':''} aria-pressed={data.preferences.themeMode==='system'} onClick={()=>change('themeMode','system')}><Monitor size={20}/>系统</button>
          </div>
        </div>
        <label className="toggle-field">
          <span>减少动态效果</span>
          <input
            type="checkbox"
            checked={data.preferences.reduceMotion === true}
            onChange={(event) => change('reduceMotion', event.target.checked)}
          />
          <span className="toggle" />
        </label>
        </>}
        {section !== 'appearance' && <>
        <div className="backup-actions">
          <button
            className="secondary-button"
            onClick={async () => {
              try {
                await download(
                  rawBackup() ?? JSON.stringify(data, null, 2),
                  `flowday-${new Date().toISOString().slice(0, 10)}.json`,
                );
              } catch {
                setError('导出失败，请检查目标文件权限。');
              }
            }}
          >
            <ArrowDownToLine size={17} />
            导出备份
          </button>
          <button className="secondary-button" onClick={selectBackup}>
            <ArrowUpFromLine size={17} />
            导入备份
          </button>
        </div>
        <input
          ref={file}
          type="file"
          accept=".json,application/json"
          hidden
          onChange={async (event) => {
            const selected = event.currentTarget.files?.[0];
            event.currentTarget.value = '';
            if (!selected) return;
            try {
              if (selected.size > 20 * 1024 * 1024) throw new Error('备份不能超过 20MB');
              setPending(parseWorkspace(await selected.text()));
              setError('');
            } catch (failure) {
              setError(failure instanceof Error ? failure.message : '无法读取备份');
            }
          }}
        />
        {pending && (
          <div className="import-confirm">
            <p>
              导入 {pending.tasks.length} 个任务、{pending.events.length} 个日程？当前数据将被替换。
            </p>
            <div>
              <button className="secondary-button" onClick={() => setPending(null)}>
                取消
              </button>
              <button
                className="primary-button"
                onClick={() => {
                  if (onImport(pending)) {
                    setPending(null);
                    onClose();
                  } else setError('导入失败');
                }}
              >
                确认导入
              </button>
            </div>
          </div>
        )}
        </>}
        {error && (
          <p className="form-error" role="alert">
            {error}
          </p>
        )}
      </div>
  );
  return embedded ? contents : <Modal title="设置" onClose={onClose} className="settings-dialog">{contents}</Modal>;
}
