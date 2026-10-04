import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { expect, it, vi } from 'vitest';
import { MobileNavigation } from './MobileNavigation';
it('keeps attachments under tasks and settings under More, and switches destinations', async () => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  const host = document.createElement('div');
  const root = createRoot(host);
  const navigate = vi.fn();
  try {
    await act(async()=>root.render(<MobileNavigation page="attachments" onNavigate={navigate}/>));
    expect(host.querySelector('[aria-current="page"]')?.getAttribute('aria-label')).toBe('任务');
    await act(async()=>host.querySelector<HTMLButtonElement>('[aria-label="更多"]')!.click());
    expect(navigate).toHaveBeenCalledWith('more');
    await act(async()=>root.render(<MobileNavigation page="settings" onNavigate={navigate}/>));
    expect(host.querySelector('[aria-current="page"]')?.getAttribute('aria-label')).toBe('更多');
    expect(host.querySelectorAll('button')).toHaveLength(5);
  } finally { await act(async()=>root.unmount()); }
});
