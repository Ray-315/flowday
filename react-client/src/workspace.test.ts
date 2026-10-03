import { describe, expect, it } from 'vitest';
import { act, createElement } from 'react';
import { createRoot } from 'react-dom/client';
import { Preferences } from './Management';
import {
  emptyWorkspace,
  parseWorkspace,
  saveTask,
  toggleTask,
  eventsForDay,
  layoutEvents,
} from './workspace';

describe('workspace', () => {
  it('binds the skip preference to the dependency engine setting', async () => {
    Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
    const host = document.createElement('div');
    document.body.append(host);
    const root = createRoot(host);
    const data = { ...emptyWorkspace(), preferences: { workflowSkipCompletes: false } };
    let saved = data;
    try {
      await act(async () =>
        root.render(
          createElement(Preferences, {
            data,
            section: 'workflow',
            onSave: (next) => {
              saved = next as typeof data;
              return true;
            },
          }),
        ),
      );
      const label = [...host.querySelectorAll('label')].find((label) =>
        label.textContent?.includes('跳过节点视为完成'),
      )!;
      const input = label.querySelector('input')!;
      expect(input.checked).toBe(false);
      await act(async () => input.click());
      expect(saved.preferences.workflowSkipCompletes).toBe(true);
      expect(saved.preferences).not.toHaveProperty('workflowSkipUnlock');
    } finally {
      await act(async () => root.unmount());
      host.remove();
    }
  });
  type ValidationFixture = {
    schemaVersion: number;
    tasks: Record<string, unknown>[];
    projects: Record<string, unknown>[];
    nodes: Record<string, unknown>[];
    edges: Record<string, unknown>[];
    events: Record<string, unknown>[];
    captures: unknown[];
    notices: unknown[];
    preferences: Record<string, unknown>;
  };
  const validGraph = (): ValidationFixture => ({
    ...emptyWorkspace(),
    captures: [],
    notices: [],
    projects: [{ id: 'p', title: '项目', color: 1 }],
    tasks: [{ id: 't', title: '任务', status: 'todo', priority: 'normal', projectId: 'p' }],
    nodes: [{ id: 'n', title: '节点', projectId: 'p', taskId: 't', kind: 'task', status: 'ready' }],
    edges: [],
  });
  it.each([
    [
      'malformed node',
      (data: ValidationFixture) => {
        data.nodes = [{ id: 'broken' }];
      },
    ],
    [
      'bad node kind',
      (data: ValidationFixture) => {
        data.nodes[0].kind = 'execute';
      },
    ],
    [
      'bad node coordinates',
      (data: ValidationFixture) => {
        data.nodes[0].x = '1';
      },
    ],
    [
      'missing task project',
      (data: ValidationFixture) => {
        data.tasks[0].projectId = 'missing';
      },
    ],
    [
      'invalid tags',
      (data: ValidationFixture) => {
        data.tasks[0].tags = [42];
      },
    ],
    [
      'invalid attachment',
      (data: ValidationFixture) => {
        data.tasks[0].attachments = [{ id: 'a', title: '资料', kind: 'executable', content: 'x' }];
      },
    ],
    [
      'negative minutes',
      (data: ValidationFixture) => {
        data.tasks[0].actualMinutes = -1;
      },
    ],
    [
      'repeat interval bound',
      (data: ValidationFixture) => {
        data.tasks[0].repeatRule = { frequency: 'daily', interval: 367 };
      },
    ],
    [
      'repeat count bound',
      (data: ValidationFixture) => {
        data.tasks[0].repeatRule = { frequency: 'daily', interval: 1, count: 1001 };
      },
    ],
    [
      'project cycle',
      (data: ValidationFixture) => {
        data.projects[0].parentId = 'p';
      },
    ],
    [
      'task cycle',
      (data: ValidationFixture) => {
        data.tasks[0].parentId = 't';
      },
    ],
    [
      'group cycle',
      (data: ValidationFixture) => {
        data.nodes[0].kind = 'group';
        data.nodes[0].groupId = 'n';
      },
    ],
    [
      'nongroup parent',
      (data: ValidationFixture) => {
        data.nodes.push({ id: 'child', title: '子节点', projectId: 'p', groupId: 'n' });
      },
    ],
    [
      'crossproject edge',
      (data: ValidationFixture) => {
        data.projects.push({ id: 'q', title: 'Q', color: 1 });
        data.nodes.push({ id: 'm', title: 'M', projectId: 'q' });
        data.edges.push({ id: 'e', projectId: 'p', sourceId: 'n', targetId: 'm' });
      },
    ],
    [
      'invalid branch',
      (data: ValidationFixture) => {
        data.nodes[0].selectedBranchEdgeId = 'missing';
      },
    ],
    [
      'invalid reminder rule',
      (data: ValidationFixture) => {
        data.events = [
          {
            id: 'e',
            title: 'E',
            start: '2026-01-01T09:00:00Z',
            end: '2026-01-01T10:00:00Z',
            reminderRules: [{ leadMinutes: 5, dueAt: '2026-01-01T08:00:00Z' }],
          },
        ];
      },
    ],
    [
      'invalid known preference',
      (data: ValidationFixture) => {
        data.preferences.workflowSkipCompletes = 'false';
      },
    ],
    [
      'credential in preferences',
      (data: ValidationFixture) => {
        data.preferences.apiToken = 'never-store-credentials';
      },
    ],
  ])('rejects %s before a backup can replace data', (_name, mutate) => {
    const data = validGraph();
    mutate(data);
    expect(() => parseWorkspace(JSON.stringify(data))).toThrow();
  });
  it('preserves unknown extension fields and valid manual workflow loops', () => {
    const data = {
      ...validGraph(),
      extension: { future: true },
      tasks: [
        { ...validGraph().tasks[0], futureProperty: { retained: 1 }, repeatRule: { frequency: 'weekly' } },
      ],
      edges: [{ id: 'e', projectId: 'p', sourceId: 'n', targetId: 'n' }],
    };
    const parsed = parseWorkspace(JSON.stringify(data));
    expect(parsed.extension).toEqual({ future: true });
    expect(parsed.tasks[0].futureProperty).toEqual({ retained: 1 });
    expect(parsed.tasks[0].repeatRule).toEqual({ frequency: 'weekly', interval: 1 });
    expect(parsed.edges).toEqual(data.edges);
  });
  it('accepts omitted optional server fields with Flutter defaults while rejecting invalid provided fields', () => {
    const minimal = {
      ...emptyWorkspace(),
      tasks: [{ id: 't', title: '任务' }],
      projects: [{ id: 'p', title: '项目' }],
      events: [{ id: 'e', title: '排程', start: '2026-10-03T10:00:00Z', end: '2026-10-03T11:00:00Z' }],
    };
    const parsed = parseWorkspace(JSON.stringify(minimal));
    expect(parsed.tasks[0].status).toBe('todo');
    expect(parsed.tasks[0].priority).toBe('normal');
    expect(parsed.events[0].color).toBe(0xff2680ff);
    expect(parsed.projects[0].color).toBe(0xff2680ff);
    expect(() =>
      parseWorkspace(JSON.stringify({ ...minimal, projects: [{ id: 'p', title: '项目', color: null }] })),
    ).toThrow();
  });
  it('rejects corrupt and unsupported backups', () => {
    expect(() => parseWorkspace('{')).toThrow();
    expect(() => parseWorkspace('{"schemaVersion":2}')).toThrow();
    expect(() =>
      parseWorkspace(
        JSON.stringify({ ...emptyWorkspace(), tasks: [{ id: 't', title: 'x', status: 'invalid' }] }),
      ),
    ).toThrow();
  });
  it('preserves workflow and unknown task fields during edits and export', () => {
    const original = {
      ...emptyWorkspace(),
      projects: [{ id: 'p', title: '项目', color: 1 }],
      nodes: [{ id: 'n', title: '保留', projectId: 'p' }],
      tasks: [
        {
          id: 't',
          title: '旧任务',
          status: 'todo',
          priority: 'normal',
          tags: ['论文'],
          estimateMinutes: 60,
          repeatRule: { frequency: 'daily' },
        },
      ],
    };
    const data = parseWorkspace(JSON.stringify(original));
    const next = saveTask(data, {
      id: 't',
      title: '新任务',
      priority: 'high',
      deadline: null,
      projectId: null,
    });
    expect(next.nodes).toEqual(original.nodes);
    expect(next.tasks[0].repeatRule).toEqual({ ...original.tasks[0].repeatRule, interval: 1 });
    expect(next.tasks[0].tags).toEqual(['论文']);
    expect(next.tasks[0].title).toBe('新任务');
    expect(data.tasks[0].title).toBe('旧任务');
  });
  it('completes a task and allows undo while preserving related data', () => {
    const data = saveTask(emptyWorkspace(), {
      title: '写论文',
      priority: 'normal',
      deadline: null,
      projectId: null,
    });
    const done = toggleTask(data, data.tasks[0].id);
    expect(done.tasks[0].status).toBe('done');
    expect(done.tasks[0].completedAt).toBeTruthy();
    const undone = toggleTask(done, data.tasks[0].id);
    expect(undone.tasks[0].status).toBe('todo');
    expect(undone.tasks[0].completedAt).toBeNull();
  });
  it('includes overnight events only on intersecting days and excludes deleted events', () => {
    const data = emptyWorkspace();
    data.events = [
      { id: 'e', title: '跨天', start: '2026-10-03T23:00:00', end: '2026-10-04T01:00:00', color: 0xff237bff },
      {
        id: 'deleted',
        title: '已删',
        start: '2026-10-04T09:00:00',
        end: '2026-10-04T10:00:00',
        color: 0xff237bff,
        deletedAt: '2026-10-03T12:00:00',
      },
    ];
    expect(eventsForDay(data, '2026-10-03')).toHaveLength(1);
    expect(eventsForDay(data, '2026-10-04')).toHaveLength(1);
    expect(eventsForDay(data, '2026-10-05')).toHaveLength(0);
  });
  it('positions overlapping events in separate columns', () => {
    const items = [
      { id: 'a', title: 'A', start: '2026-10-03T09:00:00', end: '2026-10-03T11:00:00', color: 0xff237bff },
      { id: 'b', title: 'B', start: '2026-10-03T10:00:00', end: '2026-10-03T12:00:00', color: 0xff237bff },
      { id: 'c', title: 'C', start: '2026-10-03T12:00:00', end: '2026-10-03T13:00:00', color: 0xff237bff },
    ];
    const result = layoutEvents(items, '2026-10-03');
    expect(result[0].columns).toBe(2);
    expect(result[1].column).not.toBe(result[0].column);
    expect(result[2].columns).toBe(1);
  });
});
