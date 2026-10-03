export type Task = Record<string, unknown> & {
  id: string;
  title: string;
  status: string;
  priority: string;
  tags?: string[];
  deadline?: string | null;
  projectId?: string | null;
  completedAt?: string | null;
  deletedAt?: string | null;
  archived?: boolean;
};
export type CalendarEvent = Record<string, unknown> & {
  id: string;
  title: string;
  start: string;
  end: string;
  color: number;
  projectId?: string | null;
  location?: string;
  deletedAt?: string | null;
  allDay?: boolean;
};
export type Project = Record<string, unknown> & {
  id: string;
  title: string;
  color: number;
  archived?: boolean;
  deletedAt?: string | null;
};
export type Workspace = Record<string, unknown> & {
  schemaVersion: number;
  tasks: Task[];
  events: CalendarEvent[];
  projects: Project[];
  nodes: unknown[];
  preferences: Record<string, unknown>;
};
export type TaskInput = {
  id?: string;
  title: string;
  priority: string;
  deadline: string | null;
  projectId: string | null;
};
export function emptyWorkspace(): Workspace {
  return {
    schemaVersion: 1,
    tasks: [],
    events: [],
    projects: [],
    nodes: [],
    edges: [],
    captures: [],
    notices: [],
    preferences: {},
  };
}
const statuses = ['todo', 'doing', 'waiting', 'done', 'cancelled'];
const priorities = ['low', 'normal', 'high', 'urgent'];
const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);
const validDate = (value: unknown) =>
  typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(value) && Number.isFinite(Date.parse(value));

