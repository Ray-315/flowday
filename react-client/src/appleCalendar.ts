import { invoke, isTauri } from '@tauri-apps/api/core';
import type { CalendarEvent, Workspace } from './workspace';
export type CalendarFields = { title: string; start: number; end: number; allDay: boolean; location: string; notes: string };
export type AppleEvent = CalendarFields & { identifier: string; externalId: string; occurrence: number; recurring: boolean; url: string };
export type AppleCalendar = { id: string; title: string; account: string; writable: boolean };
export type CalendarLink = { remoteKey: string; local: CalendarFields; remote: CalendarFields };
export type CalendarLinks = Record<string, CalendarLink>;
export type Resolution = { side: 'apple' | 'flowday'; signature: string };
export type CalendarConflict = { id: string; title: string; local: CalendarFields; remote: CalendarFields; signature: string };
export type CalendarChange = { kind: 'import' | 'export' | 'baseline'; id: string; local?: CalendarEvent; remote?: AppleEvent; fields: CalendarFields };
export type CalendarPlan = { changes: CalendarChange[]; conflicts: CalendarConflict[]; skipped: number };
export async function calendarRequest<T>(data: Record<string, unknown>): Promise<T> {
  if (!isTauri()) throw new Error('请在 Mac 或 iPhone 客户端使用苹果日历同步');
  return invoke('plugin:apple-calendar|request', { data });
}
export function fields(event: CalendarEvent | AppleEvent): CalendarFields {
  return { title: event.title, start: typeof event.start === 'number' ? event.start : Date.parse(event.start),
    end: typeof event.end === 'number' ? event.end : Date.parse(event.end), allDay: event.allDay === true,
    location: typeof event.location === 'string' ? event.location : '', notes: typeof event.notes === 'string' ? event.notes : '' };
}
export const fingerprint = (value: CalendarFields) => JSON.stringify(fields(value as AppleEvent));
export const remoteKey = (value: AppleEvent) => `${value.externalId || value.identifier}|${value.recurring ? value.occurrence : ''}`;
export async function digest(value: string) {
  const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(hash)].map(byte => byte.toString(16).padStart(2, '0')).join('');
}
export const marker = (scopeHash: string, id: string) => `flowday://calendar/${scopeHash}/${encodeURIComponent(id)}`;
export function asLocal(id: string, value: CalendarFields, previous?: CalendarEvent): CalendarEvent {
  return { ...previous, id, title: value.title, start: new Date(value.start).toISOString(), end: new Date(value.end).toISOString(),
    allDay: value.allDay, location: value.location, notes: value.notes, color: previous?.color ?? 0xff4b70e8 };
}
export async function planCalendarSync(localEvents: CalendarEvent[], incoming: AppleEvent[], links: CalendarLinks,
  scopeHash: string, from: number, to: number, resolutions: Record<string, Resolution> = {}): Promise<CalendarPlan> {
  const plan: CalendarPlan = { changes: [], conflicts: [], skipped: 0 };
  const localById = new Map(localEvents.map(e => [e.id, e]));
  const linkedKeys = new Map(Object.entries(links).map(([id, link]) => [link.remoteKey, id]));
  const seen = new Set<string>();
  for (const remote of incoming) {
    const prefix = `flowday://calendar/${scopeHash}/`;
    if (remote.url.startsWith('flowday://calendar/') && !remote.url.startsWith(prefix)) { plan.skipped++; continue; }
    let tagged: string | undefined;
    try { if (remote.url.startsWith(prefix)) tagged = decodeURIComponent(remote.url.slice(prefix.length)); } catch { /* use stable external identifier */ }
    const id = linkedKeys.get(remoteKey(remote)) ?? tagged ?? `apple-${await digest(remoteKey(remote))}`;
    if (seen.has(id)) { plan.skipped++; continue; }
    seen.add(id);
    const local = localById.get(id), right = fields(remote), link = links[id];
    if (local?.deletedAt || local?.repeatRule) { plan.skipped++; continue; }
    if (!local) { plan.changes.push({ kind: 'import', id, remote, fields: right }); continue; }
    const left = fields(local), same = fingerprint(left) === fingerprint(right);
    const leftChanged = !link || fingerprint(left) !== fingerprint(link.local);
    const rightChanged = !link || fingerprint(right) !== fingerprint(link.remote);
    if (same || (!leftChanged && !rightChanged)) { plan.changes.push({ kind: 'baseline', id, local, remote, fields: left }); continue; }
    if (leftChanged && rightChanged) {
      const signature = fingerprint(left) + fingerprint(right), resolution = resolutions[id];
      if (!resolution || resolution.signature !== signature) {
        plan.conflicts.push({ id, title: left.title, local: left, remote: right, signature }); continue;
      }
      plan.changes.push({ kind: resolution.side === 'apple' ? 'import' : 'export', id, local, remote,
        fields: resolution.side === 'apple' ? right : left });
    } else plan.changes.push({ kind: rightChanged ? 'import' : 'export', id, local, remote, fields: rightChanged ? right : left });
  }
  for (const local of localEvents) {
    if (seen.has(local.id) || local.deletedAt || Date.parse(local.start) >= to || Date.parse(local.end) <= from) continue;
    // Missing Apple entries may be deleted or moved outside the range. Never recreate or delete them implicitly.
    if (links[local.id] || local.id.startsWith('apple-') || local.repeatRule) { plan.skipped++; continue; }
    plan.changes.push({ kind: 'export', id: local.id, local, fields: fields(local) });
  }
  return plan;
}
export function directionalPlan(plan: CalendarPlan, direction: 'import' | 'export'): CalendarPlan {
  return { ...plan, changes: plan.changes.filter(change => change.kind === direction || change.kind === 'baseline') };
}
export async function applyCalendarPlan(plan: CalendarPlan, options: {
  calendarId: string; scopeHash: string; links: CalendarLinks;
  read: () => Workspace; save: (value: Workspace) => boolean; persist: (links: CalendarLinks) => void;
  ensureScope: () => void;
  write?: (data: Record<string, unknown>) => Promise<{ event: AppleEvent }>;
}) {
  let imported = 0, exported = 0;
  const links = { ...options.links };
  for (const change of plan.changes) {
    options.ensureScope();
    const current = options.read(), local = current.events.find(e => e.id === change.id);
    if (Boolean(local) !== Boolean(change.local) || (local && change.local &&
        (local.deletedAt !== change.local.deletedAt || fingerprint(fields(local)) !== fingerprint(fields(change.local))))) {
      throw new Error('本地日程在同步期间发生变化，请重新同步；已保存的结果不会重复创建');
    }
    let remote = change.remote;
    if (change.kind === 'import') {
      const next = asLocal(change.id, change.fields, local);
      const events = local ? current.events.map(e => e.id === next.id ? next : e) : [...current.events, next];
      if (!options.save({ ...current, events })) throw new Error('无法保存导入结果，请先处理本地存储错误');
      imported++;
    }
    if (change.kind === 'export') {
      remote = (await (options.write ?? calendarRequest<{ event: AppleEvent }>)({ action: 'save', calendarId: options.calendarId,
        event: { ...change.fields, url: marker(options.scopeHash, change.id) }, expected: remote })).event;
      options.ensureScope();
      exported++;
    }
    if (remote) {
      links[change.id] = { remoteKey: remoteKey(remote), local: change.fields, remote: fields(remote) };
      options.persist(links);
    }
  }
  return { imported, exported, links };
}
