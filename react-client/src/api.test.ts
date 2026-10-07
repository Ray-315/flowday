import { describe, expect, it, vi } from 'vitest';
import {
  ApiException,
  FlowApi,
  SyncController,
  normalizeEndpoint,
  type ApiTransport,
  type AuthSession,
} from './api';
import { emptyWorkspace } from './workspace';
const session: AuthSession = {
  token: 'private-token',
  user: { id: 'u1', email: 'a@example.test', displayName: 'A' },
};
const ok = (value: unknown) => ({ status: 200, body: JSON.stringify(value) });
describe('API transport', () => {
  it('requires HTTPS except exact loopback and rejects credentials', () => {
    expect(normalizeEndpoint('http://127.0.0.1:3108')).toBe('http://127.0.0.1:3108/api/v1');
    expect(normalizeEndpoint('https://flowday.mtrx.pro/api/v1/')).toBe('https://flowday.mtrx.pro/api/v1');
    for (const url of [
      'http://example.test',
      'https://user:password@example.test',
      'https://example.test?token=secret',
    ])
      expect(() => normalizeEndpoint(url)).toThrow();
  });
  it('allows AI preview to finish beyond the ordinary client deadline', async () => {
    vi.useFakeTimers();
    try {
      const api = new FlowApi('http://localhost', async () => {
        await new Promise(resolve => setTimeout(resolve, 25000));
        return ok({ previewId: 'ready' });
      });
      const pending = api.feature(session.token, 'POST', '/ai/preview', { text: '明天开会', timezone: 'Asia/Shanghai' });
      await vi.advanceTimersByTimeAsync(25000);
      await expect(pending).resolves.toMatchObject({ previewId: 'ready' });
    } finally { vi.useRealTimers(); }
  });
  it('passes CAS and token only through transport and preserves conflict version', async () => {
    const send = vi.fn<ApiTransport>(async () => ({
      status: 409,
      body: JSON.stringify({
        error: { code: 'VERSION_CONFLICT', message: 'private-token' },
        currentVersion: 4,
      }),
    }));
    const api = new FlowApi('http://localhost:3108', send);
    try {
      await api.putWorkspace(session.token, 3, emptyWorkspace());
      throw new Error('missing conflict');
    } catch (error) {
      expect(error).toBeInstanceOf(ApiException);
      expect(error).toMatchObject({ status: 409, code: 'VERSION_CONFLICT', currentVersion: 4 });
      expect(String(error)).not.toContain(session.token);
    }
    expect(JSON.parse(send.mock.calls[0][0].body!)).toMatchObject({ baseVersion: 3 });
    expect(send.mock.calls[0][0].token).toBe(session.token);
  });
  it('times out hung requests and aborts browser transport signal', async () => {
    let signal: AbortSignal | undefined;
    const api = new FlowApi(
      'http://localhost',
      async (request) => {
        signal = request.signal;
        return new Promise(() => {});
      },
      5,
    );
    await expect(api.getWorkspace('token')).rejects.toMatchObject({ code: 'TIMEOUT' });
    expect(signal?.aborted).toBe(true);
  });
  it('validates auth and workspace responses', async () => {
    const api = new FlowApi('http://localhost', async () => ok({ token: 2, user: {} }));
    await expect(api.login('a@example.test', 'password')).rejects.toMatchObject({ code: 'INVALID_RESPONSE' });
    const corrupt = new FlowApi('http://localhost', async () => ok({ version: '1', data: emptyWorkspace() }));
    await expect(corrupt.getWorkspace('token')).rejects.toMatchObject({ code: 'INVALID_RESPONSE' });
  });
});
describe('CAS synchronization', () => {
  it('marks conflict when edits happen while replacement persistence awaits disk', async () => {
    let data = emptyWorkspace();
    const api = new FlowApi('http://localhost', async () =>
      ok({ version: 1, data: { ...emptyWorkspace(), preferences: { theme: 'dark' } } }),
    );
    const sync = new SyncController(api, session, {
      read: () => data,
      backup: async () => {},
      replace: async () => {
        data = { ...data, preferences: { theme: 'light' } };
        throw new Error('本地数据已修改');
      },
    });
    await sync.sync();
    expect(sync.conflict).toBe(true);
    expect(data.preferences.theme).toBe('light');
    expect(sync.baseVersion).toBeUndefined();
  });
  it('stops repeated requests after a session expires', async () => {
    const send = vi.fn<ApiTransport>(async () => ({
      status: 401,
      body: JSON.stringify({ error: { code: 'UNAUTHORIZED' } }),
    }));
    const sync = new SyncController(new FlowApi('http://localhost', send), session, {
      read: emptyWorkspace,
      replace: vi.fn(),
      backup: vi.fn(),
    });
    await sync.sync();
    await sync.sync();
    expect(sync.unauthorized).toBe(true);
    expect(send).toHaveBeenCalledOnce();
    await expect(sync.remoteMutation(async () => {})).rejects.toThrow('登录已过期');
  });
  it('retains edits created during upload as dirty against the exact uploaded baseline', async () => {
    let data = { ...emptyWorkspace(), preferences: { theme: 'dark' } };
    const original = JSON.stringify(data);
    const send: ApiTransport = async (request) => {
      if (request.method === 'GET') return ok({ version: 1, data: emptyWorkspace() });
      data = { ...data, preferences: { theme: 'light' } };
      return ok({ version: 2 });
    };
    const sync = new SyncController(new FlowApi('http://localhost', send), session, {
      read: () => data,
      replace: vi.fn(),
      backup: vi.fn(),
      baseline: { version: 1, json: JSON.stringify(emptyWorkspace()) },
    });
    await sync.sync();
    expect(data.preferences.theme).toBe('light');
    expect(sync.lastSyncedJson).toBe(original);
    expect(sync.localDirty).toBe(true);
  });
  it('does not retry or advance the baseline when CAS upload fails', async () => {
    const send = vi.fn<ApiTransport>(async (request) =>
      request.method === 'GET'
        ? ok({ version: 1, data: emptyWorkspace() })
        : { status: 409, body: JSON.stringify({ error: { code: 'VERSION_CONFLICT' }, currentVersion: 2 }) },
    );
    const original = { ...emptyWorkspace(), preferences: { theme: 'dark' } };
    const baseline = JSON.stringify(emptyWorkspace());
    const sync = new SyncController(new FlowApi('http://localhost', send), session, {
      read: () => original,
      replace: vi.fn(),
      backup: vi.fn(),
      baseline: { version: 1, json: baseline },
    });
    await sync.sync();
    await sync.sync();
    expect(sync.conflict).toBe(true);
    expect(sync.baseVersion).toBe(1);
    expect(sync.lastSyncedJson).toBe(baseline);
    expect(send).toHaveBeenCalledTimes(2);
  });
  it('keeps local data on first-sync difference without blindly uploading', async () => {
    const data = { ...emptyWorkspace(), preferences: { theme: 'dark' } };
    const send = vi.fn<ApiTransport>(async () => ok({ version: 1, data: emptyWorkspace() }));
    const replace = vi.fn();
    const backup = vi.fn();
    const sync = new SyncController(new FlowApi('http://localhost', send), session, {
      read: () => data,
      replace,
      backup,
    });
    await sync.sync();
    expect(sync.conflict).toBe(true);
    expect(replace).not.toHaveBeenCalled();
    expect(backup).not.toHaveBeenCalled();
    expect(send).toHaveBeenCalledTimes(1);
  });
  it('backs up before replacing and rejects local edits made while backup runs', async () => {
    let data = emptyWorkspace();
    const remote = { ...emptyWorkspace(), preferences: { theme: 'dark' } };
    const replace = vi.fn();
    const sync = new SyncController(
      new FlowApi('http://localhost', async () => ok({ version: 1, data: remote })),
      session,
      {
        read: () => data,
        replace,
        backup: async () => {
          data = { ...data, preferences: { theme: 'light' } };
        },
      },
    );
    await sync.sync();
    expect(sync.conflict).toBe(true);
    expect(replace).not.toHaveBeenCalled();
    expect(data.preferences.theme).toBe('light');
  });
  it('uses server CAS version on explicit local choice and saves exact sent baseline', async () => {
    const data = { ...emptyWorkspace(), preferences: { theme: 'dark' } };
    const send = vi.fn<ApiTransport>(async (request) =>
      request.method === 'GET' ? ok({ version: 8, data: emptyWorkspace() }) : ok({ version: 9 }),
    );
    const saveBaseline = vi.fn();
    const backup = vi.fn(async () => {});
    const sync = new SyncController(new FlowApi('http://localhost', send), session, {
      read: () => data,
      replace: vi.fn(),
      backup,
      saveBaseline,
    });
    await sync.resolveUploadLocal();
    expect(backup).toHaveBeenCalledOnce();
    expect(JSON.parse(send.mock.calls[1][0].body!).baseVersion).toBe(8);
    expect(saveBaseline).toHaveBeenCalledWith(9, JSON.stringify(data));
  });
  it('preserves edits arriving during a remote mutation and signals conflict', async () => {
    let data = emptyWorkspace();
    const replace = vi.fn();
    const api = new FlowApi('http://localhost', async () => ok({ version: 1, data: emptyWorkspace() }));
    const sync = new SyncController(api, session, { read: () => data, replace, backup: vi.fn() });
    await expect(
      sync.remoteMutation(async () => {
        data = { ...data, preferences: { theme: 'dark' } };
      }),
    ).rejects.toThrow('冲突');
    expect(data.preferences.theme).toBe('dark');
    expect(replace).not.toHaveBeenCalled();
  });
  it('disposal stops a previous account request from replacing current account data', async () => {
    let finish!: (value: ReturnType<typeof ok>) => void;
    const api = new FlowApi(
      'http://localhost',
      () =>
        new Promise((resolve) => {
          finish = resolve;
        }),
    );
    const replace = vi.fn();
    const sync = new SyncController(api, session, { read: emptyWorkspace, replace, backup: vi.fn() });
    const pending = sync.sync();
    sync.dispose();
    finish(ok({ version: 2, data: { ...emptyWorkspace(), preferences: { theme: 'dark' } } }));
    await pending;
    expect(replace).not.toHaveBeenCalled();
    expect(sync.baseVersion).toBeUndefined();
  });
});
