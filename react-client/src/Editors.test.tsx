import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { Editor } from './Editors';
import { emptyWorkspace, type Workspace } from './workspace';
let container: HTMLDivElement;
let root: Root;
beforeEach(() => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  HTMLDialogElement.prototype.showModal = vi.fn();
  HTMLDialogElement.prototype.close = vi.fn();
  container = document.createElement('div');
  document.body.append(container);
  root = createRoot(container);
});
afterEach(async () => {
  await act(() => root.unmount());
  container.remove();
});
function input(selector: string, value: string) {
  const element = container.querySelector<HTMLInputElement>(selector)!;
  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(element, value);
  element.dispatchEvent(new Event('input', { bubbles: true }));
}
it('creates a task with advanced defaults and preserves unrelated objects', async () => {
  const original = emptyWorkspace();
  original.projects = [{ id: 'p', title: '项目', color: 0xff4b70e8 }];
  let saved: Workspace | undefined;
  await act(() =>
    root.render(
      <Editor
        editing={{ kind: 'task' }}
        data={original}
        day="2026-10-05"
        defaultProject="p"
        onSave={(next) => {
          saved = next;
          return true;
        }}
        onClose={() => {}}
      />,
    ),
  );
  await act(() => input('input[maxlength="300"]', '真实任务'));
  await act(() =>
    container.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })),
  );
  expect(saved?.tasks[0]).toMatchObject({
    title: '真实任务',
    projectId: 'p',
    status: 'todo',
    estimateMinutes: 60,
    splittable: true,
    attachments: [],
  });
  expect(saved?.projects).toEqual(original.projects);
  expect(original.tasks).toHaveLength(0);
});
it('rejects cyclic task parents before invoking persistence', async () => {
  const data = emptyWorkspace();
  data.tasks = [
    { id: 'a', title: '父任务', status: 'todo', priority: 'normal', parentId: 'b' },
    { id: 'b', title: '子任务', status: 'todo', priority: 'normal' },
  ];
  const save = vi.fn(() => true);
  await act(() =>
    root.render(
      <Editor
        editing={{ kind: 'task', item: data.tasks[1] }}
        data={data}
        day="2026-10-05"
        defaultProject={null}
        onSave={save}
        onClose={() => {}}
      />,
    ),
  );
  const select = [...container.querySelectorAll('select')].find(
    (element) => element.previousElementSibling?.textContent === '父级任务',
  )!;
  await act(() => {
    select.value = 'a';
    select.dispatchEvent(new Event('change', { bubbles: true }));
  });
  await act(() =>
    container.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })),
  );
  expect(save).not.toHaveBeenCalled();
  expect(container.textContent).toContain('父级不能形成循环');
});
it('event completion from the editor completes its single linked task', async () => {
  const data = emptyWorkspace();
  data.preferences.timezone = 'UTC';
  data.tasks = [{ id: 't', title: '任务', status: 'todo', priority: 'normal' }];
  data.events = [
    {
      id: 'e',
      title: '任务时间块',
      start: '2026-10-05T09:00Z',
      end: '2026-10-05T10:00Z',
      taskId: 't',
      color: 0xff000000,
    },
  ];
  let saved: Workspace | undefined;
  await act(() =>
    root.render(
      <Editor
        editing={{ kind: 'event', item: data.events[0] }}
        data={data}
        day="2026-10-05"
        defaultProject={null}
        onSave={(next) => {
          saved = next;
          return true;
        }}
        onClose={() => {}}
      />,
    ),
  );
  const completed = [...container.querySelectorAll('label')]
    .find((element) => element.querySelector('span')?.textContent === '已完成')!
    .querySelector('input')!;
  await act(() => completed.click());
  await act(() =>
    container.querySelector('form')!.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })),
  );
  expect(saved?.events[0]).toMatchObject({ completed: true, actualMinutes: 60 });
  expect(saved?.tasks[0].status).toBe('done');
});
