import { afterEach, describe, expect, it, vi } from 'vitest';
import { act, createElement } from 'react';
import { createRoot } from 'react-dom/client';
import { emptyWorkspace, type Workspace } from './workspace';
import { credentialVault, workspaceStorage } from './storage';
import { FlowApi } from './api';
import App from './App';

const callbacks = vi.hoisted(() => ({
  restore: null as null | ((data: Workspace) => boolean),
  save: null as null | ((data: Workspace) => boolean),
}));
vi.mock('./Management', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./Management')>()),
  LocalBackups: ({ onRestore }: { onRestore: (data: Workspace) => boolean }) => {
    callbacks.restore = onRestore;
    return null;
  },
  Preferences: ({ onSave }: { onSave: (data: Workspace) => boolean }) => {
    callbacks.save = onSave;
    return null;
  },
}));
vi.mock('./Tools', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./Tools')>()),
  ToolsDialog: ({ children }: { children: import('react').ReactNode }) => children,
}));
vi.mock('./api', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./api')>()),
  SyncController: class {
    constructor(
      _api: unknown,
      public session: unknown,
    ) {}
    async sync() {}
    dispose() {}
  },
}));

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  callbacks.restore = callbacks.save = null;
});

describe('account switching', () => {
  it.each(['restore', 'save'] as const)(
    'rejects a stale guest %s callback after session restoration',
    async (action) => {
      Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
      vi.stubGlobal('matchMedia', () => ({
        matches: false,
        addEventListener() {},
        removeEventListener() {},
      }));
      const entries = new Map<string, string>();
      vi.stubGlobal('localStorage', {
        getItem: (key: string) => entries.get(key) ?? null,
        setItem: (key: string, value: string) => entries.set(key, value),
        removeItem: (key: string) => entries.delete(key),
      });
      const user = { id: 'account-user', email: 'user@example.test', displayName: '用户' };
      let finishSession!: (source: string) => void;
      vi.spyOn(credentialVault, 'read').mockImplementation(
        () =>
          new Promise((resolve) => {
            finishSession = resolve;
          }),
      );
      vi.spyOn(FlowApi.prototype, 'me').mockResolvedValue(user);
      vi.spyOn(workspaceStorage, 'flush').mockResolvedValue(undefined);
      const account = {
        ...emptyWorkspace(),
        projects: [{ id: 'account-project', title: '账号项目', color: 1 }],
      };
      vi.spyOn(workspaceStorage, 'load').mockResolvedValue(account);
      const writes = vi.spyOn(workspaceStorage, 'save').mockImplementation(() => {});
      const protection = vi.spyOn(workspaceStorage, 'protect');
      const host = document.createElement('div');
      document.body.append(host);
      const root = createRoot(host);
      try {
        await act(async () => root.render(createElement(App)));
        const button = [...host.querySelectorAll('button')].find(
          (item) => item.textContent === (action === 'restore' ? '同步与备份' : '设置'),
        )!;
        await act(async () => button.click());
        await act(async () => new Promise(resolve=>setTimeout(resolve,350)));
        if (action === 'restore') {
          const local = [...host.querySelectorAll('button')].find(item => item.textContent === '本地备份')!;
          await act(async () => local.click());
        }
        const stale = action === 'restore' ? callbacks.restore : callbacks.save;
        expect(stale).not.toBeNull();
        await act(async () => finishSession(JSON.stringify({ token: 'test-session', user })));
        expect(host.textContent).toContain('账号项目');
        writes.mockClear();
        protection.mockClear();
        let result: boolean | undefined;
        await act(async () => {
          result = stale!({
            ...emptyWorkspace(),
            projects: [{ id: 'guest-project', title: '访客备份', color: 1 }],
          });
        });
        expect(result).toBe(false);
        expect(writes).not.toHaveBeenCalled();
        expect(protection).not.toHaveBeenCalled();
        expect(host.textContent).toContain('账号项目');
        expect(host.textContent).not.toContain('访客备份');
      } finally {
        await act(async () => root.unmount());
        host.remove();
      }
    },
  );
});
