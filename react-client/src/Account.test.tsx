import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { expect, it, vi } from 'vitest';
import { Account } from './Account';
import { FlowApi } from './api';

it.each(['login', 'register'] as const)('shows native credential errors after successful %s without reporting an API failure', async mode => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  const host = document.createElement('div');
  document.body.append(host);
  const root = createRoot(host);
  const session = { token: 'test-token', user: { id: 'test-user', email: 'test@example.com', displayName: 'Test' } };
  const api = new FlowApi();
  const authenticate = vi.spyOn(api, mode).mockResolvedValue(session);
  const onSession = vi.fn().mockRejectedValue('无法保存登录信息到 macOS 钥匙串');
  try {
    await act(() => root.render(<Account api={api} session={null} onSession={onSession} sync={null} />));
    if (mode === 'register') await act(() => host.querySelector<HTMLButtonElement>('.auth-switch')!.click());
    await act(async () => host.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })));
    expect(authenticate).toHaveBeenCalledOnce();
    expect(onSession).toHaveBeenCalledWith(session);
    expect(host.querySelector('[role="alert"]')?.textContent).toContain('无法保存登录信息到 macOS 钥匙串');
    expect(host.querySelector('[role="alert"]')?.textContent).toContain(mode === 'register' ? '账号已创建' : '账号验证成功');
    expect(host.querySelector<HTMLButtonElement>('.auth-submit')!.disabled).toBe(false);
  } finally {
    await act(() => root.unmount());
    host.remove();
    vi.restoreAllMocks();
  }
});
