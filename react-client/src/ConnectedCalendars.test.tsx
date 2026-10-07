import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { it, expect, vi } from 'vitest';
import { ConnectedEventEditor } from './ConnectedCalendars';
import type { AppleCalendars, ConnectedEvent } from './useAppleCalendars';
import { emptyWorkspace } from './workspace';
it('keeps the originally opened version for conflict checks and preserves the draft when writing fails', async () => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  HTMLDialogElement.prototype.showModal = vi.fn();
  HTMLDialogElement.prototype.close = vi.fn();
  const host = document.createElement('div'), root = createRoot(host), close = vi.fn();
  const save = vi.fn().mockRejectedValue(new Error('苹果日程刚刚发生变化'));
  const connection = { save } as unknown as AppleCalendars;
  const entry: ConnectedEvent = { calendar: { id: 'c', title: '工作', account: 'iCloud', writable: true }, event: { identifier: 'e', externalId: 'e', occurrence: 1, recurring: true, title: '旧会议', start: Date.parse('2026-10-07T09:00Z'), end: Date.parse('2026-10-07T10:00Z'), allDay: false, location: '', notes: '', url: '' } };
  const render = (value: ConnectedEvent) => <ConnectedEventEditor entry={value} connection={connection} data={emptyWorkspace()} onClose={close}/>;
  try {
    await act(() => root.render(render(entry)));
    await act(() => root.render(render({ ...entry, event: { ...entry.event, title: '另一台设备的更新' } })));
    const title = host.querySelector<HTMLInputElement>('input[maxlength="300"]')!;
    await act(() => { Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(title, '我的修改'); title.dispatchEvent(new Event('input', { bubbles: true })); });
    await act(async () => { host.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })); });
    expect(save).toHaveBeenCalledWith(entry.calendar, expect.objectContaining({ title: '我的修改' }), entry.event);
    expect(close).not.toHaveBeenCalled();
    expect(title.value).toBe('我的修改');
    expect(host.textContent).toContain('苹果日程刚刚发生变化');
    expect(host.textContent).toContain('修改仅应用于这一次日程');
  } finally { await act(() => root.unmount()); }
});
