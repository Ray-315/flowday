import type { CalendarEvent, Project, Task, Workspace } from './workspace';
export type RepeatRule = {
  frequency: 'daily' | 'weekly' | 'monthly' | 'yearly';
  interval: number;
  count?: number | null;
  until?: string | null;
};
export type RepeatScope = 'thisOnly' | 'thisAndFuture';
export type NodeKind = 'task' | 'condition' | 'delay' | 'milestone' | 'note' | 'link' | 'group';
export type NodeStatus = 'locked' | 'ready' | 'doing' | 'waiting' | 'done' | 'skipped';
export type FlowNode = Record<string, unknown> & {
  id: string;
  projectId: string;
  title: string;
  kind: NodeKind;
  status: NodeStatus;
  x: number;
  y: number;
  anyPredecessor: boolean;
  taskId?: string | null;
  groupId?: string | null;
  targetProjectId?: string | null;
  selectedBranchEdgeId?: string | null;
  collapsed?: boolean;
  delayWaiting?: boolean;
  completedAt?: string | null;
};
export type FlowEdge = Record<string, unknown> & {
  id: string;
  projectId: string;
  sourceId: string;
  targetId: string;
  label: string;
  active: boolean;
  delayMinutes: number;
  availableAt?: string | null;
};
const record = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);
export const workflowNodes = (data: Workspace): FlowNode[] =>
  data.nodes.map((value) => {
    if (
      !record(value) ||
      typeof value.id !== 'string' ||
      typeof value.projectId !== 'string' ||
      typeof value.title !== 'string'
    )
      throw new Error('工作流节点格式无效');
    const node = { kind: 'task', status: 'ready', x: 0, y: 0, anyPredecessor: false, ...value };
    if (
      !['task', 'condition', 'delay', 'milestone', 'note', 'link', 'group'].includes(String(node.kind)) ||
      !['locked', 'ready', 'doing', 'waiting', 'done', 'skipped'].includes(String(node.status)) ||
      typeof node.x !== 'number' ||
      typeof node.y !== 'number' ||
      !Number.isFinite(node.x) ||
      !Number.isFinite(node.y) ||
      typeof node.anyPredecessor !== 'boolean'
    )
      throw new Error('工作流节点属性无效');
    return node as FlowNode;
  });
export const workflowEdges = (data: Workspace): FlowEdge[] =>
  (Array.isArray(data.edges) ? data.edges : []).map((value: unknown) => {
    if (
      !record(value) ||
      ['id', 'projectId', 'sourceId', 'targetId'].some((key) => typeof value[key] !== 'string')
    )
      throw new Error('工作流连线格式无效');
    const edge = { label: '', active: true, delayMinutes: 0, ...value };
    if (
      typeof edge.label !== 'string' ||
      typeof edge.active !== 'boolean' ||
      typeof edge.delayMinutes !== 'number' ||
      !Number.isInteger(edge.delayMinutes) ||
      edge.delayMinutes < 0
    )
      throw new Error('工作流连线属性无效');
    return edge as FlowEdge;
  });
const clone = <T>(value: T): T => structuredClone(value);
const timestamp = (value: unknown): number => (typeof value === 'string' ? Date.parse(value) : NaN);
const flag = (data: Workspace, key: string, fallback = true) =>
  typeof data.preferences[key] === 'boolean' ? (data.preferences[key] as boolean) : fallback;
const requireItem = <T extends { id: string }>(items: T[], id: string): T => {
  const item = items.find((x) => x.id === id);
  if (!item) throw new Error('项目或条目已不存在');
  return item;
};
export function occurrence(anchor: string, rule: RepeatRule, index: number): string {
  const date = new Date(anchor);
  if (
    !Number.isFinite(date.getTime()) ||
    !Number.isInteger(index) ||
    index < 0 ||
    !Number.isInteger(rule.interval) ||
    rule.interval < 1 ||
    !['daily', 'weekly', 'monthly', 'yearly'].includes(rule.frequency) ||
    (rule.count != null && (!Number.isInteger(rule.count) || rule.count < 1)) ||
    (rule.until != null && !Number.isFinite(timestamp(rule.until)))
  )
    throw new Error('重复规则无效');
  const step = rule.interval * index;
  if (rule.frequency === 'daily' || rule.frequency === 'weekly')
    date.setDate(date.getDate() + step * (rule.frequency === 'weekly' ? 7 : 1));
  else {
    const day = date.getDate();
    date.setDate(1);
    if (rule.frequency === 'monthly') date.setMonth(date.getMonth() + step);
    else date.setFullYear(date.getFullYear() + step);
    const last = new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();
    date.setDate(Math.min(day, last));
  }
  return date.toISOString();
}
type Recurring = Task | CalendarEvent;
const anchorOf = (item: Recurring): string =>
  String(item.occurrenceDate ?? item.plannedStart ?? item.deadline ?? item.start ?? new Date().toISOString());
