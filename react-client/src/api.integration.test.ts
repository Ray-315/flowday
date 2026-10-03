// @vitest-environment node
import { afterEach, beforeEach, expect, it } from 'vitest';
import { FlowApi, type ApiTransport } from './api';
import { emptyWorkspace } from './workspace';
type InjectResponse = { statusCode: number; body: string };
type TestServer = {
  app: {
    inject: (request: {
      method: string;
      url: string;
      payload?: string;
      headers: Record<string, string>;
    }) => Promise<InjectResponse>;
    close: () => Promise<void>;
  };
};
let context: TestServer;
let api: FlowApi;
let codes: Map<string, string>;
beforeEach(async () => {
  const modulePath = new URL('../../server/src/app.js', import.meta.url).href;
  const { createApp } = await import(/* @vite-ignore */ modulePath);
  codes = new Map();
  context = await createApp({
    databasePath: ':memory:',
    worker: false,
    env: { ACTION_SIGNING_KEY: 'test-only-signing-key-0123456789' },
    sendRegistrationEmail: async ({ email, code }: { email: string; code: string }) => {
      codes.set(email, code);
    },
  });
  const transport: ApiTransport = async (request) => {
    const response = await context.app.inject({
      method: request.method,
      url: `/api/v1${request.path}`,
      payload: request.body,
      headers: {
        ...(request.body ? { 'content-type': 'application/json' } : {}),
        ...(request.token ? { authorization: `Bearer ${request.token}` } : {}),
      },
    });
    return { status: response.statusCode, body: response.body };
  };
  api = new FlowApi('http://localhost', transport);
});
afterEach(async () => {
  await context?.app.close();
});
async function register(email: string) {
  await api.sendRegistrationCode(email);
  return api.register(email, 'test-password-012345', '测试账号', codes.get(email)!);
}
it('selected today module preferences and system timezone round-trip through real workspace validation', async () => {
  const session = await register('preferences@example.test');
  const preferences = {
    todayModuleOrder: ['todo', 'timeline', 'calendar'],
    todayHiddenModules: ['workflow', 'pressure'],
    timezone: 'system',
    autoSync: true,
  };
  expect(await api.putWorkspace(session.token, 0, { ...emptyWorkspace(), preferences })).toBe(1);
  expect((await api.getWorkspace(session.token)).data.preferences).toEqual(preferences);
});
it('real registration, session identity, isolated workspace and CAS protocols match the client', async () => {
  const a = await register('a@example.test');
  const b = await register('b@example.test');
  expect(await api.me(a.token)).toEqual(a.user);
  const snapshot = await api.getWorkspace(a.token);
  expect(snapshot.version).toBe(0);
  const data = {
    ...emptyWorkspace(),
    tasks: [{ id: 'task-a', title: '私有任务', status: 'todo', priority: 'normal' }],
  };
  expect(await api.putWorkspace(a.token, 0, data)).toBe(1);
  await expect(api.putWorkspace(a.token, 0, emptyWorkspace())).rejects.toMatchObject({
    status: 409,
    code: 'VERSION_CONFLICT',
    currentVersion: 1,
  });
  expect((await api.getWorkspace(b.token)).data.tasks).toEqual([]);
  await api.feature(a.token, 'POST', '/auth/logout');
  await expect(api.me(a.token)).rejects.toMatchObject({ status: 401 });
});
it('real backup restore CAS and signed reminder execution match the service forms', async () => {
  const session = await register('services@example.test');
  const backup = await api.feature(session.token, 'POST', '/backups');
  await api.putWorkspace(session.token, 0, { ...emptyWorkspace(), preferences: { themeMode: 'dark' } });
  await expect(
    api.feature(session.token, 'POST', `/backups/${backup.id}/restore`, { baseVersion: 0 }),
  ).rejects.toMatchObject({ status: 409 });
  const restored = await api.feature(session.token, 'POST', `/backups/${backup.id}/restore`, {
    baseVersion: 1,
  });
  expect(restored.version).toBe(2);
  expect(restored.protectionBackup).toBeDefined();
  const result = await api.feature(session.token, 'POST', '/reminders', {
    title: '测试提醒',
    dueAt: new Date(Date.now() + 3600000).toISOString(),
  });
  const reminder = result.reminder as { id: string };
  const signed = await api.feature(session.token, 'POST', `/reminders/${reminder.id}/actions`, {
    action: 'ack',
  });
  expect((await api.request('POST', '/reminder-actions', undefined, { token: signed.token })).executed).toBe(
    true,
  );
  await expect(
    api.request('POST', '/reminder-actions', undefined, { token: signed.token }),
  ).rejects.toMatchObject({ status: 410 });
});
it('real scheduling preview, partial apply, retry and undo keep server-owned action semantics', async () => {
  const session = await register('schedule@example.test');
  await api.putWorkspace(session.token, 0, {
    ...emptyWorkspace(),
    tasks: [
      { id: 't1', title: '任务一', status: 'todo', priority: 'normal', estimateMinutes: 45 },
      { id: 't2', title: '任务二', status: 'todo', priority: 'normal', estimateMinutes: 45 },
    ],
  });
  const preview = await api.feature(session.token, 'POST', '/ai/schedule', {
    taskIds: ['t1', 't2'],
    start: new Date(Date.now() + 86400000).toISOString(),
    end: new Date(Date.now() + 172800000).toISOString(),
    timezone: 'Asia/Shanghai',
    excluded: [],
  });
  expect((await api.getWorkspace(session.token)).data.events).toHaveLength(0);
  const candidates = preview.candidates as { id: string }[];
  const body = {
    previewId: preview.previewId,
    baseVersion: preview.baseVersion,
    candidateId: candidates[0].id,
    actionIndexes: [0],
  };
  const applied = await api.feature(session.token, 'POST', '/ai/apply', body);
  expect((await api.getWorkspace(session.token)).data.events).toHaveLength(1);
  expect((await api.feature(session.token, 'POST', '/ai/apply', body)).version).toBe(applied.version);
  const undone = await api.feature(session.token, 'POST', `/audit/${applied.auditId}/undo`, {
    baseVersion: applied.version,
  });
  expect(undone.undone).toBe(true);
  const workspace = await api.getWorkspace(session.token);
  expect(workspace.data.tasks).toHaveLength(2);
  expect(workspace.data.events).toHaveLength(0);
});
