import { act, lazy } from 'react';
import { createRoot } from 'react-dom/client';
import { expect, it } from 'vitest';
import { LazyPanel } from './LazyPanel';

it('keeps surrounding settings visible while a feature loads, then replaces only its placeholder', async () => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  let finish!: (module: { default: () => React.ReactNode }) => void;
  const Feature = lazy(() => new Promise<{ default: () => React.ReactNode }>(resolve => { finish = resolve; }));
  const host = document.createElement('div');
  const root = createRoot(host);
  const render = (open: boolean) => <main><nav>设置分类</nav><section><h2>同步与备份</h2>{open && <LazyPanel><Feature/></LazyPanel>}</section></main>;
  try {
    await act(async () => root.render(render(false)));
    const navigation = host.querySelector('nav');
    await act(async () => root.render(render(true)));
    expect(host.querySelector('nav')).toBe(navigation);
    expect(host.querySelector('main')?.style.display).not.toBe('none');
    expect(host.textContent).toContain('设置分类');
    expect(host.querySelector('[role="status"]')?.textContent).toBe('正在加载…');
    await act(async () => finish({ default: () => <button>创建备份</button> }));
    expect(host.querySelector('nav')).toBe(navigation);
    expect(host.querySelector('[role="status"]')).toBeNull();
    expect(host.textContent).toContain('创建备份');
  } finally {
    await act(async () => root.unmount());
  }
});
