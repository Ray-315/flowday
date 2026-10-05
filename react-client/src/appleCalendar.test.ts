import { expect, it, vi } from 'vitest';
import { webcrypto } from 'node:crypto';
import { applyCalendarPlan, directionalPlan, asLocal, fields, fingerprint, marker, planCalendarSync, remoteKey, type AppleEvent, type CalendarLinks } from './appleCalendar';
import { emptyWorkspace } from './workspace';
Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true });
const remote: AppleEvent = { identifier: 'native', externalId: 'icloud-uid', occurrence: 1000000, recurring: false,
  title: 'Meeting', start: 1000000, end: 2000000, allDay: false, location: '', notes: '', url: '' };
const local = asLocal('local', fields(remote));
const baseline: CalendarLinks = { local: { remoteKey: remoteKey(remote), local: fields(local), remote: fields(remote) } };
const plan = (locals = [local], remotes = [remote], links = baseline) => planCalendarSync(locals, remotes, links, 'scope', 0, 9000000);
it('imports with stable IDs and repeated sync does not duplicate or export the same imported item', async () => {
  const first = await plan([], [remote], {});
  expect(first.changes[0].kind).toBe('import');
  const imported = asLocal(first.changes[0].id, first.changes[0].fields);
  const again = await plan([imported], [remote], {});
  expect(again.changes).toHaveLength(1);
  expect(again.changes[0].kind).toBe('baseline');
  expect(again.changes[0].id).toBe(imported.id);
});
it('uses markers to recover export mappings after an interrupted sync or on another device', async () => {
  const result = await plan([local], [{ ...remote, url: marker('scope', 'local') }], {});
  expect(result.changes).toHaveLength(1);
  expect(result.changes[0].kind).toBe('baseline');
});
it('exports a local edit and imports an Apple edit, preserving unrelated local metadata', async () => {
  expect((await plan([{ ...local, title: 'Local edit' }])).changes[0].kind).toBe('export');
  const result = await plan([local], [{ ...remote, title: 'Apple edit' }]);
  expect(result.changes[0].kind).toBe('import');
  expect(asLocal('local', result.changes[0].fields, { ...local, locked: true, taskId: 'task' })).toMatchObject({ locked: true, taskId: 'task', title: 'Apple edit' });
});
it('keeps concurrent edits as conflicts and rejects stale user resolutions', async () => {
  const left = { ...local, title: 'Local edit' }, right = { ...remote, title: 'Apple edit' };
  const result = await plan([left], [right]);
  expect(result.changes).toHaveLength(0);
  expect(result.conflicts).toHaveLength(1);
  const resolution = { local: { side: 'apple' as const, signature: result.conflicts[0].signature } };
  expect((await planCalendarSync([left], [right], baseline, 'scope', 0, 9000000, resolution)).changes[0].kind).toBe('import');
  expect((await planCalendarSync([left], [{ ...right, notes: 'New edit' }], baseline, 'scope', 0, 9000000, resolution)).conflicts).toHaveLength(1);
});
it('does not recreate missing Apple events, reimport deleted local events, or export foreign recurring copies', async () => {
  expect((await plan([local], [])).changes).toHaveLength(0);
  expect((await plan([{ ...local, deletedAt: new Date().toISOString() }])).changes).toHaveLength(0);
  expect((await plan([{ ...local, id: 'apple-other' }], [], {})).changes).toHaveLength(0);
  expect((await plan([{ ...local, repeatRule: { frequency: 'daily', interval: 1 } }], [], {})).changes).toHaveLength(0);
});
it('keeps recurring instances distinct and ignores another FlowDay account marker', async () => {
  const result = await plan([], [{ ...remote, recurring: true }, { ...remote, recurring: true, occurrence: 3000000, start: 3000000, end: 4000000 }], {});
  expect(new Set(result.changes.map(e => e.id)).size).toBe(2);
  expect((await plan([], [{ ...remote, url: marker('other-scope', 'id') }], {})).changes).toHaveLength(0);
});
it('refuses local changes during sync and preserves successful write mappings for retry', async () => {
  let data = { ...emptyWorkspace(), events: [local] };
  const persist = vi.fn(), write = vi.fn(async () => ({ event: remote }));
  const result = await plan([local], [], {});
  data.events = [{ ...local, title: 'Changed while waiting' }];
  await expect(applyCalendarPlan(result, { calendarId: 'c', scopeHash: 'scope', links: {}, read: () => data, save: () => true, persist, write, ensureScope() {} })).rejects.toThrow('本地日程');
  expect(write).not.toHaveBeenCalled();
  data.events = [local];
  const applied = await applyCalendarPlan(result, { calendarId: 'c', scopeHash: 'scope', links: {}, read: () => data, save: () => true, persist, write, ensureScope() {} });
  expect(applied.exported).toBe(1);
  expect(persist).toHaveBeenCalledWith(expect.objectContaining({ local: expect.objectContaining({ remoteKey: remoteKey(remote) }) }));
  expect(fingerprint(applied.links.local.local)).toBe(fingerprint(fields(local)));
});

it('keeps import and export strictly one-way', async () => {
  const both = await planCalendarSync([local, { ...local, id: 'new-local' }], [remote, { ...remote, identifier: 'other', externalId: 'other' }], baseline, 'scope', 0, 9000000);
  expect(directionalPlan(both, 'import').changes.map(c => c.kind)).toEqual(['baseline', 'import']);
  expect(directionalPlan(both, 'export').changes.map(c => c.kind)).toEqual(['baseline', 'export']);
});
