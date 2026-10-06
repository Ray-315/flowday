import { Suspense, type ReactNode } from 'react';

// Keep the surrounding navigation visible while a feature chunk loads.
export function LazyPanel({ children }: { children: ReactNode }) {
  return <Suspense fallback={<p className="section-description" role="status">正在加载…</p>}>{children}</Suspense>;
}
