import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { Services } from './Services';
import { FlowApi, SyncController, type ApiTransport } from './api';
import { emptyWorkspace } from './workspace';
let container: HTMLDivElement;
let root: Root;
beforeEach(() => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  container = document.createElement('div');
  document.body.append(container);
  root = createRoot(container);
});
afterEach(async () => {
  await act(async () => root.unmount());
  container.remove();
});
const session = {
  token: 'session-secret',
  user: { id: 'u', email: 'test@example.test', displayName: 'Test' },
};
async function click(caption: string) {
  const button = [...container.querySelectorAll('button')].find((item) => item.textContent === caption);
  expect(button).toBeDefined();
  await act(async () => button!.click());
}
async function input(caption: string, value: string) {
  const field = [...container.querySelectorAll('label')]
    .find((item) => item.textContent === caption)
    ?.querySelector('input');
  expect(field).toBeDefined();
  await act(async () => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(field, value);
    field!.dispatchEvent(new Event('input', { bubbles: true }));
    field!.dispatchEvent(new Event('change', { bubbles: true }));
  });
}
it('scheduling uses selected timezone for ranges and exclusions rather than system timezone', async () => {
  const workspace = {
    ...emptyWorkspace(),
    preferences: { timezone: 'Asia/Kolkata' },
    tasks: [{ id: 't', title: '任务', status: 'todo', priority: 'normal' }],
  };
  const send = vi.fn<ApiTransport>(async (request) => ({
    status: 200,
    body: JSON.stringify(
      request.path === '/workspace'
        ? { version: 1, data: workspace }
        : request.path === '/audit'
          ? { records: [] }
          : {
              previewId: 'p',
              baseVersion: 1,
              expiresAt: new Date(Date.now() + 60000).toISOString(),
              candidates: [{ id: 'c', label: '方案', intent: { actions: [] } }],
            },
    ),
  }));
  const api = new FlowApi('http://localhost', send);
  const sync = new SyncController(api, session, {
    read: () => workspace,
    replace: async () => {},
    backup: async () => {},
  });
  await act(async () =>
    root.render(<Services api={api} session={session} sync={sync} workspace={workspace} />),
  );
  await input('排程开始', '2026-11-01T08:00');
  await input('排程结束', '2026-11-02T18:00');
  await input('排除开始', '2026-11-01T12:00');
  await input('排除结束', '2026-11-01T13:00');
  await act(async () =>
    container
      .querySelectorAll('form')[2]
      .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })),
  );
  await act(async () => container.querySelector<HTMLInputElement>('.service-choice input')!.click());
  await act(async () =>
    container
      .querySelectorAll('form')[1]
      .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })),
  );
  const schedule = send.mock.calls.find(([request]) => request.path === '/ai/schedule')?.[0];
  expect(JSON.parse(schedule!.body!)).toMatchObject({
    taskIds: ['t'],
    timezone: 'Asia/Kolkata',
    start: '2026-11-01T02:30:00.000Z',
    end: '2026-11-02T12:30:00.000Z',
    excluded: [{ start: '2026-11-01T06:30:00.000Z', end: '2026-11-01T07:30:00.000Z' }],
  });
});
it('AI preview is read-only and commits only selected server-owned actions', async () => {
  let version = 1;
  const send = vi.fn<ApiTransport>(async (request) => {
    const data =
      request.path === '/workspace'
        ? { version, data: emptyWorkspace() }
        : request.path === '/audit'
          ? { records: [] }
          : request.path === '/ai/preview'
            ? {
                previewId: 'preview',
                baseVersion: 1,
                expiresAt: new Date(Date.now() + 60000).toISOString(),
                candidates: [
                  {
                    id: 'candidate',
                    label: '方案一',
                    intent: {
                      actions: [
                        { type: 'todo', title: '任务一' },
                        { type: 'todo', title: '任务二' },
                      ],
                    },
                  },
                ],
              }
            : request.path === '/ai/apply'
              ? { version: ++version, applied: true, auditId: 'audit' }
              : {};
    return { status: 200, body: JSON.stringify(data) };
  });
  const api = new FlowApi('http://localhost', send);
  const sync = new SyncController(api, session, {
    read: emptyWorkspace,
    replace: async () => {},
    backup: async () => {},
  });
  await act(async () =>
    root.render(<Services api={api} session={session} sync={sync} workspace={emptyWorkspace()} />),
  );
  await act(async () =>
    container.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })),
  );
  expect(send.mock.calls.some(([request]) => request.path === '/ai/apply')).toBe(false);
  const checkboxes = container.querySelectorAll<HTMLInputElement>('.service-choice input[type=checkbox]');
  await act(async () => checkboxes[checkboxes.length - 1].click());
  await click('确认应用');
  const apply = send.mock.calls.find(([request]) => request.path === '/ai/apply')?.[0];
  expect(JSON.parse(apply!.body!)).toEqual({
    previewId: 'preview',
    baseVersion: 1,
    candidateId: 'candidate',
    actionIndexes: [0],
  });
});
it('reminder signed action requires a separate confirmation before execution', async () => {
  const send = vi.fn<ApiTransport>(async (request) => ({
    status: 200,
    body: JSON.stringify(
      request.path === '/audit'
        ? { records: [] }
        : request.path === '/reminders'
          ? {
              reminders: [{ id: 'r', title: '提醒一', dueAt: new Date().toISOString(), acknowledged: false }],
            }
          : request.path.endsWith('/actions')
            ? { token: 'signed-secret', expiresAt: new Date(Date.now() + 60000).toISOString() }
            : { executed: true, action: 'ack' },
    ),
  }));
  const api = new FlowApi('http://localhost', send);
  const sync = new SyncController(api, session, {
    read: emptyWorkspace,
    replace: async () => {},
    backup: async () => {},
  });
  await act(async () =>
    root.render(<Services api={api} session={session} sync={sync} workspace={emptyWorkspace()} />),
  );
  await click('提醒');
  await click('确认');
  expect(send.mock.calls.some(([request]) => request.path === '/reminder-actions')).toBe(false);
  await click('确认执行');
  const execute = send.mock.calls.find(([request]) => request.path === '/reminder-actions')?.[0];
  expect(execute?.token).toBeUndefined();
  expect(JSON.parse(execute!.body!)).toEqual({ token: 'signed-secret' });
  expect(container.textContent).not.toContain('signed-secret');
  expect(container.textContent).not.toContain(session.token);
});
