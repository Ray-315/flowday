import { useEffect, useRef, useState } from 'react';
import { isTauri } from '@tauri-apps/api/core';
import { Modal } from './Editors';
import { Select } from './Select';
import { applyCalendarPlan, calendarRequest, digest, planCalendarSync, directionalPlan,
  type AppleCalendar, type AppleEvent, type CalendarConflict, type CalendarLinks, type Resolution } from './appleCalendar';
import type { Workspace } from './workspace';

export function AppleCalendarSync({ data, onSave, scope }: { data: Workspace; onSave: (next: Workspace) => boolean; scope: string }) {
  const [supported, setSupported] = useState(false);
  const [open, setOpen] = useState(false);
  const [direction, setDirection] = useState<'import' | 'export'>('import');
  const [calendars, setCalendars] = useState<AppleCalendar[]>([]);
  const [calendarId, setCalendarId] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');
  const [conflicts, setConflicts] = useState<CalendarConflict[]>([]);
  const [resolutions, setResolutions] = useState<Record<string, Resolution>>({});
  const now = new Date();
  const [from, setFrom] = useState(new Date(now.getTime() - 30 * 86400000).toISOString().slice(0, 10));
  const [to, setTo] = useState(new Date(now.getTime() + 365 * 86400000).toISOString().slice(0, 10));
  const latest = useRef({ data, scope, onSave }); latest.current = { data, scope, onSave };
  useEffect(() => { if (isTauri()) void calendarRequest<{ supported: boolean }>({ action: 'capability' }).then(result => setSupported(result.supported)).catch(() => {}); }, []);
  useEffect(() => { setCalendarId(''); setConflicts([]); setResolutions({}); setMessage(''); }, [scope]);
  const key = (id: string) => `flowday.apple-calendar.v1:${scope}:${id}`;
  async function connect() {
    setBusy(true); setError('');
    try {
      const capturedScope = scope;
      const result = await calendarRequest<{ calendars: AppleCalendar[] }>({ action: 'calendars' });
      if (latest.current.scope !== capturedScope) return;
      setCalendars(result.calendars);
      const remembered = localStorage.getItem(key('selected'));
      setCalendarId(result.calendars.find(c => c.id === remembered && (direction === 'import' || c.writable))?.id ?? result.calendars.find(c => direction === 'import' || c.writable)?.id ?? '');
      if (!result.calendars.some(c => direction === 'import' || c.writable)) setError('没有可写日历，请先在苹果日历中添加一个日历');
    } catch (failure) { setError(String(failure instanceof Error ? failure.message : failure)); }
    finally { setBusy(false); }
  }
  async function sync() {
    if (busy) return;
    setBusy(true); setError(''); setMessage('');
    const capturedScope = scope;
    const ensureScope = () => { if (latest.current.scope !== capturedScope) throw new Error('账号已切换，请重新同步'); };
    try {
      const start = new Date(`${from}T00:00:00`).getTime(), end = new Date(`${to}T00:00:00`).getTime();
      if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start || end - start > 400 * 86400000) throw new Error('请选择不超过 400 天的有效日期范围，结束日期不包含当天');
      localStorage.setItem(key('selected'), calendarId);
      const source = localStorage.getItem(key(calendarId));
      const links = source ? JSON.parse(source) as CalendarLinks : {};
      localStorage.setItem(key(calendarId), JSON.stringify(links));
      const hash = await digest(scope);
      const remote = await calendarRequest<{ events: AppleEvent[] }>({ action: 'read', calendarId, from: start, to: end });
      ensureScope();
      const plan = directionalPlan(await planCalendarSync(latest.current.data.events, remote.events, links, hash, start, end, resolutions), direction);
      const result = await applyCalendarPlan(plan, { calendarId, scopeHash: hash, links,
        ensureScope, read: () => latest.current.data, save: value => {
          const saved = latest.current.onSave(value);
          if (saved) latest.current = { ...latest.current, data: value };
          return saved;
        }, persist: value => localStorage.setItem(key(calendarId), JSON.stringify(value)) });
      setConflicts(plan.conflicts); setResolutions({});
      setMessage(`${direction === 'import' ? '已导入 / 更新' : '已导出 / 更新'} ${direction === 'import' ? result.imported : result.exported} 条日程${plan.conflicts.length ? `，${plan.conflicts.length} 条待确认` : ''}。`);
    } catch (failure) { setError(String(failure instanceof Error ? failure.message : failure)); }
    finally { setBusy(false); }
  }
  if (!supported) return null;
  const importing = direction === 'import';
  const available = calendars.filter(c => importing || c.writable);
  return <>
    <button className="context-action" onClick={() => { setOpen(true); if (!calendars.length && localStorage.getItem(key('selected'))) void connect(); }}>苹果日历</button>
    {open && <Modal className="calendar-transfer-dialog" title="苹果日历" onClose={() => { if (!busy) setOpen(false); }}>
      <div className="calendar-transfer">
        <div className="calendar-transfer-tabs" role="group" aria-label="传输方向">
          {(['import', 'export'] as const).map(value => <button type="button" key={value} disabled={busy} aria-pressed={direction === value} onClick={() => {
            setDirection(value); setConflicts([]); setResolutions({}); setMessage(''); setError('');
            if (value === 'export' && !calendars.find(c => c.id === calendarId)?.writable) setCalendarId(calendars.find(c => c.writable)?.id ?? '');
          }}>{value === 'import' ? '导入' : '导出'}</button>)}
        </div>
        <p className="calendar-transfer-caption">{importing ? '将所选日历的日程导入 FlowDay。' : '将 FlowDay 日程保存到所选苹果日历。'}</p>
        {!calendars.length ? <div className="calendar-transfer-connect">
          <p>首次使用需要允许访问系统日历。</p>
          <button className="primary-button" disabled={busy} onClick={() => void connect()}>{busy ? '正在连接…' : '连接苹果日历'}</button>
        </div> : <form onSubmit={event => { event.preventDefault(); void sync(); }}>
          <label>{importing ? '从哪个日历导入' : '导出到哪个日历'}<Select disabled={busy} value={calendarId} onChange={event => { setCalendarId(event.target.value); setConflicts([]); setResolutions({}); }}>
            {available.map(c => <option key={c.id} value={c.id}>{c.title} · {c.account}</option>)}
          </Select></label>
          <details className="calendar-transfer-options"><summary>日期范围与选项</summary>
            <div className="calendar-transfer-dates">
              <label>开始日期<input type="date" required disabled={busy} value={from} onChange={event => setFrom(event.target.value)}/></label>
              <label>结束日期（不含当天）<input type="date" required disabled={busy} value={to} onChange={event => setTo(event.target.value)}/></label>
            </div>
            <button className="calendar-transfer-refresh" type="button" disabled={busy} onClick={() => void connect()}>刷新日历列表</button>
            <p>默认近 30 天至未来一年。重复操作不会重复创建日程，不自动删除日程。{importing ? '苹果重复日程按每次日程导入；已开启的云同步会同步导入结果。' : 'FlowDay 的重复日程暂不导出。'}</p>
          </details>
          <div className="calendar-transfer-footer"><span>{importing ? '苹果日历 → FlowDay' : 'FlowDay → 苹果日历'}</span><button className="primary-button calendar-transfer-submit" disabled={busy || !calendarId || !available.some(c => c.id === calendarId)}>{busy ? (importing ? '正在导入…' : '正在导出…') : (importing ? '导入日程' : '导出日程')}</button></div>
        </form>}
        {message && <p className="calendar-transfer-result" role="status">{message}</p>}
        {conflicts.map(conflict => <section className="calendar-transfer-conflict" key={conflict.id}>
          <h3>{conflict.title}</h3>
          <p>两边都有修改，是否用{importing ? '苹果日历' : 'FlowDay'}的版本覆盖？</p>
          <p>FlowDay：{conflict.local.title} · {new Date(conflict.local.start).toLocaleString()}</p>
          <p>苹果日历：{conflict.remote.title} · {new Date(conflict.remote.start).toLocaleString()}</p>
          <button type="button" disabled={busy} aria-pressed={Boolean(resolutions[conflict.id])} onClick={() => {
            const next = { ...resolutions };
            if (next[conflict.id]) delete next[conflict.id]; else next[conflict.id] = { side: importing ? 'apple' : 'flowday', signature: conflict.signature };
            setResolutions(next);
          }}>{resolutions[conflict.id] ? '已选中 · 再次点击导入 / 导出确认' : '使用此版本'}</button>
        </section>)}
        {error && <p className="calendar-transfer-error" role="alert">{error}</p>}
      </div>
    </Modal>}
  </>;
}