const shift = (value: unknown, offset: number): string | null =>
  typeof value === 'string' ? new Date(timestamp(value) + offset).toISOString() : null;
export function materializeRecurring(data: Workspace, until: string): Workspace {
  if (!Number.isFinite(timestamp(until))) throw new Error('展开日期无效');
  const next = clone(data);
  for (const collection of ['tasks', 'events'] as const) {
    const items = next[collection] as Recurring[];
    const seen = new Set<string>();
    for (const item of [...items].sort((a, b) => timestamp(anchorOf(a)) - timestamp(anchorOf(b)))) {
      const rule = item.repeatRule as RepeatRule | null | undefined;
      const series = String(item.seriesId ?? item.id);
      if (!rule || seen.has(series)) continue;
      seen.add(series);
      if (item.deletedAt && !items.some((x) => x.seriesId === series && !x.deletedAt)) continue;
      const anchor = anchorOf(item);
      occurrence(anchor, rule, 0);
      item.seriesId = series;
      item.occurrenceDate = anchor;
      for (let index = 1; index < (rule.count ?? 1000); index++) {
        const date = occurrence(anchor, rule, index);
        if (timestamp(date) > timestamp(until) || (rule.until && timestamp(date) > timestamp(rule.until)))
          break;
        if (items.some((x) => x.seriesId === series && timestamp(x.occurrenceDate) === timestamp(date)))
          continue;
        const copy = clone(item);
        copy.id = crypto.randomUUID();
        copy.occurrenceDate = date;
        copy.actualMinutes = 0;
        copy.deletedAt = null;
        const offset = timestamp(date) - timestamp(anchor);
        if (collection === 'tasks') {
          copy.plannedStart = shift(item.plannedStart, offset);
          copy.deadline = shift(item.deadline, offset);
          copy.status = 'todo';
          copy.completedAt = null;
        } else {
          copy.start = shift(item.start, offset);
          copy.end = shift(item.end, offset);
          copy.completed = false;
        }
        items.push(copy);
      }
    }
  }
  return next;
}
export function editRecurring(
  data: Workspace,
  collection: 'tasks' | 'events',
  value: Task | CalendarEvent,
  scope: RepeatScope = 'thisOnly',
): Workspace {
  if (!value.title.trim()) throw new Error('名称不能为空');
  if (
    collection === 'events' &&
    (!Number.isFinite(timestamp(value.start)) ||
      !Number.isFinite(timestamp(value.end)) ||
      timestamp(value.end) <= timestamp(value.start))
  )
    throw new Error('日程结束时间必须晚于开始时间');
  if (collection === 'tasks' && value.deadline != null && !Number.isFinite(timestamp(value.deadline)))
    throw new Error('任务截止时间无效');
  const old = requireItem(data[collection] as Recurring[], value.id);
  const next = clone(data);
  const anchor = anchorOf(old);
  const changedRule = JSON.stringify(old.repeatRule ?? null) !== JSON.stringify(value.repeatRule ?? null);
  const fields =
    collection === 'events'
      ? [
          'title',
          'projectId',
          'location',
          'notes',
          'color',
          'locked',
          'allDay',
          'reminderLeadMinutes',
          'strongReminder',
          'reminderInterval',
          'maxReminders',
          'reminderRules',
          'tags',
          'attachments',
        ]
      : [
          'title',
          'description',
          'projectId',
          'priority',
          'difficulty',
          'estimateMinutes',
          'splittable',
          'tags',
          'attachments',
        ];
  const updated = clone(value);
  updated.seriesId ??= old.seriesId;
  updated.occurrenceDate ??= old.occurrenceDate;
  const items = next[collection] as Recurring[];
  if (scope === 'thisAndFuture' && old.seriesId) {
    for (const item of items.filter((x) => x.seriesId === old.seriesId)) {
      if (changedRule) {
        if (timestamp(anchorOf(item)) > timestamp(anchor)) item.deletedAt = new Date().toISOString();
        if (item.repeatRule)
          item.repeatRule = {
            ...(item.repeatRule as RepeatRule),
            until: new Date(timestamp(anchor) - 1).toISOString(),
          };
      } else if (item.id !== old.id && timestamp(anchorOf(item)) > timestamp(anchor)) {
        for (const field of fields) item[field] = clone(value[field]);
        const offset = timestamp(anchorOf(item)) - timestamp(anchor);
        for (const field of collection === 'events' ? ['start', 'end'] : ['plannedStart', 'deadline'])
          item[field] = shift(value[field], offset);
      }
    }
    if (changedRule) {
      updated.seriesId = crypto.randomUUID();
      updated.occurrenceDate =
        collection === 'events' ? value.start : (value.plannedStart ?? value.deadline ?? anchor);
    }
  }
  items[items.findIndex((x) => x.id === value.id)] = updated;
  const expand = !old.seriesId || (scope === 'thisAndFuture' && changedRule);
  const result = expand
    ? materializeRecurring(next, new Date(timestamp(anchorOf(updated)) + 366 * 86400000).toISOString())
    : next;
  return collection === 'events'
    ? recalculateActualMinutes(
        result,
        new Set([
          old.taskId,
          value.taskId,
          ...items.filter((x) => x.seriesId === old.seriesId).map((x) => x.taskId),
        ]),
      )
    : setTaskStatus(result, value.id, String(value.status));
}
export function isProjectHidden(
  data: Workspace,
  id: string | null | undefined,
  includeArchived = true,
): boolean {
  const seen = new Set<string>();
  let cursor = id;
  while (cursor) {
    if (seen.has(cursor)) return true;
    seen.add(cursor);
    const project = data.projects.find((p) => p.id === cursor);
    if (!project || project.deletedAt || (includeArchived && project.archived)) return true;
    cursor = typeof project.parentId === 'string' ? project.parentId : null;
  }
  return false;
}
export const activeTasks = (data: Workspace): Task[] =>
  data.tasks.filter((t) => !t.deletedAt && !t.archived && !isProjectHidden(data, t.projectId));
