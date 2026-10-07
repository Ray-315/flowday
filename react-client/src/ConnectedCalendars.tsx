import { useRef, useState } from 'react';
import { Modal } from './Editors';
import { AppleCalendarSync } from './AppleCalendarSync';
import { asLocal, fields } from './appleCalendar';
import { inputInZone, instantInZone, zoneFor } from './timezone';
import type { Workspace } from './workspace';
import type { AppleCalendars, ConnectedEvent } from './useAppleCalendars';
import './connected-calendars.css';

export function ConnectedCalendars({ connection, data, onSave, scope, legacy }: {
  connection: AppleCalendars; data: Workspace; onSave: (next: Workspace) => boolean; scope: string; legacy?: React.ReactNode;
}) {
  const [showLegacy, setShowLegacy] = useState(false);
  return <div className="connected-calendars">
    <p className="section-description">使用系统已添加的日历，包括 iCloud。选中后，日程会持续显示在 FlowDay 中，编辑会保存回原日历。</p>
    {!connection.supported ? <p role="status">请在 Mac 或 iPhone 客户端连接系统日历。</p> : <>
      <div className="connected-calendar-actions">
        <button className={connection.calendars.length ? 'secondary-button' : 'primary-button'} disabled={connection.busy} onClick={() => void connection.refresh(true)}>{connection.busy ? '正在读取…' : connection.calendars.length ? '刷新日历' : '连接系统日历'}</button>
        {connection.updated > 0 && <span role="status">更新于 {new Date(connection.updated).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>}
      </div>
      <div className="connected-calendar-list">{connection.calendars.map(calendar => <label className="connected-calendar-row" key={calendar.id}>
        <input type="checkbox" checked={connection.selected.includes(calendar.id)} onChange={event => connection.select(calendar.id, event.target.checked)}/>
        <span><strong>{calendar.title}</strong><small>{calendar.account}{calendar.writable ? '' : ' · 只读'}</small></span>
      </label>)}</div>
      {connection.calendars.length > 0 && <p className="section-description">取消勾选仅隐藏日程。打开 App、返回前台和使用期间会自动刷新；其他设备的更新速度取决于系统日历同步。</p>}
      {connection.error && <p className="form-error" role="alert">{connection.error}</p>}
      <details className="calendar-secondary"><summary>手动导入与导出</summary>
        <p className="section-description">用于复制日程到另一个日历或 FlowDay。仅查看和编辑系统日历时，无需导入。</p>
        <AppleCalendarSync data={data} onSave={onSave} scope={scope}/>
      </details>
    </>}
    {legacy && <details className="calendar-secondary" onToggle={event => setShowLegacy(event.currentTarget.open)}><summary>旧版 iCloud 服务器连接</summary>
      <p className="section-description">管理已有的服务器连接。使用系统日历时，可在这里断开旧连接，避免两条同步路径同时运行。</p>
      {showLegacy && legacy}
    </details>}
  </div>;
}

export function ConnectedEventEditor({ entry, connection, data, onClose }: { entry: ConnectedEvent; connection: AppleCalendars; data: Workspace; onClose: () => void }) {
  // Freeze the expected version until this editor closes, so background refresh cannot overwrite concurrent edits.
  const [original] = useState(entry);
  const zone = zoneFor(data);
  const [title, setTitle] = useState(original.event.title);
  const [start, setStart] = useState(inputInZone(new Date(original.event.start).toISOString(), zone));
  const [end, setEnd] = useState(inputInZone(new Date(original.event.end).toISOString(), zone));
  const [allDay, setAllDay] = useState(original.event.allDay);
  const [location, setLocation] = useState(original.event.location);
  const [notes, setNotes] = useState(original.event.notes);
  const [busy, setBusy] = useState(false), pending = useRef(false);
  const [error, setError] = useState('');
  const close = () => { if (!pending.current) onClose(); };
  const writable = original.calendar.writable;
  return <Modal className="record-editor-dialog" title={writable ? '编辑苹果日历日程' : '查看苹果日历日程'} onClose={close}>
    <form onSubmit={async event => {
      event.preventDefault();
      if (pending.current || !writable) return;
      pending.current = true; setBusy(true); setError('');
      try {
        const value = { ...fields(original.event), title: title.trim(), start: Date.parse(instantInZone(start, zone)), end: Date.parse(instantInZone(end, zone)), allDay, location, notes };
        if (!value.title || !Number.isFinite(value.start) || !Number.isFinite(value.end) || value.end <= value.start) throw new Error('请填写名称和有效的起止时间。');
        await connection.save(original.calendar, asLocal('existing', value), original.event);
        onClose();
      } catch (failure) { setError(String(failure instanceof Error ? failure.message : failure)); }
      finally { pending.current = false; setBusy(false); }
    }}>
      <div className="editor-fields" inert={busy}>
        <p className="section-description">{original.calendar.title} · {original.calendar.account}{original.event.recurring ? ' · 修改仅应用于这一次日程' : ''}{writable ? '' : ' · 只读'}</p>
        <label className="field">日程名称<input required readOnly={!writable} maxLength={300} value={title} onChange={event => setTitle(event.target.value)}/></label>
        <div className="field-pair">
          <label className="field">开始时间<input required readOnly={!writable} type="datetime-local" value={start} onChange={event => setStart(event.target.value)}/></label>
          <label className="field">结束时间<input required readOnly={!writable} type="datetime-local" value={end} onChange={event => setEnd(event.target.value)}/></label>
        </div>
        <label className="toggle-field"><span>全天</span><input disabled={!writable} type="checkbox" checked={allDay} onChange={event => setAllDay(event.target.checked)}/><span className="toggle"/></label>
        <label className="field">地点<input readOnly={!writable} value={location} onChange={event => setLocation(event.target.value)}/></label>
        <label className="field">备注<textarea readOnly={!writable} value={notes} onChange={event => setNotes(event.target.value)}/></label>
        {error && <p className="form-error" role="alert">{error} 请关闭后刷新日历，再重新打开。</p>}
      </div>
      <div className="dialog-footer"><button type="button" className="secondary-button" disabled={busy} onClick={close}>关闭</button>{writable && <button className="primary-button" disabled={busy}>{busy ? '正在保存…' : '保存到原日历'}</button>}</div>
    </form>
  </Modal>;
}
