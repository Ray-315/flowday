import { describe, expect, it } from 'vitest';
import { emptyWorkspace, parseWorkspace, type Workspace } from './workspace';
import {
  occurrence,
  materializeRecurring,
  editRecurring,
  completeEvent,
  setTaskStatus,
  validateProjectParent,
  restoreItem,
  trashItem,
  dependenciesSatisfied,
  refreshWorkflow,
  addWorkflowEdge,
  selectBranch,
  moveWorkflowNode,
  copyWorkflowSelection,
  pasteWorkflowSelection,
  captureWorkflow,
  restoreWorkflow,
  type FlowNode,
} from './domain';
import {
  saveWorkflowNode,
  deleteWorkflowSelection,
  layoutWorkflow,
  setNodeStatus,
  archiveItem,
  setEventActualMinutes,
  setEventCompleted,
  purgeTrash,
  workflowNodes,
  workflowEdges,
} from './domain';
import { activeTasks, activeEvents } from './domain';
import { act, createElement, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { Workflow } from './Workflow';
import {
  workflowSelectionBounds,
  selectWorkflowNodes,
  workflowDragIds,
  moveWorkflowSelection,
} from './domain';
const node = (id: string, extra: Partial<FlowNode> = {}): FlowNode => ({
  id,
  title: id,
  projectId: 'p',
  kind: 'task',
  status: 'ready',
  x: 0,
  y: 0,
  anyPredecessor: false,
  ...extra,
});
const graph = (): Workspace => ({
  ...emptyWorkspace(),
  projects: [
    { id: 'p', title: 'P', color: 1 },
    { id: 'q', title: 'Q', color: 1 },
  ],
  nodes: [node('a'), node('b')],
  edges: [
    { id: 'e', projectId: 'p', sourceId: 'a', targetId: 'b', active: true, delayMinutes: 0, label: '' },
  ],
});
describe('recurrence', () => {
  it('replaces a changed future rule without regenerating retired instances', () => {
    let data = emptyWorkspace();
    data.tasks = [
      {
        id: 't',
        title: 'T',
        status: 'todo',
        priority: 'normal',
        plannedStart: '2026-10-01T09:00:00Z',
        repeatRule: { frequency: 'daily', interval: 1, count: 3 },
      },
    ];
    data = materializeRecurring(data, '2026-11-01T00:00:00Z');
    data = setTaskStatus(data, 't', 'done');
    data = editRecurring(
      data,
      'tasks',
      { ...data.tasks[1], repeatRule: { frequency: 'weekly', interval: 1, count: 2 } },
      'thisAndFuture',
    );
    const live = data.tasks.filter((t) => !t.deletedAt);
    expect(live.map((t) => new Date(String(t.plannedStart)).getUTCDate())).toEqual([1, 2, 9]);
    expect(live[0].status).toBe('done');
    expect(materializeRecurring(data, '2027-01-01T00:00:00Z').tasks.filter((t) => !t.deletedAt)).toHaveLength(
      3,
    );
  });
  it('task edits synchronize linked nodes and retain independent occurrences', () => {
    const data = graph();
    data.tasks = [{ id: 't', title: 'T', status: 'todo', priority: 'normal' }];
    data.nodes = [node('a', { taskId: 't' })];
    expect(
      (editRecurring(data, 'tasks', { ...data.tasks[0], status: 'done' }).nodes[0] as FlowNode).status,
    ).toBe('done');
  });
  it('rejects invalid rules and invalid edited event ranges', () => {
    expect(() => occurrence('2026-01-01T10:00:00Z', { frequency: 'daily', interval: 0 }, 1)).toThrow();
    const data = emptyWorkspace();
    data.events = [
      { id: 'e', title: 'E', color: 1, start: '2026-01-01T10:00:00Z', end: '2026-01-01T11:00:00Z' },
    ];
    expect(() => editRecurring(data, 'events', { ...data.events[0], end: data.events[0].start })).toThrow();
  });
  it('clamps month and leap-year dates against the original anchor', () => {
    expect(occurrence('2024-01-31T10:00:00Z', { frequency: 'monthly', interval: 1 }, 1)).toBe(
      '2024-02-29T10:00:00.000Z',
    );
    expect(occurrence('2024-01-31T10:00:00Z', { frequency: 'monthly', interval: 1 }, 2)).toBe(
      '2024-03-31T10:00:00.000Z',
    );
    expect(occurrence('2024-02-29T10:00:00Z', { frequency: 'yearly', interval: 1 }, 1)).toBe(
      '2025-02-28T10:00:00.000Z',
    );
  });
  it('materializes count-limited series once and retains deleted occurrences', () => {
    let data = emptyWorkspace();
    data.events = [
      {
        id: 'e',
        title: 'E',
        color: 1,
        start: '2026-01-01T10:00:00Z',
        end: '2026-01-01T11:00:00Z',
        repeatRule: { frequency: 'daily', interval: 1, count: 3 },
      },
    ];
    data = materializeRecurring(data, '2026-02-01T00:00:00Z');
    expect(data.events).toHaveLength(3);
    data = trashItem(data, 'events', data.events[1].id);
    expect(materializeRecurring(data, '2026-02-01T00:00:00Z').events).toHaveLength(3);
  });
  it('future edits shift times without resetting completed instances', () => {
    let data = emptyWorkspace();
    data.events = [
      {
        id: 'e',
        title: 'E',
        color: 1,
        start: '2026-01-01T10:00:00Z',
        end: '2026-01-01T11:00:00Z',
        repeatRule: { frequency: 'daily', interval: 1, count: 3 },
      },
    ];
    data = materializeRecurring(data, '2026-02-01T00:00:00Z');
    data.events[2].completed = true;
    data = editRecurring(
      data,
      'events',
      { ...data.events[1], title: 'new', start: '2026-01-02T12:00:00Z', end: '2026-01-02T13:00:00Z' },
      'thisAndFuture',
    );
    expect(data.events[0].title).toBe('E');
    expect(data.events[2].start).toBe('2026-01-03T12:00:00.000Z');
    expect(data.events[2].completed).toBe(true);
  });
});
describe('linked records and project hierarchy', () => {
  it('hides project descendants and restores completed block totals', () => {
    let data = graph();
    data.projects[1].parentId = 'p';
    data.tasks = [{ id: 't', title: 'T', status: 'todo', priority: 'normal', projectId: 'q' }];
    data.events = ['e', 'f'].map((id) => ({
      id,
      title: id,
      color: 1,
      start: '2026-01-01T10:00:00Z',
      end: '2026-01-01T11:00:00Z',
      projectId: 'q',
      taskId: 't',
    }));
    data = completeEvent(data, 'e');
    data = trashItem(data, 'events', 'e');
    expect(data.tasks[0].actualMinutes).toBe(0);
    data = completeEvent(data, 'f');
    data = restoreItem(data, 'events', 'e');
    expect(data.tasks[0].actualMinutes).toBe(120);
    data = trashItem(data, 'projects', 'p');
    expect(activeTasks(data)).toHaveLength(0);
    expect(activeEvents(data)).toHaveLength(0);
    data = restoreItem(data, 'projects', 'p');
    expect(activeTasks(data)).toHaveLength(1);
    expect(activeEvents(data)).toHaveLength(2);
    data = archiveItem(data, 'projects', 'p', true);
    expect(activeTasks(data)).toHaveLength(0);
    expect(activeEvents(data)).toHaveLength(2);
  });
  it('preserves unrelated manual time and allows event completion to be undone', () => {
    const data = emptyWorkspace();
    data.tasks = [
      { id: 't', title: 'T', status: 'todo', priority: 'normal' },
      { id: 'u', title: 'U', status: 'todo', priority: 'normal', actualMinutes: 45 },
    ];
    data.events = [
      {
        id: 'e',
        title: 'E',
        color: 1,
        start: '2026-01-01T10:00:00Z',
        end: '2026-01-01T11:00:00Z',
        taskId: 't',
      },
    ];
    const done = completeEvent(data, 'e');
    expect(done.tasks[1].actualMinutes).toBe(45);
    expect(setEventCompleted(done, 'e', false).tasks[0].actualMinutes).toBe(0);
  });
  it('purges expired trash and clears dangling references', () => {
    const data = graph();
    data.projects[0].deletedAt = '2026-01-01T00:00:00Z';
    data.tasks = [
      { id: 't', title: 'T', status: 'todo', priority: 'normal', projectId: 'p' },
      { id: 'u', title: 'U', status: 'todo', priority: 'normal', deletedAt: '2026-01-01T00:00:00Z' },
    ];
    data.events = [
      {
        id: 'e',
        title: 'E',
        color: 1,
        start: '2026-01-01T10:00:00Z',
        end: '2026-01-01T11:00:00Z',
        taskId: 'u',
        projectId: 'p',
      },
    ];
    const next = purgeTrash(data, new Date('2026-02-02T00:00:00Z'));
    expect(next.nodes).toHaveLength(0);
    expect(next.edges).toHaveLength(0);
    expect(next.events[0].taskId).toBeNull();
    expect(next.tasks[0].projectId).toBeNull();
  });
  it('retains notice content while clearing every purged entity reference', () => {
    const data = graph();
    const deletedAt = '2026-01-01T00:00:00Z';
    data.projects[0].deletedAt = deletedAt;
    data.tasks = [{ id: 't', title: 'T', status: 'todo', priority: 'normal', deletedAt }];
    data.events = [
      { id: 'event', title: 'E', color: 1, start: deletedAt, end: '2026-01-01T01:00:00Z', deletedAt },
    ];
    const notice = {
      id: 'notice',
      title: '保留通知',
      body: '内容',
      createdAt: deletedAt,
      type: 'reminder',
      taskId: 't',
      eventId: 'event',
      projectId: 'p',
      nodeId: 'a',
      read: true,
      custom: '保留',
    };
    data.notices = [notice];
    const next = purgeTrash(data, new Date('2026-02-02T00:00:00Z'));
    expect(next.notices).toEqual([{ ...notice, taskId: null, eventId: null, projectId: null, nodeId: null }]);
    expect(() => parseWorkspace(JSON.stringify(next))).not.toThrow();
  });
  it('keeps notices valid when a node is deleted or removed by workflow undo', () => {
    const data = graph();
    data.tasks = [
      { id: 't', title: 'T', status: 'todo', priority: 'normal' },
      { id: 'child', title: 'Child', status: 'todo', priority: 'normal', parentId: 't' },
    ];
    data.nodes = [node('a', { taskId: 't' }), node('b')];
    const notice = {
      id: 'notice',
      title: '通知',
      body: '内容',
      createdAt: '2026-01-01T00:00:00Z',
      nodeId: 'a',
      taskId: 't',
    };
    data.notices = [notice];
    const deleted = deleteWorkflowSelection(data, ['a']);
    expect(deleted.notices).toEqual([{ ...notice, nodeId: null }]);
    expect(() => parseWorkspace(JSON.stringify(deleted))).not.toThrow();
    const snapshot = captureWorkflow(data, 'p');
    snapshot.nodes = snapshot.nodes.filter((n) => n.id !== 'a');
    snapshot.edges = [];
    snapshot.tasks = [];
    const restored = restoreWorkflow(data, snapshot);
    expect(restored.notices).toEqual([{ ...notice, nodeId: null, taskId: null }]);
    expect(restored.tasks.find((task) => task.id === 'child')?.parentId).toBeNull();
    expect(() => parseWorkspace(JSON.stringify(restored))).not.toThrow();
  });
  it('counts completed active blocks without completing multi-block tasks', () => {
    const data = graph();
    data.tasks = [{ id: 't', title: 'T', status: 'todo', priority: 'normal' }];
    data.nodes = [node('a', { taskId: 't' })];
    data.events = ['e', 'f'].map((id) => ({
      id,
      title: id,
      color: 1,
      start: '2026-01-01T10:00:00Z',
      end: '2026-01-01T11:00:00Z',
      taskId: 't',
    }));
    const done = completeEvent(data, 'e');
    expect(done.tasks[0].actualMinutes).toBe(60);
    expect(done.tasks[0].status).toBe('todo');
    const single = completeEvent({ ...data, events: [data.events[0]] }, 'e');
    expect(single.tasks[0].status).toBe('done');
    expect((single.nodes[0] as FlowNode).status).toBe('done');
    expect(setTaskStatus(single, 't', 'todo').tasks[0].completedAt).toBeNull();
  });
  it('rejects project cycles and detaches a restored item from deleted project', () => {
    const data = graph();
    data.projects[1].parentId = 'p';
    expect(() => validateProjectParent(data, 'p', 'q')).toThrow();
    data.projects[0].deletedAt = '2026-01-01T00:00:00Z';
    data.tasks = [
      {
        id: 't',
        title: 'T',
        status: 'todo',
        priority: 'normal',
        projectId: 'p',
        deletedAt: '2026-01-01T00:00:00Z',
      },
    ];
    expect(restoreItem(data, 'tasks', 't').tasks[0].projectId).toBeNull();
  });
});
describe('workflow', () => {
  it('normalizes reverse selection rectangles and selects overlapping nodes', () => {
    const bounds = workflowSelectionBounds({ x: 220, y: 100 }, { x: 10, y: 10 });
    expect(bounds).toEqual({ left: 10, top: 10, right: 220, bottom: 100 });
    expect(
      selectWorkflowNodes([node('a'), node('b', { x: 210, y: 95 }), node('c', { x: 220, y: 100 })], bounds),
    ).toEqual(['a', 'b']);
  });
  it('moves every selected node and group descendant exactly once', () => {
    const nodes = [
      node('g', { kind: 'group' }),
      node('h', { kind: 'group', groupId: 'g', x: 10 }),
      node('a', { groupId: 'h', x: 20 }),
      node('b', { x: 400 }),
      node('c', { x: 700 }),
    ];
    expect(new Set(workflowDragIds(nodes, ['g', 'h', 'a', 'b'], 'a'))).toEqual(new Set(['g', 'h', 'a', 'b']));
    expect(workflowDragIds(nodes, ['g', 'b'], 'c')).toEqual(['c']);
    const next = moveWorkflowSelection({ ...graph(), nodes }, ['g', 'h', 'a', 'b'], 'a', 30, 40);
    expect((next.nodes as FlowNode[]).map((n) => n.x)).toEqual([30, 40, 50, 430, 700]);
  });
  it('focuses the project and selected node provided by global search', async () => {
    Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
    const host = document.createElement('div');
    document.body.append(host);
    const root = createRoot(host);
    const data = graph();
    data.nodes = [...data.nodes, node('target', { projectId: 'q', x: 600, y: 500 })];
    try {
      await act(async () =>
        root.render(createElement(Workflow, { data, projectId: 'q', nodeId: 'target', onSave: () => true })),
      );
      const select = host.querySelector('[aria-label="工作流项目"]')!;
      expect(select.textContent).toBe(data.projects.find(project => project.id === 'q')!.title);
      expect(host.querySelector('[aria-label="target"]')?.getAttribute('aria-pressed')).toBe('true');
      expect(select.getAttribute('role')).toBe('combobox');
    } finally {
      await act(async () => root.unmount());
      host.remove();
    }
  });
  it('refreshes imported dependencies when the canvas mounts', async () => {
    Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
    const host = document.createElement('div');
    document.body.append(host);
    const root = createRoot(host);
    function Harness() {
      const [data, setData] = useState(graph());
      return createElement(Workflow, {
        data,
        onSave: (next: Workspace) => {
          setData(next);
          return true;
        },
      });
    }
    try {
      await act(async () => root.render(createElement(Harness)));
      expect(host.querySelectorAll('.workflow-node')[1].textContent).toContain('锁定');
    } finally {
      await act(async () => root.unmount());
      host.remove();
    }
  });
  it('uses workflow task defaults and optional automatic layout', () => {
    const data = graph();
    data.preferences = {
      workflowDefaultPriority: 'high',
      workflowEstimateMinutes: 90,
      workflowAutoLayout: true,
    };
    const next = saveWorkflowNode(data, node('t', { taskId: 'new', x: 999, y: 999 }), true);
    const task = next.tasks.find((t) => t.id === 'new');
    expect(task?.priority).toBe('high');
    expect(task?.estimateMinutes).toBe(90);
    expect((next.nodes as FlowNode[]).find((n) => n.id === 't')?.x).not.toBe(999);
  });
  it('selects pasted nodes so deletion targets the new copy', async () => {
    Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
    const host = document.createElement('div');
    document.body.append(host);
    const root = createRoot(host);
    function Harness() {
      const [data, setData] = useState(graph());
      return createElement(Workflow, {
        data,
        onSave: (next: Workspace) => {
          setData(next);
          return true;
        },
      });
    }
    try {
      await act(async () => {
        root.render(createElement(Harness));
      });
      const original = host.querySelector<HTMLElement>('.workflow-node')!;
      await act(async () => {
        original.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true, ctrlKey: true, button: 0 }));
      });
      await act(async () => {
        host.querySelector<HTMLButtonElement>('button[aria-label="复制"]')!.click();
      });
      await act(async () => {
        host.querySelector<HTMLButtonElement>('button[aria-label="粘贴"]')!.click();
      });
      expect(host.querySelectorAll('.workflow-node')).toHaveLength(3);
      expect(original.getAttribute('aria-pressed')).toBe('false');
      expect(host.querySelectorAll('.workflow-node[aria-pressed="true"]')).toHaveLength(1);
    } finally {
      await act(async () => root.unmount());
      host.remove();
    }
  });
  it('rejects converting a populated group to a non-group kind', () => {
    const data = graph();
    data.nodes = [node('g', { kind: 'group' }), node('a', { groupId: 'g' })];
    expect(() => saveWorkflowNode(data, node('g', { kind: 'note' }))).toThrow();
  });
  it('copies collapsed nested groups and preserves branch/status metadata', () => {
    const data = graph();
    data.nodes = [
      node('g', { kind: 'group', collapsed: true }),
      node('h', { kind: 'group', groupId: 'g' }),
      node('a', { kind: 'condition', groupId: 'h', status: 'done', selectedBranchEdgeId: 'e' }),
      node('b', { groupId: 'h' }),
    ];
    const copy = copyWorkflowSelection(data, ['g']);
    expect(copy.nodes).toHaveLength(4);
    const pasted = pasteWorkflowSelection(data, copy, 'q');
    const cloned = (pasted.nodes as FlowNode[]).filter((n) => n.projectId === 'q');
    expect(cloned.find((n) => n.kind === 'condition')?.status).toBe('done');
    expect(cloned.find((n) => n.kind === 'condition')?.selectedBranchEdgeId).not.toBe('e');
  });
  it('does not unlock nodes when auto-unlock is disabled and honors skip policy', () => {
    const data = graph();
    data.nodes = [node('a', { status: 'skipped' }), node('b', { status: 'locked' })];
    data.preferences.workflowAutoUnlock = false;
    expect((refreshWorkflow(data).nodes[1] as FlowNode).status).toBe('locked');
    expect(dependenciesSatisfied(data, node('b'))).toBe(true);
    data.preferences.workflowSkipCompletes = false;
    expect(dependenciesSatisfied(data, node('b'))).toBe(false);
    data.preferences.workflowCheckDependencies = false;
    data.preferences.workflowAutoUnlock = true;
    expect((refreshWorkflow(data).nodes[1] as FlowNode).status).toBe('ready');
  });
  it('normalizes legacy omitted fields and rejects malformed unknown nodes', () => {
    const data = graph();
    data.nodes = [{ id: 'a', projectId: 'p', title: 'A' }];
    expect(workflowNodes(data)[0].status).toBe('ready');
    data.edges = [{ id: 'e', projectId: 'p', sourceId: 'a', targetId: 'b' }];
    expect(workflowEdges(data)[0].active).toBe(true);
    data.nodes = [null];
    expect(() => workflowNodes(data)).toThrow();
  });
  it('validates nested groups and creates linked task nodes', () => {
    let data = graph();
    data = saveWorkflowNode(data, node('g', { kind: 'group' }));
    data = saveWorkflowNode(data, node('h', { kind: 'group', groupId: 'g' }));
    expect(() => saveWorkflowNode(data, node('g', { kind: 'group', groupId: 'h' }))).toThrow();
    data = saveWorkflowNode(data, node('t', { taskId: 'new-task' }), true);
    expect(data.tasks.find((t) => t.id === 'new-task')?.title).toBe('t');
  });
  it('deletes selected edges and detaches group members', () => {
    const data = graph();
    data.nodes = [...data.nodes, node('g', { kind: 'group' }), node('h', { groupId: 'g' })];
    const next = deleteWorkflowSelection(data, ['g', 'a']);
    expect(next.edges).toHaveLength(0);
    expect((next.nodes as FlowNode[]).find((n) => n.id === 'h')?.groupId).toBeNull();
  });
  it('lays out predecessors before successors', () => {
    const laid = layoutWorkflow(graph(), 'p');
    expect((laid.nodes[0] as FlowNode).x).toBeLessThan((laid.nodes[1] as FlowNode).x);
  });
  it('guards starting locked nodes and mirrors completion to linked tasks', () => {
    const data = graph();
    data.tasks = [{ id: 't', title: 'T', status: 'todo', priority: 'normal' }];
    data.nodes = [node('a'), node('b', { taskId: 't', status: 'locked' })];
    expect(() => setNodeStatus(data, 'b', 'doing')).toThrow();
    expect(setNodeStatus(data, 'b', 'done').tasks[0].status).toBe('done');
    expect(archiveItem(data, 'tasks', 't', true).tasks[0].archived).toBe(true);
    expect(() => setEventActualMinutes(data, 'missing', -1)).toThrow();
  });
  it('locks dependent nodes, supports OR and selected condition exits', () => {
    const data = graph();
    expect(dependenciesSatisfied(data, node('b'))).toBe(false);
    data.nodes = [node('a', { kind: 'condition' }), node('b'), node('c')];
    data.edges = [
      ...(data.edges as object[]),
      { id: 'f', projectId: 'p', sourceId: 'a', targetId: 'c', active: true, delayMinutes: 0, label: '' },
    ];
    const next = selectBranch(data, 'a', 'e');
    expect(dependenciesSatisfied(next, node('b'))).toBe(true);
    expect(dependenciesSatisfied(next, node('c'))).toBe(false);
    next.nodes = [...next.nodes, node('d', { status: 'done' })];
    next.edges = [
      ...(next.edges as object[]),
      { id: 'g', projectId: 'p', sourceId: 'd', targetId: 'c', active: true, delayMinutes: 0, label: '' },
    ];
    expect(dependenciesSatisfied(next, node('c', { anyPredecessor: true }))).toBe(true);
  });
  it('waits for edge delay, then unlocks without executing downstream nodes', () => {
    const data = graph();
    data.nodes = [node('a', { status: 'done', completedAt: '2026-01-01T10:00:00Z' }), node('b')];
    (data.edges as Record<string, unknown>[])[0].delayMinutes = 30;
    expect((refreshWorkflow(data, new Date('2026-01-01T10:10:00Z')).nodes[1] as FlowNode).status).toBe(
      'waiting',
    );
    expect((refreshWorkflow(data, new Date('2026-01-01T10:30:00Z')).nodes[1] as FlowNode).status).toBe(
      'ready',
    );
  });
  it('preserves manual graph loops and moves nested group members', () => {
    const data = graph();
    expect(() =>
      addWorkflowEdge(data, {
        id: 'f',
        projectId: 'p',
        sourceId: 'b',
        targetId: 'a',
        active: true,
        delayMinutes: 0,
        label: '',
      }),
    ).not.toThrow();
    data.nodes = [node('g', { kind: 'group' }), node('a', { groupId: 'g' }), node('b', { groupId: 'a' })];
    expect((moveWorkflowNode(data, 'g', 10, 20).nodes as FlowNode[]).map((n) => n.x)).toEqual([10, 10, 10]);
  });
  it('copies internal edges and linked tasks and restores only one project history', () => {
    const data = graph();
    data.tasks = [
      { id: 't', title: 'T', status: 'todo', priority: 'normal', projectId: 'p' },
      { id: 'u', title: 'U', status: 'todo', priority: 'normal', projectId: 'q' },
    ];
    data.nodes = [node('a', { taskId: 't' }), node('b')];
    const snapshot = captureWorkflow(data, 'p');
    const pasted = pasteWorkflowSelection(data, copyWorkflowSelection(data, ['a', 'b']), 'p');
    expect(pasted.nodes).toHaveLength(4);
    expect(pasted.tasks).toHaveLength(3);
    expect(pasted.edges).toHaveLength(2);
    pasted.tasks[1].title = 'changed';
    const restored = restoreWorkflow(pasted, snapshot);
    expect(restored.nodes).toHaveLength(2);
    expect(restored.tasks).toHaveLength(2);
    expect(restored.tasks.find((t) => t.id === 'u')?.title).toBe('changed');
  });
});
