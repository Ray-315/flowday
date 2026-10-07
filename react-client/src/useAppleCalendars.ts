import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { isTauri } from '@tauri-apps/api/core';
import { asLocal, calendarRequest, digest, fields, marker, remoteKey, type AppleCalendar, type AppleEvent } from './appleCalendar';
import type { CalendarEvent } from './workspace';

export type ConnectedEvent = { calendar: AppleCalendar; event: AppleEvent };
export const connectedPrefix = 'system-calendar:';
export const connectedId = (calendarId: string, event: AppleEvent) => connectedPrefix + JSON.stringify([calendarId, remoteKey(event)]);
export function projectAppleEvents(entries: ConnectedEvent[]): CalendarEvent[] {
  return entries.map(({ calendar, event }) => ({ ...asLocal(connectedId(calendar.id, event), fields(event)),
    locked: true, appleCalendarTitle: calendar.title }));
}
function readSelection(scope: string): string[] {
  try {
    const value: unknown = JSON.parse(localStorage.getItem(`flowday.apple-connected:${scope}`) ?? '[]');
    return Array.isArray(value) ? [...new Set(value.filter((id): id is string => typeof id === 'string'))] : [];
  } catch { return []; }
}

export function useAppleCalendars(scope: string, day: string) {
  const [state, setState] = useState<{ scope: string; supported: boolean; calendars: AppleCalendar[]; selected: string[]; entries: ConnectedEvent[]; busy: boolean; error: string; updated: number }>({ scope, supported: false, calendars: [], selected: readSelection(scope), entries: [], busy: false, error: '', updated: 0 });
  const generation = useRef(0);
  const current = useRef({ scope, day, selected: state.scope === scope ? state.selected : readSelection(scope) });
  current.current = { scope, day, selected: state.scope === scope ? state.selected : readSelection(scope) };
  const mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; generation.current++; }; }, []);
  const refresh = useCallback(async (requestAccess = false) => {
    const token = ++generation.current;
    const snapshot = current.current;
    const valid = () => mounted.current && token === generation.current && snapshot.scope === current.current.scope;
    if (!isTauri()) return;
    setState(old => ({ ...old, busy: true }));
    try {
      const capability = await calendarRequest<{ supported: boolean; authorized: boolean }>({ action: 'capability' });
      if (!valid()) return;
      if (!capability.supported || (!requestAccess && !capability.authorized)) {
        setState(old => ({ ...old, supported: capability.supported, calendars: [], entries: [], busy: false,
          error: old.selected.length && capability.supported ? '请允许访问系统日历后重新连接。' : '' }));
        return;
      }
      const { calendars } = await calendarRequest<{ calendars: AppleCalendar[] }>({ action: 'calendars' });
      if (!valid()) return;
      const center = new Date(`${snapshot.day}T12:00:00`).getTime();
      const today = Date.now();
      const ranges = [{ from: today - 31 * 86400000, to: today + 366 * 86400000 }];
      if (center - 31 * 86400000 < ranges[0].from || center + 62 * 86400000 > ranges[0].to) ranges.push({ from: center - 31 * 86400000, to: center + 62 * 86400000 });
      const entries: ConnectedEvent[] = [];
      for (const calendar of calendars.filter(c => snapshot.selected.includes(c.id))) {
        const seen = new Set<string>();
        for (const range of ranges) {
          const result = await calendarRequest<{ events: AppleEvent[] }>({ action: 'read', calendarId: calendar.id, ...range });
          if (!valid()) return;
          for (const event of result.events) if (!seen.has(remoteKey(event))) {
            seen.add(remoteKey(event)); entries.push({ calendar, event });
          }
        }
      }
      if (valid()) setState(old => ({ ...old, supported: true, calendars, entries, busy: false, updated: Date.now(),
        error: snapshot.selected.some(id => !calendars.some(c => c.id === id)) ? '部分已选日历已不可用，请重新选择。' : '' }));
    } catch (error) {
      if (valid()) setState(old => ({ ...old, busy: false, error: String(error instanceof Error ? error.message : error) }));
    }
  }, []);
  useEffect(() => {
    generation.current++;
    setState({ scope, supported: false, calendars: [], selected: readSelection(scope), entries: [], busy: false, error: '', updated: 0 });
    void refresh();
  }, [scope, refresh]);
  useEffect(() => {
    void refresh();
    const resume = () => { if (document.visibilityState !== 'hidden') void refresh(); };
    const timer = setInterval(resume, 30000);
    window.addEventListener('focus', resume);
    document.addEventListener('visibilitychange', resume);
    return () => { generation.current++; clearInterval(timer); window.removeEventListener('focus', resume); document.removeEventListener('visibilitychange', resume); };
  }, [scope, day, refresh]);
  function select(id: string, checked: boolean) {
    const selected = checked ? [...new Set([...current.current.selected, id])] : current.current.selected.filter(value => value !== id);
    try { localStorage.setItem(`flowday.apple-connected:${scope}`, JSON.stringify(selected)); }
    catch { setState(old => ({ ...old, error: '无法保存日历选择，请检查可用存储空间。' })); return; }
    current.current = { ...current.current, selected };
    setState(old => ({ ...old, selected, entries: old.entries.filter(entry => selected.includes(entry.calendar.id)) }));
    void refresh();
  }
  async function save(calendar: AppleCalendar, value: CalendarEvent, expected?: AppleEvent) {
    const sourceScope = scope;
    if (!calendar.writable) throw new Error('这个日历只读，请在原日历账户中修改。');
    if (current.current.scope !== sourceScope) throw new Error('账号已切换，请重新打开日程。');
    const hash = await digest(sourceScope);
    if (current.current.scope !== sourceScope) throw new Error('账号已切换，请重新打开日程。');
    const result = await calendarRequest<{ event: AppleEvent }>({ action: 'save', calendarId: calendar.id,
      event: { ...fields(value), url: expected?.url ?? marker(hash, value.id) }, expected });
    if (mounted.current && current.current.scope === sourceScope) {
      // Show the acknowledged write immediately, even if a subsequent refresh fails.
      generation.current++;
      setState(old => ({ ...old, entries: [...old.entries.filter(entry => !(entry.calendar.id === calendar.id &&
        (remoteKey(entry.event) === remoteKey(expected ?? result.event) || remoteKey(entry.event) === remoteKey(result.event)))),
        ...(old.selected.includes(calendar.id) ? [{ calendar, event: result.event }] : [])], busy: false }));
      void refresh();
    }
  }
  const visible = state.scope === scope ? state : { ...state, calendars: [], selected: [], entries: [], error: '', updated: 0 };
  const events = useMemo(() => state.scope === scope ? projectAppleEvents(state.entries) : [], [state.entries, state.scope, scope]);
  return { ...visible, refresh, select, save, events };
}
export type AppleCalendars = ReturnType<typeof useAppleCalendars>;
