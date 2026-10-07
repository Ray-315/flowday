import { useEffect, useRef, useState } from 'react';
import { Select } from './Select';
import { Modal } from './Editors';
import { activityCall, eligibleEvents, unavailable, readAutoActivitySettings, scheduleActivity, type AutoActivitySettings, type ActivityStatus } from './liveActivityBridge';
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
  const [automatic, setAutomatic] = useState<AutoActivitySettings>(() => readAutoActivitySettings(scope));
  const [notice, setNotice] = useState('');
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
      if (active?.eventId && !active.upcoming && active.scope === current.current.scope) {
        const event = eligibleEvents(current.current.workspace.events, Date.now()).find(e => e.id === active.eventId);
        if (!event) next = await activityCall('end');
        else if (event.title !== active.title || Date.parse(event.start) !== active.start || Date.parse(event.end) !== active.end) {
          next = await activityCall('start', { ...active, title: event.title, start: Date.parse(event.start), end: Date.parse(event.end) });
        }
      }
      if (next.autoScheduling && document.visibilityState === 'visible') {
        const settings = readAutoActivitySettings(current.current.scope);
        next = await scheduleActivity(current.current.workspace.events, current.current.scope, settings);
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
  useEffect(() => { setAutomatic(readAutoActivitySettings(scope)); setNotice(''); void refresh(); }, [scope]);
  useEffect(() => { void refresh(); }, [workspace.events]);
  if (!status.supported || !visible) return null;
  const events = eligibleEvents(workspace.events, now);
  const active = status.active?.scope === scope ? status.active : null;
  async function saveAutomatic(event?: React.FormEvent) {
    event?.preventDefault();
    if (inFlight.current) return;
    if (!Number.isInteger(automatic.minutes) || automatic.minutes < 1 || automatic.minutes > 120) { setError('请设置提前 1–120 分钟'); return; }
    inFlight.current = true; setBusy(true); setError(''); setNotice('');
    try {
      // Confirm storage is writable before changing the native reservation.
      const key = `flowday.live-activity.auto:${scope}`;
      const old = localStorage.getItem(key);
      localStorage.setItem(key, JSON.stringify(automatic));
      try { setStatus(await scheduleActivity(current.current.workspace.events, scope, automatic)); }
      catch (failure) { if (old === null) localStorage.removeItem(key); else localStorage.setItem(key, old); throw failure; }
      setNotice(automatic.enabled ? '设置已保存，下一个日程将提前提醒。' : '自动提醒已关闭。');
    } catch (failure) { setError(failure instanceof Error ? failure.message : String(failure)); }
    finally { inFlight.current = false; setBusy(false); }
  }
  async function run(command: 'start' | 'end') {
    if (inFlight.current) return;
    inFlight.current = true; setBusy(true); setError('');
    try {
      if (command === 'end' && active?.upcoming) {
        const value = { ...automatic, enabled: false };
        localStorage.setItem(`flowday.live-activity.auto:${scope}`, JSON.stringify(value)); setAutomatic(value);
      }
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
      <span>{active ? active.upcoming ? '即将开始' : '专注中' : '灵动岛'}</span>
    </button>
    {open && <Modal title="灵动岛与锁屏" onClose={() => { if (!busy) setOpen(false); }}><section className="live-activity-panel" aria-label="灵动岛设置">
    <form className="live-activity-automatic" onSubmit={event => void saveAutomatic(event)}>
      <h3>下个日程自动提醒</h3>
      {status.autoScheduling ? <>
        <label className="live-activity-toggle"><span>提前显示灵动岛与通知</span><input type="checkbox" checked={automatic.enabled} disabled={busy || !status.enabled} onChange={event => setAutomatic({ ...automatic, enabled: event.target.checked })}/></label>
        {automatic.enabled && <label className="live-activity-lead">提前多少分钟<input type="number" min={1} max={120} step={1} required disabled={busy} value={automatic.minutes} onChange={event => setAutomatic({ ...automatic, minutes: Number(event.target.value) })}/></label>}
        <button className="primary-button" disabled={busy || !status.enabled}>{busy ? '正在保存…' : '保存提醒设置'}</button>
        {status.scheduled?.scope === scope && <p className="section-description" role="status">已预约：{status.scheduled.title}<br/>{new Date(Math.max(status.scheduled.start, now)).toLocaleString()} 开始提醒，倒计时至日程开始。</p>}
        <p className="section-description">自动预约下一个未完成、非全天日程。关闭 App 后由系统触发；打开 App 会刷新下一次预约。通知显示受系统通知与专注模式影响。</p>
      </> : <p className="section-description">自动预约需要 iOS 26 或更新版本，当前系统可使用手动专注。</p>}
      {notice && <p role="status" className="section-description">{notice}</p>}
    </form>
    <h3 className="live-activity-manual-title">{active?.upcoming ? '日程倒计时' : '手动专注'}</h3>
    {!status.enabled ? <p>请在 iPhone 设置中允许 FlowDay「实时活动」，然后返回这里。</p> : active ? <>
      <p role="status"><strong>{active.title}</strong> · 正在实时活动中显示</p>
      <p className="section-description">结束于 {new Date(active.end).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}，可离开 App 查看倒计时。</p>
      <button disabled={busy} onClick={() => void run('end')}>{busy ? '正在结束…' : active.upcoming ? '结束并关闭自动提醒' : '结束实时活动'}</button>
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