export function parseWorkspace(source: string): Workspace {
  const value: unknown = JSON.parse(source);
  if (!isRecord(value) || value.schemaVersion !== 1) throw new Error('不支持的备份版本');
  type Row = Record<string, unknown>;
  type Validator = (value: unknown) => boolean;
  const check = (valid: boolean, message = '备份数据字段无效') => {
    if (!valid) throw new Error(message);
  };
  const string: Validator = (x) => typeof x === 'string' && x.length <= 20000;
  const text: Validator = (x) => string(x) && Boolean((x as string).trim());
  const id: Validator = (x) => text(x) && (x as string).length <= 128;
  const integer: Validator = (x) => typeof x === 'number' && Number.isSafeInteger(x) && x >= 0;
  const boolean: Validator = (x) => typeof x === 'boolean';
  const one =
    (values: string[]): Validator =>
    (x) =>
      typeof x === 'string' && values.includes(x);
  const nullable =
    (validate: Validator): Validator =>
    (x) =>
      x === null || validate(x);
  const range =
    (minimum: number, maximum: number): Validator =>
    (x) =>
      integer(x) && (x as number) >= minimum && (x as number) <= maximum;
  const rule: Validator = (x) => {
    if (!isRecord(x)) return false;
    if (x.frequency === undefined) x.frequency = 'daily';
    if (x.interval === undefined) x.interval = 1;
    return (
      one(['daily', 'weekly', 'monthly', 'yearly'])(x.frequency) &&
      range(1, 366)(x.interval) &&
      (x.count === undefined || nullable(range(1, 1000))(x.count)) &&
      (x.until === undefined || nullable(validDate)(x.until))
    );
  };
  const attachments: Validator = (x) => {
    if (!Array.isArray(x) || x.length > 100) return false;
    const seen = new Set<string>();
    return x.every((a) => {
      if (!isRecord(a) || !id(a.id) || !text(a.title) || seen.has(a.id as string)) return false;
      seen.add(a.id as string);
      if (a.kind === undefined) a.kind = 'url';
      if (a.content === undefined) a.content = '';
      return one(['file', 'url', 'markdown'])(a.kind) && string(a.content);
    });
  };
  const reminderRules: Validator = (x) => {
    if (!Array.isArray(x) || x.length > 10) return false;
    const seen = new Set<string>();
    return x.every((r) => {
      if (!isRecord(r) || (r.leadMinutes !== undefined) === (r.dueAt !== undefined)) return false;
      const lead = r.leadMinutes !== undefined;
      if (!(lead ? range(0, 10080)(r.leadMinutes) : validDate(r.dueAt))) return false;
      const key = lead ? `lead:${r.leadMinutes}` : `at:${Date.parse(String(r.dueAt))}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  };
  const common = { id, title: text, description: string, deletedAt: nullable(validDate) };
  const recurring = {
    repeatRule: nullable(rule),
    seriesId: nullable(id),
    occurrenceDate: nullable(validDate),
    attachments,
    strongReminder: nullable(boolean),
    reminderInterval: nullable(range(1, 10080)),
    maxReminders: nullable(range(1, 50)),
  };
  const schemas: Record<string, Record<string, Validator>> = {
    projects: {
      ...common,
      parentId: nullable(id),
      color: integer,
      deadline: nullable(validDate),
      archived: boolean,
      attachments,
    },
    tasks: {
      ...common,
      ...recurring,
      projectId: nullable(id),
      parentId: nullable(id),
      status: one(statuses),
      priority: one(priorities),
      difficulty: one(['low', 'normal', 'high']),
      archived: boolean,
      plannedStart: nullable(validDate),
      estimateMinutes: integer,
      actualMinutes: integer,
      deadline: nullable(validDate),
      completedAt: nullable(validDate),
      splittable: boolean,
      tags: (x) => Array.isArray(x) && x.length <= 100 && x.every(string),
    },
    events: {
      ...recurring,
      id,
      title: text,
      start: validDate,
      end: validDate,
      projectId: nullable(id),
      taskId: nullable(id),
      color: integer,
      location: string,
      notes: string,
      completed: boolean,
      locked: boolean,
      allDay: boolean,
      deletedAt: nullable(validDate),
      actualMinutes: integer,
      reminderLeadMinutes: nullable(range(0, 10080)),
      reminderRules: nullable(reminderRules),
      tags: (x) => Array.isArray(x) && x.length <= 100 && x.every(string),
    },
    nodes: {
      id,
      projectId: id,
      title: text,
      description: string,
      kind: one(['task', 'condition', 'delay', 'milestone', 'note', 'link', 'group']),
      status: one(['locked', 'ready', 'doing', 'waiting', 'done', 'skipped']),
      taskId: nullable(id),
      x: Number.isFinite,
      y: Number.isFinite,
      anyPredecessor: boolean,
      groupId: nullable(id),
      targetProjectId: nullable(id),
      selectedBranchEdgeId: nullable(id),
      collapsed: boolean,
      completedAt: nullable(validDate),
      delayWaiting: boolean,
    },
    edges: {
      id,
      projectId: id,
      sourceId: id,
      targetId: id,
      label: string,
      active: boolean,
      delayMinutes: integer,
      availableAt: nullable(validDate),
    },
    captures: { id, text, createdAt: validDate, processed: boolean },
    notices: {
      id,
      title: text,
      body: string,
      createdAt: validDate,
      read: boolean,
      acknowledged: boolean,
      taskId: nullable(id),
      type: nullable(one(['reminder', 'calendar_conflict', 'workflow', 'ai', 'system'])),
      eventId: nullable(id),
      projectId: nullable(id),
      nodeId: nullable(id),
    },
  };
  const maps: Record<string, Map<string, Row>> = {};
  for (const key of ['tasks', 'events', 'projects', 'nodes', 'edges', 'captures', 'notices']) {
    if (!Array.isArray(value[key]) || value[key].length > 10000) throw new Error('备份数据格式不正确');
    const map = (maps[key] = new Map<string, Row>());
    const ids = new Set<string>();
    for (const item of value[key]) {
      if (!isRecord(item) || typeof item.id !== 'string' || !item.id.trim() || ids.has(item.id))
        throw new Error('备份中存在无效或重复标识');
      ids.add(item.id);
      check(id(item.id), '备份标识无效');
      const required =
        key === 'captures'
          ? ['text', 'createdAt']
          : key === 'edges'
            ? ['projectId', 'sourceId', 'targetId']
            : key === 'notices'
              ? ['title', 'body', 'createdAt']
              : key === 'nodes'
                ? ['title', 'projectId']
                : key === 'events'
                  ? ['title', 'start', 'end']
                  : ['title'];
      check(
        required.every((field) => Object.hasOwn(item, field)),
        '备份缺少必要字段',
      );
      if (key === 'tasks') {
        if (item.status === undefined) item.status = 'todo';
        if (item.priority === undefined) item.priority = 'normal';
      }
      if (['events', 'projects'].includes(key) && item.color === undefined) item.color = 0xff2680ff;
      for (const [field, fieldValue] of Object.entries(item))
        if (schemas[key][field]) check(schemas[key][field](fieldValue), `备份中的 ${key}.${field} 无效`);
      map.set(item.id, item);
      if (
        ['tasks', 'events', 'projects'].includes(key) &&
        (typeof item.title !== 'string' || !item.title.trim())
      )
        throw new Error('备份中存在无效名称');
      if (
        key === 'tasks' &&
        (!statuses.includes(String(item.status)) || !priorities.includes(String(item.priority)))
      )
        throw new Error('备份中的任务状态无效');
      if (key === 'tasks' && item.deadline != null && !validDate(item.deadline))
        throw new Error('备份中的任务日期无效');
      if (
        key === 'events' &&
        (!validDate(item.start) ||
          !validDate(item.end) ||
          Date.parse(String(item.end)) <= Date.parse(String(item.start)))
      )
        throw new Error('备份中的日程时间无效');
      if (
        ['events', 'projects'].includes(key) &&
        (typeof item.color !== 'number' || !Number.isInteger(item.color))
      )
        throw new Error('备份中的颜色无效');
    }
  }
  const ref = (item: Row, field: string, collection: string) => {
    if (item[field] != null) check(maps[collection].has(item[field] as string), '关联对象不存在');
  };
  for (const [collection, map] of Object.entries(maps))
    for (const item of map.values()) {
      for (const [field, target] of [
        ['projectId', 'projects'],
        ['taskId', 'tasks'],
        ['eventId', 'events'],
        ['nodeId', 'nodes'],
      ] as const)
        if (schemas[collection][field]) ref(item, field, target);
      if (collection === 'projects' || collection === 'tasks') ref(item, 'parentId', collection);
      if (collection === 'nodes') {
        ref(item, 'groupId', 'nodes');
        ref(item, 'targetProjectId', 'projects');
        ref(item, 'selectedBranchEdgeId', 'edges');
        if (item.groupId != null) {
          const group = maps.nodes.get(item.groupId as string)!;
          check(group.kind === 'group' && group.projectId === item.projectId, '分组必须属于同一项目');
        }
        if (item.selectedBranchEdgeId != null) {
          const edge = maps.edges.get(item.selectedBranchEdgeId as string)!;
          check(item.kind === 'condition' && edge.sourceId === item.id, '条件出口无效');
        }
      }
      if (collection === 'edges') {
        ref(item, 'sourceId', 'nodes');
        ref(item, 'targetId', 'nodes');
        check(
          maps.nodes.get(item.sourceId as string)!.projectId === item.projectId &&
            maps.nodes.get(item.targetId as string)!.projectId === item.projectId,
          '连线必须属于同一项目',
        );
      }
    }
  for (const [collection, parent] of [
    ['projects', 'parentId'],
    ['tasks', 'parentId'],
    ['nodes', 'groupId'],
  ] as const)
    for (const start of maps[collection].values()) {
      const seen = new Set<string>();
      let item: Row | undefined = start;
      while (item) {
        check(!seen.has(item.id as string), '父级关系不能形成循环');
        seen.add(item.id as string);
        item = maps[collection].get(item[parent] as string);
      }
    }
  if (!isRecord(value.preferences)) throw new Error('备份中的设置无效');
  const booleans = [
    'workflowAutoTodo',
    'workflowSkipCompletes',
    'workflowAutoUnlock',
    'workflowCheckDependencies',
    'workflowAllowManualUnlock',
    'workflowShowEdgeLabels',
    'workflowShowDescription',
    'workflowShowEstimate',
    'workflowShowMilestones',
    'workflowAutoLayout',
    'sidebarCollapsed',
    'showNavigationLabels',
    'showSearch',
    'showShortcutHints',
    'reduceMotion',
    'automaticBackup',
    'strongReminder',
    'autoSync',
    'nativeNotifications',
    'weekStartsMonday',
  ];
  const preferenceSchemas: Record<string, Validator> = {
    ...Object.fromEntries(booleans.map((key) => [key, boolean])),
    themeMode: one(['system', 'light', 'dark']),
    density: one(['comfortable', 'compact', 'spacious', '紧凑', '舒适', '宽松']),
    calendarView: one(['月', '周', '日', '时间轴', '列表']),
    overlapStyle: one(['并排', '层叠', '聚合']),
    displayName: (x) => string(x) && (x as string).length <= 100,
    defaultTaskPriority: one(priorities),
    defaultPriority: one(priorities),
    workflowDefaultPriority: one(priorities),
    workflowDefaultKind: one(['task', 'milestone', 'note']),
    defaultDifficulty: (x) => one(['low', 'normal', 'high'])(x) || integer(x),
    sidebarPosition: one(['left', 'right']),
    dateFormat: one(['chinese', 'YYYY-MM-DD', 'YYYY/MM/DD']),
    timeFormat: one(['12', '24']),
    fontFamily: one(['HarmonyOS Sans SC', 'Microsoft YaHei', 'system']),
    fontScale: (x) => typeof x === 'number' && Number.isFinite(x) && x >= 0.5 && x <= 3,
    reminderMinutes: range(0, 10080),
    courseReminderLeadMinutes: range(0, 10080),
    reminderInterval: range(1, 10080),
    maxReminders: range(1, 100),
    defaultEventMinutes: range(5, 1440),
    defaultEstimateMinutes: range(5, 1440),
    workflowEstimateMinutes: range(5, 1440),
    timeStepMinutes: range(5, 60),
    workflowZoom: range(25, 200),
    brandColor: range(0xff000000, 0xffffffff),
    todayModules: (x) => Array.isArray(x) && x.length <= 30 && x.every(string),
    timezone: (x) => {
      if (x === 'system') return true;
      if (typeof x !== 'string') return false;
      try {
        new Intl.DateTimeFormat('en', { timeZone: x });
        return true;
      } catch {
        return false;
      }
    },
  };
  check(Object.keys(value.preferences).length <= 100, '设置数量超限');
  for (const [key, entry] of Object.entries(value.preferences)) {
    check(
      !/secret|token|password|private.?key|api.?key|webhook|__proto__|constructor|prototype/i.test(key),
      '凭据不能写入工作区设置',
    );
    if (preferenceSchemas[key]) check(preferenceSchemas[key](entry), `设置 ${key} 无效`);
  }
  return value as Workspace;
}

export function saveTask(data: Workspace, input: TaskInput): Workspace {
  if (!input.title.trim()) throw new Error('请输入任务名称');
  if (!priorities.includes(input.priority)) throw new Error('无效的优先级');
  if (input.deadline !== null && !validDate(input.deadline)) throw new Error('无效的截止时间');
  const existing = data.tasks.find((task) => task.id === input.id);
  if (input.id && !existing) throw new Error('任务已不存在');
  const task: Task = {
    id: crypto.randomUUID(),
    status: 'todo',
    difficulty: 'normal',
    description: '',
    estimateMinutes: 60,
    actualMinutes: 0,
    splittable: true,
    archived: false,
    attachments: [],
    tags: [],
    ...existing,
    ...input,
    title: input.title.trim(),
  };
  if (!task.id) task.id = crypto.randomUUID();
  return {
    ...data,
    tasks: existing
      ? data.tasks.map((item) => (item.id === existing.id ? task : item))
      : [...data.tasks, task],
  };
}

export function toggleTask(data: Workspace, id: string): Workspace {
  return {
    ...data,
    tasks: data.tasks.map((task) =>
      task.id === id
        ? {
            ...task,
            status: task.status === 'done' ? 'todo' : 'done',
            completedAt: task.status === 'done' ? null : new Date().toISOString(),
          }
        : task,
    ),
  };
}

export function localDay(date: Date = new Date()): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}
export function shiftDay(day: string, offset: number): string {
  const date = new Date(`${day}T12:00:00`);
  date.setDate(date.getDate() + offset);
  return localDay(date);
}
export function dateTimeInput(value: string): string {
  const date = new Date(value);
  return `${localDay(date)}T${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
}
export function eventsForDay(data: Workspace, day: string): CalendarEvent[] {
  const start = new Date(`${day}T00:00:00`).getTime();
  const end = new Date(`${shiftDay(day, 1)}T00:00:00`).getTime();
  return data.events
    .filter((event) => !event.deletedAt && Date.parse(event.start) < end && Date.parse(event.end) > start)
    .sort((a, b) => Date.parse(a.start) - Date.parse(b.start));
}

export function layoutEvents(items: CalendarEvent[], day: string) {
  const dayStart = new Date(`${day}T00:00:00`).getTime();
  const dayEnd = new Date(`${shiftDay(day, 1)}T00:00:00`).getTime();
  const sorted = items
    .filter((item) => !item.allDay)
    .map((event) => ({
      event,
      start: Math.max(dayStart, Date.parse(event.start)),
      end: Math.min(dayEnd, Date.parse(event.end)),
      column: 0,
      columns: 1,
    }))
    .sort((a, b) => a.start - b.start || b.end - a.end);
  let group: typeof sorted = [];
  let ends: number[] = [];
  let groupEnd = 0;
  function finish() {
    for (const item of group) item.columns = ends.length;
    group = [];
    ends = [];
  }
  for (const item of sorted) {
    if (item.start >= groupEnd) finish();
    let column = ends.findIndex((end) => end <= item.start);
    if (column < 0) column = ends.length;
    item.column = column;
    ends[column] = item.end;
    group.push(item);
    groupEnd = Math.max(groupEnd, item.end);
  }
  finish();
  return sorted;
}
export function hexColor(color: number): string {
  return `#${(color & 0xffffff).toString(16).padStart(6, '0')}`;
}

export function previewWorkspace(): Workspace {
  const day = localDay();
  const at = (time: string) => new Date(`${day}T${time}:00`).toISOString();
  return {
    ...emptyWorkspace(),
    projects: [
      { id: 'research', title: 'LLM 水印论文', color: 0xff4b70e8 },
      { id: 'study', title: '研究生课程', color: 0xff9878d0 },
      { id: 'life', title: '个人生活', color: 0xff309b87 },
    ],
    tasks: [
      {
        id: 't1',
        title: '阅读三篇相关论文',
        status: 'todo',
        priority: 'high',
        projectId: 'research',
        deadline: at('15:00'),
        estimateMinutes: 180,
      },
      {
        id: 't2',
        title: '整理实验结果',
        status: 'doing',
        priority: 'high',
        projectId: 'research',
        deadline: at('19:00'),
        estimateMinutes: 120,
      },
      {
        id: 't3',
        title: '回复导师邮件',
        status: 'todo',
        priority: 'normal',
        projectId: 'study',
        deadline: at('20:00'),
        estimateMinutes: 30,
      },
      {
        id: 't4',
        title: '预习下周课程内容',
        status: 'todo',
        priority: 'normal',
        projectId: 'study',
        deadline: at('22:00'),
        estimateMinutes: 60,
      },
    ],
    events: [
      {
        id: 'e1',
        title: '机器学习理论课',
        start: at('08:30'),
        end: at('10:00'),
        color: 0xff4b70e8,
        projectId: 'study',
        location: '教学楼 A302',
      },
      {
        id: 'e2',
        title: '实验 · 鲁棒性测试',
        start: at('10:30'),
        end: at('12:00'),
        color: 0xffc17c56,
        projectId: 'research',
        location: '实验室',
      },
      {
        id: 'e3',
        title: '组会',
        start: at('14:00'),
        end: at('16:00'),
        color: 0xff9878d0,
        projectId: 'research',
        location: '线上会议',
      },
      { id: 'e4', title: '健身', start: at('16:30'), end: at('18:00'), color: 0xff309b87, projectId: 'life' },
      {
        id: 'e5',
        title: '阅读论文',
        start: at('19:00'),
        end: at('20:30'),
        color: 0xffb39447,
        projectId: 'research',
      },
    ],
  };
}
