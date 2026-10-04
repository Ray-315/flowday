import { afterEach, describe, expect, it, vi } from 'vitest';
import { act, createElement } from 'react';
import { createRoot } from 'react-dom/client';
import { emptyWorkspace, type Workspace } from './workspace';
import { credentialVault, loginPreferences, workspaceStorage } from './storage';
import { FlowApi, ApiException, type AuthSession } from './api';
import App from './App';

const callbacks = vi.hoisted(() => ({
  authenticate: null as null | ((session: AuthSession | null, remember?: boolean) => Promise<void>),
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
vi.mock('./Account', () => ({
  Account: ({ onSession }: { onSession: (session: AuthSession | null, remember?: boolean) => Promise<void> }) => {
    callbacks.authenticate = onSession;
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
    subscribe() { return () => {}; }
    dispose() {}
  },
}));

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  callbacks.restore = callbacks.save = null;
  callbacks.authenticate = null;
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
      vi.spyOn(loginPreferences, 'read').mockReturnValue(true);
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

it.each(['failed-before', 'failed-after', 'stale-after', 'expired-after'] as const)('keeps a new login when restoration is %s', async timing => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  vi.stubGlobal('matchMedia', () => ({ matches: false, addEventListener() {}, removeEventListener() {} }));
  vi.stubGlobal('localStorage', { getItem: () => null, setItem() {}, removeItem() {} });
  vi.spyOn(loginPreferences, 'read').mockReturnValue(true);
  let resolveRead!: (value: string) => void;
  let rejectRead!: (reason: unknown) => void;
  vi.spyOn(credentialVault, 'read').mockImplementation(() => new Promise((resolve, reject) => { resolveRead = resolve; rejectRead = reject; }));
  vi.spyOn(credentialVault, 'write').mockResolvedValue();
  vi.spyOn(workspaceStorage, 'flush').mockResolvedValue();
  vi.spyOn(workspaceStorage, 'load').mockResolvedValue(emptyWorkspace());
  let rejectMe!: (reason: unknown) => void;
  const me = vi.spyOn(FlowApi.prototype, 'me').mockImplementation(() => new Promise((_resolve, reject) => { rejectMe = reject; }));
  const remove = vi.spyOn(credentialVault, 'delete').mockResolvedValue();
  const host = document.createElement('div');
  document.body.append(host);
  const root = createRoot(host);
  try {
    await act(async () => root.render(createElement(App)));
    if(timing === 'expired-after') await act(async () => resolveRead(JSON.stringify({token:'expired-test-token',user:{id:'old-user'}})));
    if(timing === 'failed-before') {
      await act(async () => rejectRead('钥匙串暂时不可用'));
      expect(host.textContent).toContain('钥匙串暂时不可用');
    }
    await act(async () => host.querySelector<HTMLButtonElement>('[aria-label="账号与安全"]')!.click());
    const user = { id:'new-user', email:'test@example.test', displayName:'新登录用户' };
    await act(async () => callbacks.authenticate!({token:'new-test-token',user}));
    if(timing === 'failed-after') await act(async () => rejectRead('旧请求失败'));
    if(timing === 'stale-after') await act(async () => resolveRead(JSON.stringify({token:'old-test-token',user:{...user,id:'old-user'}})));
    expect(host.textContent).toContain('新登录用户');
    expect(host.textContent).not.toContain('无法恢复登录会话');
    if(timing === 'expired-after') {
      await act(async () => rejectMe(new ApiException(401, 'UNAUTHORIZED', '登录已过期')));
      expect(host.textContent).toContain('新登录用户');
      expect(host.textContent).not.toContain('无法恢复登录会话');
    } else expect(me).not.toHaveBeenCalled();
    expect(remove).not.toHaveBeenCalled();
  } finally {
    await act(async () => root.unmount());
    host.remove();
  }
});

it('does not read or save tokens and clears any previous token when auto-login is disabled', async () => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  vi.stubGlobal('matchMedia', () => ({ matches:false, addEventListener() {}, removeEventListener() {} }));
  vi.spyOn(loginPreferences, 'read').mockReturnValue(false);
  const cache = new Map<string,string>();
  vi.stubGlobal('localStorage', { getItem:(key:string)=>cache.get(key)??null, setItem:(key:string,value:string)=>cache.set(key,value), removeItem:(key:string)=>cache.delete(key) });
  const read = vi.spyOn(credentialVault,'read');
  const write = vi.spyOn(credentialVault,'write');
  const remove = vi.spyOn(credentialVault,'delete').mockResolvedValue();
  vi.spyOn(workspaceStorage,'flush').mockResolvedValue();
  vi.spyOn(workspaceStorage,'load').mockResolvedValue(emptyWorkspace());
  const host = document.createElement('div');
  document.body.append(host);
  const root = createRoot(host);
  try {
    await act(async () => root.render(createElement(App)));
    await act(async () => host.querySelector<HTMLButtonElement>('[aria-label="账号与安全"]')!.click());
    await act(async () => callbacks.authenticate!({ token:'memory-only-token',user:{id:'user',email:'test@example.test',displayName:'临时登录用户'} }, false));
    expect(host.textContent).toContain('临时登录用户');
    expect(loginPreferences.read()).toBe(false);
    expect([...cache.values()].join('')).not.toContain('memory-only-token');
    await act(async () => callbacks.authenticate!(null));
    expect(read).not.toHaveBeenCalled();
    expect(write).not.toHaveBeenCalled();
    expect(remove).toHaveBeenCalledExactlyOnceWith('session');
  } finally {
    await act(async () => root.unmount());
    host.remove();
  }
});
