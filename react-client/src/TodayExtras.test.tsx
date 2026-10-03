import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { expect, it, vi } from 'vitest';
import { emptyWorkspace } from './workspace';
import {
  saveCapture,
  captureToTask,
  todayModuleOrder,
  todayHiddenModules,
  isDefaultTodayLayout,
  weekPressure,
  QuickCapture,
  TodayExtraModule,
} from './TodayExtras';
it('normalizes module configuration while preserving chosen order and defaults', () => {
  const data = emptyWorkspace();
  expect(isDefaultTodayLayout(data)).toBe(true);
  data.preferences.todayModuleOrder = ['todo', 'unknown', 'todo', 'timeline'];
  data.preferences.todayHiddenModules = ['capture', 'unknown'];
  expect(todayModuleOrder(data).slice(0, 3)).toEqual(['todo', 'timeline', 'capture']);
  expect([...todayHiddenModules(data)]).toEqual(['capture']);
  expect(isDefaultTodayLayout(data)).toBe(false);
});
it('retains quick input when persistence fails and does not start AI parsing', async () => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  const container = document.createElement('div');
  document.body.append(container);
  const root = createRoot(container);
  const parse = vi.fn();
  try {
    await act(() =>
      root.render(<QuickCapture data={emptyWorkspace()} onSave={() => false} onParse={parse} />),
    );
    const input = container.querySelector('input')!;
    await act(() => {
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(
        input,
        '保存不了的输入',
      );
      input.dispatchEvent(new Event('input', { bubbles: true }));
    });
    await act(() =>
      container
        .querySelector('form')!
        .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })),
    );
    expect(input.value).toBe('保存不了的输入');
    expect(parse).not.toHaveBeenCalled();
    expect(container.textContent).toContain('保存失败');
  } finally {
    await act(() => root.unmount());
    container.remove();
  }
});
it('delegates notice acknowledgement to the shared reminder action handler', async () => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  const data = emptyWorkspace();
  data.notices = [{ id: 'n', title: '提醒', read: false, acknowledged: false }];
  const acknowledge = vi.fn(() => true),
    save = vi.fn(() => true);
  const container = document.createElement('div');
  document.body.append(container);
  const root = createRoot(container);
  try {
    await act(() =>
      root.render(
        <TodayExtraModule
          module="notices"
          data={data}
          day="2026-10-05"
          onSave={save}
          onEdit={() => {}}
          onAcknowledge={acknowledge}
        />,
      ),
    );
    await act(async () =>
      [...container.querySelectorAll('button')].find((button) => button.textContent === '已知晓')!.click(),
    );
    expect(acknowledge).toHaveBeenCalledWith('n');
    expect(save).not.toHaveBeenCalled();
    expect(data.notices).toMatchObject([{ acknowledged: false }]);
  } finally {
    await act(() => root.unmount());
    container.remove();
  }
});
it('saves capture and converts it exactly once without losing the raw text', () => {
  const data = emptyWorkspace();
  const captured = saveCapture(data, '  明天写论文  ', new Date('2026-10-05T01:00Z'));
  expect(captured.captures).toEqual([
    { id: expect.any(String), text: '明天写论文', createdAt: '2026-10-05T01:00:00.000Z', processed: false },
  ]);
  expect(data.captures).toEqual([]);
  const id = (captured.captures as { id: string }[])[0].id;
  const processed = captureToTask(captured, id);
  expect(processed.tasks[0].title).toBe('明天写论文');
  expect(processed.captures).toMatchObject([{ text: '明天写论文', processed: true }]);
  expect(() => captureToTask(processed, id)).toThrow();
  expect(() => saveCapture(data, ' ')).toThrow();
});
it('clips weekly events and adds only unplanned task estimates in the selected timezone', () => {
  const data = emptyWorkspace();
  data.preferences.timezone = 'America/New_York';
  data.tasks = [
    {
      id: 'linked',
      title: '已有时间块',
      status: 'todo',
      priority: 'normal',
      estimateMinutes: 180,
      deadline: '2026-10-05T18:00Z',
    },
    {
      id: 'free',
      title: '未安排',
      status: 'todo',
      priority: 'normal',
      estimateMinutes: 90,
      plannedStart: '2026-10-05T19:00Z',
    },
  ];
  data.events = [
    {
      id: 'e',
      title: '已有时间块',
      taskId: 'linked',
      color: 0xff000000,
      start: '2026-10-05T03:30Z',
      end: '2026-10-05T05:00Z',
    },
  ];
  const result = weekPressure(data, '2026-10-05');
  expect(result[0]).toMatchObject({ day: '2026-10-05', scheduled: 60, estimated: 90 });
  expect(result).toHaveLength(7);
});