export const activeEvents = (data: Workspace): CalendarEvent[] =>
  data.events.filter((e) => !e.deletedAt && !isProjectHidden(data, e.projectId, false));
function recalculateActualMinutes(data: Workspace, ids: Set<unknown>): Workspace {
  return {
    ...data,
    tasks: data.tasks.map((task) =>
      ids.has(task.id)
        ? {
            ...task,
            actualMinutes: activeEvents(data)
              .filter((e) => e.taskId === task.id && e.completed)
              .reduce((sum, e) => sum + Number(e.actualMinutes ?? 0), 0),
          }
        : task,
    ),
  };
}
export function completeEvent(data: Workspace, id: string, now = new Date()): Workspace {
  const event = requireItem(data.events, id);
  if (event.completed || event.deletedAt) return data;
  const next = recalculateActualMinutes(
    {
      ...data,
      events: data.events.map((e) =>
        e.id === id
          ? {
              ...e,
              completed: true,
              actualMinutes:
                Number(e.actualMinutes) ||
                Math.max(0, Math.floor((timestamp(e.end) - timestamp(e.start)) / 60000)),
            }
          : e,
      ),
    },
    new Set([event.taskId]),
  );
  return typeof event.taskId === 'string' &&
    data.tasks.some((t) => t.id === event.taskId) &&
    activeEvents(data).filter((e) => e.taskId === event.taskId).length === 1
    ? setTaskStatus(next, event.taskId, 'done', now)
    : next;
}
export function setEventCompleted(
  data: Workspace,
  id: string,
  completed: boolean,
  now = new Date(),
): Workspace {
  if (completed) return completeEvent(data, id, now);
  const event = requireItem(data.events, id);
  return recalculateActualMinutes(
    { ...data, events: data.events.map((e) => (e.id === id ? { ...e, completed: false } : e)) },
    new Set([event.taskId]),
  );
}
export function setEventActualMinutes(data: Workspace, id: string, minutes: number): Workspace {
  const event = requireItem(data.events, id);
  if (!Number.isInteger(minutes) || minutes < 0) throw new Error('耗时不能为负数');
  return recalculateActualMinutes(
    { ...data, events: data.events.map((e) => (e.id === id ? { ...e, actualMinutes: minutes } : e)) },
    new Set([event.taskId]),
  );
}
export function setTaskStatus(data: Workspace, id: string, status: string, now = new Date()): Workspace {
  requireItem(data.tasks, id);
  if (!['todo', 'doing', 'waiting', 'done', 'cancelled'].includes(status)) throw new Error('无效任务状态');
  const mapped: Record<string, NodeStatus> = {
    todo: 'ready',
    doing: 'doing',
    waiting: 'waiting',
    done: 'done',
    cancelled: 'skipped',
  };
  return refreshWorkflow(
    {
      ...data,
      tasks: data.tasks.map((t) =>
        t.id === id
          ? { ...t, status, completedAt: status === 'done' ? (t.completedAt ?? now.toISOString()) : null }
          : t,
      ),
      nodes: workflowNodes(data).map((n) =>
        n.taskId === id
          ? {
              ...n,
              status: mapped[status],
              completedAt: ['done', 'cancelled'].includes(status) ? now.toISOString() : null,
            }
          : n,
      ),
    },
    now,
  );
}
export function validateProjectParent(data: Workspace, id: string, parentId: string | null): void {
  const seen = new Set([id]);
  let cursor = parentId;
  while (cursor) {
    if (seen.has(cursor)) throw new Error('项目层级不能形成循环');
    seen.add(cursor);
    const parent = requireItem(data.projects, cursor);
    if (parent.deletedAt) throw new Error('父项目已删除');
    cursor = typeof parent.parentId === 'string' ? parent.parentId : null;
  }
}
export function restoreItem(
  data: Workspace,
  collection: 'tasks' | 'events' | 'projects',
  id: string,
): Workspace {
  requireItem<Task | CalendarEvent | Project>(data[collection], id);
  const next = clone(data);
  const item = requireItem<Task | CalendarEvent | Project>(next[collection], id);
  item.deletedAt = null;
  const key = collection === 'projects' ? 'parentId' : 'projectId';
  if (item[key] && !data.projects.some((p) => p.id === item[key] && !p.deletedAt)) item[key] = null;
  return collection === 'events' ? recalculateActualMinutes(next, new Set([item.taskId])) : next;
}
export function archiveItem(
  data: Workspace,
  collection: 'tasks' | 'projects',
  id: string,
  archived: boolean,
): Workspace {
  requireItem<Task | Project>(data[collection], id);
  return {
    ...data,
    [collection]: data[collection].map((item) => (item.id === id ? { ...item, archived } : item)),
  };
}
export function trashItem(
  data: Workspace,
  collection: 'tasks' | 'events' | 'projects',
  id: string,
  scope: RepeatScope = 'thisOnly',
  now = new Date(),
): Workspace {
  const item = requireItem<Task | CalendarEvent | Project>(data[collection], id);
  const affected = data[collection].filter(
    (x) =>
      x.id === id ||
      (scope === 'thisAndFuture' &&
        item.seriesId &&
        x.seriesId === item.seriesId &&
        timestamp(anchorOf(x as Recurring)) >= timestamp(anchorOf(item as Recurring))),
  );
  const ids = new Set(affected.map((x) => x.id));
  const next = {
    ...data,
    [collection]: data[collection].map((x) => (ids.has(x.id) ? { ...x, deletedAt: now.toISOString() } : x)),
  };
  return collection === 'events'
    ? recalculateActualMinutes(next, new Set(affected.map((x) => x.taskId)))
    : next;
}
export function purgeTrash(data: Workspace, now = new Date()): Workspace {
  const expired = (item: { deletedAt?: string | null }) =>
    Boolean(item.deletedAt && timestamp(item.deletedAt) <= now.getTime() - 30 * 86400000);
  const projectIds = new Set(data.projects.filter(expired).map((p) => p.id)),
    taskIds = new Set(data.tasks.filter(expired).map((t) => t.id)),
    eventIds = new Set(data.events.filter(expired).map((e) => e.id)),
    removedNodes = new Set(
      workflowNodes(data)
        .filter((n) => projectIds.has(n.projectId))
        .map((n) => n.id),
    );
  const nodes = workflowNodes(data)
    .filter((n) => !removedNodes.has(n.id))
    .map((n) => ({
      ...n,
      taskId: n.taskId && taskIds.has(n.taskId) ? null : n.taskId,
      targetProjectId: n.targetProjectId && projectIds.has(n.targetProjectId) ? null : n.targetProjectId,
      groupId: n.groupId && removedNodes.has(n.groupId) ? null : n.groupId,
    }));
  const edges = workflowEdges(data).filter(
    (e) => !projectIds.has(e.projectId) && !removedNodes.has(e.sourceId) && !removedNodes.has(e.targetId),
  );
  const projects = data.projects
    .filter((p) => !projectIds.has(p.id))
    .map((p) => ({
      ...p,
      parentId: typeof p.parentId === 'string' && projectIds.has(p.parentId) ? null : p.parentId,
    }));
  const tasks = data.tasks
    .filter((t) => !taskIds.has(t.id))
    .map((t) => ({
      ...t,
      parentId: typeof t.parentId === 'string' && taskIds.has(t.parentId) ? null : t.parentId,
      projectId: t.projectId && projectIds.has(t.projectId) ? null : t.projectId,
    }));
  const events = data.events
    .filter((e) => !expired(e))
    .map((e) => ({
      ...e,
      projectId: e.projectId && projectIds.has(e.projectId) ? null : e.projectId,
      taskId: typeof e.taskId === 'string' && taskIds.has(e.taskId) ? null : e.taskId,
    }));
  const notices = Array.isArray(data.notices)
    ? data.notices.map((value: unknown) =>
        typeof value === 'object' && value !== null
          ? {
              ...value,
              taskId: taskIds.has((value as Record<string, unknown>).taskId as string)
                ? null
                : (value as Record<string, unknown>).taskId,
              eventId: eventIds.has((value as Record<string, unknown>).eventId as string)
                ? null
                : (value as Record<string, unknown>).eventId,
              projectId: projectIds.has((value as Record<string, unknown>).projectId as string)
                ? null
                : (value as Record<string, unknown>).projectId,
              nodeId: removedNodes.has((value as Record<string, unknown>).nodeId as string)
                ? null
                : (value as Record<string, unknown>).nodeId,
            }
          : value,
      )
    : data.notices;
  return {
    ...data,
    projects,
    tasks,
    events,
    nodes: nodes.map((n) => ({
      ...n,
      selectedBranchEdgeId:
        n.selectedBranchEdgeId && !edges.some((e) => e.id === n.selectedBranchEdgeId)
          ? null
          : n.selectedBranchEdgeId,
    })),
    edges,
    notices,
  };
}
export function dependenciesSatisfied(
  data: Workspace,
  node: FlowNode,
  now = new Date(),
  ignoreDelay = false,
): boolean {
  const incoming = workflowEdges(data).filter((e) => e.active && e.targetId === node.id);
  const satisfied = (edge: FlowEdge) => {
    const source = workflowNodes(data).find((n) => n.id === edge.sourceId);
    if (!source) return false;
    if (source.kind === 'condition' && source.selectedBranchEdgeId !== edge.id) return false;
    if (
      !ignoreDelay &&
      ((edge.availableAt && now.getTime() < timestamp(edge.availableAt)) ||
        (edge.delayMinutes > 0 &&
          (!source.completedAt || now.getTime() < timestamp(source.completedAt) + edge.delayMinutes * 60000)))
    )
      return false;
    return source.status === 'done' || (source.status === 'skipped' && flag(data, 'workflowSkipCompletes'));
  };
  return (
    incoming.length === 0 || (node.anyPredecessor ? incoming.some(satisfied) : incoming.every(satisfied))
  );
}
export function refreshWorkflow(data: Workspace, now = new Date(), manuallyUnlocked?: string): Workspace {
  return {
    ...data,
    nodes: workflowNodes(data).map((node) => {
      if (node.id === manuallyUnlocked || (!['locked', 'ready'].includes(node.status) && !node.delayWaiting))
        return node;
      const ready = !flag(data, 'workflowCheckDependencies') || dependenciesSatisfied(data, node, now);
      if (!ready) {
        const delayWaiting = dependenciesSatisfied(data, node, now, true);
        return { ...node, delayWaiting, status: delayWaiting ? 'waiting' : 'locked' };
      }
      return node.status !== 'locked' || flag(data, 'workflowAutoUnlock')
        ? { ...node, status: 'ready', delayWaiting: false }
        : node;
    }),
  };
}
export function addWorkflowEdge(data: Workspace, edge: FlowEdge): Workspace {
  const source = requireItem(workflowNodes(data), edge.sourceId),
    target = requireItem(workflowNodes(data), edge.targetId);
  if (
    source.projectId !== edge.projectId ||
    target.projectId !== edge.projectId ||
    !Number.isInteger(edge.delayMinutes) ||
    edge.delayMinutes < 0
  )
    throw new Error('连线无效');
  if (workflowEdges(data).some((e) => e.id === edge.id)) throw new Error('连线已存在');
  const next = refreshWorkflow({ ...data, edges: [...workflowEdges(data), edge] });
  return flag(data, 'workflowAutoLayout', false) ? layoutWorkflow(next, edge.projectId) : next;
}
export function setNodeStatus(data: Workspace, id: string, status: NodeStatus, now = new Date()): Workspace {
  const node = requireItem(workflowNodes(data), id);
  const manual = node.status === 'locked' && status === 'ready';
  if (manual && !flag(data, 'workflowAllowManualUnlock')) throw new Error('不允许手动解锁节点');
  if (
    status === 'doing' &&
    flag(data, 'workflowCheckDependencies') &&
    !dependenciesSatisfied(data, node, now)
  )
    throw new Error('前置节点尚未完成');
  const taskStatus: Record<NodeStatus, string> = {
    locked: 'todo',
    ready: 'todo',
    doing: 'doing',
    waiting: 'waiting',
    done: 'done',
    skipped: 'cancelled',
  };
  const next = {
    ...data,
    nodes: workflowNodes(data).map((n) =>
      n.id === id || (node.taskId && n.taskId === node.taskId)
        ? {
            ...n,
            status,
            delayWaiting: false,
            completedAt: ['done', 'skipped'].includes(status) ? now.toISOString() : null,
          }
        : n,
    ),
    tasks: data.tasks.map((t) =>
      t.id === node.taskId
        ? {
            ...t,
            status: taskStatus[status],
            completedAt: status === 'done' ? (t.completedAt ?? now.toISOString()) : null,
          }
        : t,
    ),
  };
  return refreshWorkflow(next, now, manual ? id : undefined);
}
export function selectBranch(data: Workspace, nodeId: string, edgeId: string, now = new Date()): Workspace {
  const node = requireItem(workflowNodes(data), nodeId);
  if (node.kind !== 'condition' || !workflowEdges(data).some((e) => e.id === edgeId && e.sourceId === nodeId))
    throw new Error('条件出口无效');
  return refreshWorkflow(
    {
      ...data,
      nodes: workflowNodes(data).map((n) =>
        n.id === nodeId
          ? { ...n, selectedBranchEdgeId: edgeId, status: 'done', completedAt: now.toISOString() }
          : n,
      ),
    },
    now,
  );
}
export function moveWorkflowNode(data: Workspace, id: string, dx: number, dy: number): Workspace {
  return moveWorkflowSelection(data, [id], id, dx, dy);
}
export type WorkflowPoint = { x: number; y: number };
export type WorkflowBounds = { left: number; top: number; right: number; bottom: number };
export function workflowSelectionBounds(start: WorkflowPoint, end: WorkflowPoint): WorkflowBounds {
  if (![start.x, start.y, end.x, end.y].every(Number.isFinite)) throw new Error('选择范围无效');
  return {
    left: Math.min(start.x, end.x),
    top: Math.min(start.y, end.y),
    right: Math.max(start.x, end.x),
    bottom: Math.max(start.y, end.y),
  };
}
export function selectWorkflowNodes(nodes: FlowNode[], bounds: WorkflowBounds): string[] {
  return nodes
    .filter(
      (node) =>
        node.x < bounds.right &&
        node.x + 200 > bounds.left &&
        node.y < bounds.bottom &&
        node.y + 86 > bounds.top,
    )
    .map((node) => node.id);
}
export function workflowDragIds(nodes: FlowNode[], selection: string[], anchorId: string): string[] {
  requireItem(nodes, anchorId);
  const ids = new Set(
    selection.includes(anchorId) ? selection.filter((id) => nodes.some((n) => n.id === id)) : [anchorId],
  );
  let size = 0;
  while (size !== ids.size) {
    size = ids.size;
    for (const node of nodes) if (node.groupId && ids.has(node.groupId)) ids.add(node.id);
  }
  return [...ids];
}
export function moveWorkflowSelection(
  data: Workspace,
  selection: string[],
  anchorId: string,
  dx: number,
  dy: number,
): Workspace {
  if (!Number.isFinite(dx) || !Number.isFinite(dy)) throw new Error('坐标无效');
  const ids = new Set(workflowDragIds(workflowNodes(data), selection, anchorId));
  return {
    ...data,
    nodes: workflowNodes(data).map((n) => (ids.has(n.id) ? { ...n, x: n.x + dx, y: n.y + dy } : n)),
  };
}
export function saveWorkflowNode(data: Workspace, node: FlowNode, createTask = false): Workspace {
  requireItem(data.projects, node.projectId);
  if (node.kind !== 'group' && workflowNodes(data).some((member) => member.groupId === node.id))
    throw new Error('请先移出分组成员');
  if (
    !node.title.trim() ||
    !Number.isFinite(node.x) ||
    !Number.isFinite(node.y) ||
    !['task', 'condition', 'delay', 'milestone', 'note', 'link', 'group'].includes(node.kind)
  )
    throw new Error('节点属性无效');
  let cursor = node.groupId;
  const visited = new Set([node.id]);
  while (cursor) {
    if (visited.has(cursor)) throw new Error('分组不能形成循环');
    visited.add(cursor);
    const group = requireItem(workflowNodes(data), cursor);
    if (group.kind !== 'group' || group.projectId !== node.projectId) throw new Error('分组必须属于同一项目');
    cursor = group.groupId;
  }
  if (node.targetProjectId) requireItem(data.projects, node.targetProjectId);
  let tasks = data.tasks;
  if (node.taskId && !tasks.some((t) => t.id === node.taskId)) {
    if (!createTask) throw new Error('关联任务不存在');
    tasks = [
      ...tasks,
      {
        id: node.taskId,
        title: node.title,
        projectId: node.projectId,
        status: 'todo',
        priority: ['low', 'normal', 'high', 'urgent'].includes(
          String(data.preferences.workflowDefaultPriority),
        )
          ? String(data.preferences.workflowDefaultPriority)
          : 'normal',
        description: node.description ?? '',
        estimateMinutes:
          typeof data.preferences.workflowEstimateMinutes === 'number' &&
          Number.isInteger(data.preferences.workflowEstimateMinutes) &&
          data.preferences.workflowEstimateMinutes > 0 &&
          data.preferences.workflowEstimateMinutes <= 1440
            ? data.preferences.workflowEstimateMinutes
            : 60,
        actualMinutes: 0,
        archived: false,
        tags: [],
        attachments: [],
      },
    ];
  }
  const existing = workflowNodes(data).find((n) => n.id === node.id);
  const next = {
    ...data,
    tasks,
    nodes: existing
      ? workflowNodes(data).map((n) => (n.id === node.id ? { ...n, ...node, title: node.title.trim() } : n))
      : [...data.nodes, { ...node, title: node.title.trim() }],
  };
  const result = node.taskId
    ? setTaskStatus(next, node.taskId, requireItem(tasks, node.taskId).status)
    : refreshWorkflow(next);
  return !existing && flag(data, 'workflowAutoLayout', false)
    ? layoutWorkflow(result, node.projectId)
    : result;
}
export function deleteWorkflowSelection(data: Workspace, ids: string[]): Workspace {
  const edges = workflowEdges(data).filter(
    (e) => !ids.includes(e.id) && !ids.includes(e.sourceId) && !ids.includes(e.targetId),
  );
  return refreshWorkflow({
    ...data,
    notices: Array.isArray(data.notices)
      ? data.notices.map((value: unknown) => {
          if (typeof value !== 'object' || value === null) return value;
          const notice = value as Record<string, unknown>;
          return typeof notice.nodeId === 'string' && ids.includes(notice.nodeId)
            ? { ...notice, nodeId: null }
            : value;
        })
      : data.notices,
    edges,
    nodes: workflowNodes(data)
      .filter((n) => !ids.includes(n.id))
      .map((n) => ({
        ...n,
        groupId: n.groupId && ids.includes(n.groupId) ? null : n.groupId,
        selectedBranchEdgeId:
          n.selectedBranchEdgeId && !edges.some((e) => e.id === n.selectedBranchEdgeId)
            ? null
            : n.selectedBranchEdgeId,
      })),
  });
}
export function layoutWorkflow(data: Workspace, projectId: string): Workspace {
  const nodes = workflowNodes(data).filter((n) => n.projectId === projectId),
    remaining = new Set(nodes.map((n) => n.id)),
    placed = new Set<string>(),
    positions = new Map<string, { x: number; y: number }>();
  let column = 0;
  while (remaining.size) {
    let layer = nodes.filter(
      (n) =>
        remaining.has(n.id) &&
        workflowEdges(data)
          .filter((e) => e.targetId === n.id && e.active)
          .every((e) => placed.has(e.sourceId) || !remaining.has(e.sourceId)),
    );
    if (!layer.length) layer = [nodes.find((n) => remaining.has(n.id))!];
    layer.forEach((node, row) => positions.set(node.id, { x: 40 + column * 260, y: 40 + row * 140 }));
    for (const n of layer) {
      remaining.delete(n.id);
      placed.add(n.id);
    }
    column++;
  }
  return {
    ...data,
    nodes: workflowNodes(data).map((n) => (positions.has(n.id) ? { ...n, ...positions.get(n.id)! } : n)),
  };
}
export type WorkflowSnapshot = { projectId: string; nodes: FlowNode[]; edges: FlowEdge[]; tasks: Task[] };
export function copyWorkflowSelection(data: Workspace, ids: string[]): WorkflowSnapshot {
  const selected = new Set(ids);
  let size = 0;
  while (size !== selected.size) {
    size = selected.size;
    for (const n of workflowNodes(data)) if (n.groupId && selected.has(n.groupId)) selected.add(n.id);
  }
  const nodes = workflowNodes(data).filter((n) => selected.has(n.id));
  const taskIds = new Set(nodes.map((n) => n.taskId));
  return clone({
    projectId: nodes[0]?.projectId ?? '',
    nodes,
    edges: workflowEdges(data).filter((e) => selected.has(e.sourceId) && selected.has(e.targetId)),
    tasks: data.tasks.filter((t) => taskIds.has(t.id)),
  });
}
export function pasteWorkflowSelection(
  data: Workspace,
  snapshot: WorkflowSnapshot,
  projectId: string,
): Workspace {
  requireItem(data.projects, projectId);
  const ids = new Map(
    [...snapshot.nodes, ...snapshot.edges, ...snapshot.tasks].map((x) => [x.id, crypto.randomUUID()]),
  );
  const tasks = snapshot.tasks.map((t) => ({
    ...clone(t),
    id: ids.get(t.id)!,
    projectId,
    parentId: typeof t.parentId === 'string' ? (ids.get(t.parentId) ?? null) : null,
  }));
  const nodes = snapshot.nodes.map((n) => ({
    ...clone(n),
    id: ids.get(n.id)!,
    projectId,
    x: n.x + 40,
    y: n.y + 40,
    taskId: n.taskId ? (ids.get(n.taskId) ?? null) : null,
    groupId: n.groupId ? (ids.get(n.groupId) ?? null) : null,
    selectedBranchEdgeId: n.selectedBranchEdgeId ? (ids.get(n.selectedBranchEdgeId) ?? null) : null,
  }));
  const edges = snapshot.edges.map((e) => ({
    ...clone(e),
    id: ids.get(e.id)!,
    projectId,
    sourceId: ids.get(e.sourceId)!,
    targetId: ids.get(e.targetId)!,
  }));
  return refreshWorkflow({
    ...data,
    tasks: [...data.tasks, ...tasks],
    nodes: [...data.nodes, ...nodes],
    edges: [...workflowEdges(data), ...edges],
  });
}
export function captureWorkflow(data: Workspace, projectId: string): WorkflowSnapshot {
  const snapshot = copyWorkflowSelection(
    data,
    workflowNodes(data)
      .filter((n) => n.projectId === projectId)
      .map((n) => n.id),
  );
  snapshot.projectId = projectId;
  return snapshot;
}
export function restoreWorkflow(data: Workspace, snapshot: WorkflowSnapshot): Workspace {
  const removedTasks = new Set(
    workflowNodes(data)
      .filter((n) => n.projectId === snapshot.projectId)
      .map((n) => n.taskId),
  );
  const snapshotTasks = new Set(snapshot.tasks.map((t) => t.id));
  const nodes = [
    ...workflowNodes(data).filter((n) => n.projectId !== snapshot.projectId),
    ...clone(snapshot.nodes),
  ];
  const retained = new Set(nodes.map((n) => n.taskId));
  const tasks = data.tasks.filter(
    (t) =>
      !snapshotTasks.has(t.id) &&
      (!removedTasks.has(t.id) || retained.has(t.id) || data.events.some((e) => e.taskId === t.id)),
  );
  const restoredTasks = [...tasks, ...clone(snapshot.tasks)];
  const taskIds = new Set(restoredTasks.map((t) => t.id));
  const nodeIds = new Set(nodes.map((n) => n.id));
  return {
    ...data,
    nodes,
    edges: [
      ...workflowEdges(data).filter((e) => e.projectId !== snapshot.projectId),
      ...clone(snapshot.edges),
    ],
    tasks: restoredTasks.map((task) =>
      typeof task.parentId === 'string' && !taskIds.has(task.parentId) ? { ...task, parentId: null } : task,
    ),
    notices: Array.isArray(data.notices)
      ? data.notices.map((value: unknown) => {
          if (typeof value !== 'object' || value === null) return value;
          const notice = value as Record<string, unknown>;
          return {
            ...notice,
            ...(typeof notice.nodeId === 'string' && !nodeIds.has(notice.nodeId) ? { nodeId: null } : {}),
            ...(typeof notice.taskId === 'string' && !taskIds.has(notice.taskId) ? { taskId: null } : {}),
          };
        })
      : data.notices,
  };
}
