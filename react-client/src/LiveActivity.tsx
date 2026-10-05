import { useEffect, useRef, useState } from 'react';
import { Select } from './Select';
import { Modal } from './Editors';
import { activityCall, eligibleEvents, unavailable, type ActivityStatus } from './liveActivityBridge';
import type { Workspace } from './workspace';
import './live-activity.css';

export function LiveActivity({ workspace, scope, visible }: { workspace: Workspace; scope: string; visible: boolean }) {
  const [open, setOpen] = useState(false);
  const [status, setStatus] = useState<ActivityStatus>(unavailable);
  const [title, setTitle] = useState('专注时间');
  const [minutes, setMinutes] = useState(25);
  const [eventId, setEventId] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [now, setNow] = useState(Date.now());
  const inFlight = useRef(false);
  const supported = useRef(false);
  const current = useRef({ workspace, scope });
  current.current = { workspace, scope };
  async function refresh() {
    if (inFlight.current) return;
    inFlight.current = true;
    try {
      let next = await activityCall('status');
      supported.current = next.supported;
      const active = next.active;
      if (active?.eventId && active.scope === current.current.scope) {
        const event = eligibleEvents(current.current.workspace.events, Date.now()).find(e => e.id === active.eventId);
        if (!event) next = await activityCall('end');
        else if (event.title !== active.title || Date.parse(event.start) !== active.start || Date.parse(event.end) !== active.end) {
          next = await activityCall('start', { ...active, title: event.title, start: Date.parse(event.start), end: Date.parse(event.end) });
        }
      }
      setStatus(next);
    } catch (failure) { setError(failure instanceof Error ? failure.message : String(failure)); }
    finally { inFlight.current = false; }
  }
  useEffect(() => {
    void refresh();
    const timer = setInterval(() => { setNow(Date.now()); if (supported.current && document.visibilityState === 'visible') void refresh(); }, 15000);
    const resume = () => { if (document.visibilityState === 'visible') void refresh(); };
    document.addEventListener('visibilitychange', resume);
    return () => { clearInterval(timer); document.removeEventListener('visibilitychange', resume); };
  }, []);
  useEffect(() => { void refresh(); }, [workspace.events, scope]);
  if (!status.supported || !visible) return null;
  const events = eligibleEvents(workspace.events, now);
  const active = status.active?.scope === scope ? status.active : null;
  async function run(command: 'start' | 'end') {
    if (inFlight.current) return;
    inFlight.current = true; setBusy(true); setError('');
    try {
      const event = eventId ? eligibleEvents(workspace.events, Date.now()).find(e => e.id === eventId) : undefined;
      if (command === 'start' && eventId && !event) throw new Error('这个日程已结束，请重新选择');
      const start = event ? Date.parse(event.start) : Date.now();
      setStatus(await activityCall(command, command === 'start' ? {
        title: event?.title ?? title.trim(), start,
        end: event ? Date.parse(event.end) : start + minutes * 60000,
        scope, eventId: event?.id ?? null,
      } : undefined));
    } catch (failure) { setError(failure instanceof Error ? failure.message : String(failure)); }
    finally { inFlight.current = false; setBusy(false); }
  }
  return <>
    <button className="context-action live-activity-trigger" aria-haspopup="dialog" onClick={() => setOpen(true)}>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true"><rect x="3" y="7" width="18" height="10" rx="5" stroke="currentColor" strokeWidth="1.6"/><circle cx="17" cy="12" r="1.5" fill="currentColor"/></svg>
      <span>{active ? '专注中' : '灵动岛'}</span>
    </button>
    {open && <Modal title="灵动岛与锁屏" onClose={() => { if (!busy) setOpen(false); }}><section className="live-activity-panel" aria-label="灵动岛设置">
    {!status.enabled ? <p>请在 iPhone 设置中允许 FlowDay「实时活动」，然后返回这里。</p> : active ? <>
      <p role="status"><strong>{active.title}</strong> · 正在实时活动中显示</p>
      <p className="section-description">结束于 {new Date(active.end).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}，可离开 App 查看倒计时。</p>
      <button disabled={busy} onClick={() => void run('end')}>{busy ? '正在结束…' : '结束实时活动'}</button>
    </> : <form onSubmit={event => { event.preventDefault(); void run('start'); }}>
      <label>显示内容<Select value={eventId} onChange={event => setEventId(event.target.value)}><option value="">手动专注</option>{events.map(event => <option key={event.id} value={event.id}>{event.title}</option>)}</Select></label>
      {!eventId && <div className="live-activity-fields"><label>专注事项<input required maxLength={120} value={title} onChange={event => setTitle(event.target.value)} /></label><label>分钟<input type="number" required min={1} max={480} step={1} value={minutes} onChange={event => setMinutes(Number(event.target.value))}/></label></div>}
      <button className="primary-button" disabled={busy || (!eventId && !title.trim())}>{busy ? '正在开启…' : '开启实时活动'}</button>
      <p className="section-description">有灵动岛的 iPhone 显示在岛上，其他机型显示在锁屏。到时后返回 App 结束，或在锁屏移除。</p>
    </form>}
    {error && <p role="alert">{error}</p>}
  </section></Modal>}
  </>;
}
