import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import { ChevronLeft, ChevronRight, MapPin, Plus } from './icons';
import type { Editing } from './App';
import { setEventCompleted, editRecurring } from './domain';
import './calendar-advanced.css';
import { zoneFor, inputInZone, instantInZone, dayInZone, dayBounds } from './timezone';
import { activeEvents } from './domain';
import { ToolsDialog } from './Tools';
import { hexColor, localDay, shiftDay, type CalendarEvent, type Workspace } from './workspace';

type Props = {
  data: Workspace;
  day: string;
  onDay: (day: string) => void;
  onEdit: (editing: Editing) => void;
  query: string;
  clock: Date;
  full: boolean;
  onSave?: (data: Workspace) => boolean;
  overlapStyle?: OverlapStyle;
};
export type OverlapStyle = '并排' | '层叠' | '聚合';
const viewLabels: Record<string, string> = {
  day: '日',
  week: '周',
  month: '月',
  timeline: '时间轴',
  list: '列表',
};
const viewFor = (value: unknown) =>
  Object.keys(viewLabels).find((key) => viewLabels[key] === value) ?? 'month';
export function calendarOverlapGroups(events: CalendarEvent[]): CalendarEvent[][] {
  const sorted = [...events].sort(
    (a, b) => Date.parse(a.start) - Date.parse(b.start) || a.id.localeCompare(b.id),
  );
  const groups: CalendarEvent[][] = [];
  let end = -Infinity;
  for (const event of sorted) {
    if (Date.parse(event.start) >= end) {
      groups.push([]);
      end = -Infinity;
    }
    groups[groups.length - 1].push(event);
    end = Math.max(end, Date.parse(event.end));
  }
  return groups;
}
export function Calendar({
  data,
  day,
  onDay,
  onEdit,
  query,
  clock,
  full,
  onSave,
  overlapStyle: overlapOverride,
}: Props) {
  const zone = zoneFor(data);
  const localDay = (date: Date = new Date()) => dayInZone(date, zone);
  const time = (iso: string) =>
    new Date(iso).toLocaleTimeString('zh-CN', {
      timeZone: zone,
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  const eventsForDay = (_data: Workspace, date: string) => {
    const bounds = dayBounds(date, zone);
    return activeEvents(_data)
      .filter((event) => Date.parse(event.start) < bounds.end && Date.parse(event.end) > bounds.start)
      .sort((a, b) => Date.parse(a.start) - Date.parse(b.start));
  };
  const [view, setView] = useState(() => (full ? viewFor(data.preferences.calendarView) : 'day'));
  const overlap =
    overlapOverride ??
    (full && ['并排', '层叠', '聚合'].includes(String(data.preferences.overlapStyle))
      ? (data.preferences.overlapStyle as OverlapStyle)
      : '并排');
  const weekStartsMonday = data.preferences.weekStartsMonday !== false;
  const weekOffset = (date: string) => {
    const weekday = new Date(`${date}T12:00:00Z`).getUTCDay();
    return weekStartsMonday ? (weekday + 6) % 7 : weekday;
  };
  const weekdays = weekStartsMonday
    ? ['一', '二', '三', '四', '五', '六', '日']
    : ['日', '一', '二', '三', '四', '五', '六'];
  const [aggregate, setAggregate] = useState<CalendarEvent[] | null>(null);
  const [error, setError] = useState('');
  const resizing = useRef<{ id: string; y: number; end: number } | null>(null);
  function persist(next: Workspace) {
    if (!onSave?.(next)) setError('保存失败');
    else setError('');
  }
  function changeView(value: string) {
    if (
      full &&
      onSave &&
      !onSave({ ...data, preferences: { ...data.preferences, calendarView: viewLabels[value] } })
    ) {
      setError('保存失败');
      return;
    }
    setView(value);
    setError('');
  }
  useEffect(() => {
    setView(full ? viewFor(data.preferences.calendarView) : 'day');
  }, [data.preferences.calendarView, full]);
  function drop(event: React.DragEvent, date: string, hour = 9, minute = 0) {
    event.preventDefault();
    if (!onSave) return;
    const eventId = event.dataTransfer.getData('application/flowday-event');
    const taskId = event.dataTransfer.getData('application/flowday-task');
    try {
      const start = new Date(
        instantInZone(`${date}T${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}:00`, zone),
      );
      if (eventId) {
        const item = data.events.find((item) => item.id === eventId);
        if (!item || item.locked || item.completed) return;
        persist(
          editRecurring(data, 'events', {
            ...item,
            start: start.toISOString(),
            end: new Date(start.getTime() + Date.parse(item.end) - Date.parse(item.start)).toISOString(),
          }),
        );
      } else if (taskId) {
        const task = data.tasks.find((item) => item.id === taskId);
        if (!task || task.deletedAt || task.status === 'done') return;
        const project = data.projects.find((item) => item.id === task.projectId);
        const minutes = Math.max(15, Number(task.estimateMinutes ?? 60));
        persist({
          ...data,
          events: [
            ...data.events,
            {
              id: crypto.randomUUID(),
              title: task.title,
              taskId: task.id,
              projectId: task.projectId,
              start: start.toISOString(),
              end: new Date(start.getTime() + minutes * 60000).toISOString(),
              color: project?.color ?? 0xff4b70e8,
              completed: false,
              locked: false,
              allDay: false,
              actualMinutes: 0,
              notes: '',
              tags: [],
              attachments: [],
            },
          ],
        });
      }
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : '排程失败');
    }
  }
  const firstMonth = `${day.slice(0, 7)}-01`;
  const monthOffset = weekOffset(firstMonth);
  const rangeStart =
    view === 'month'
      ? shiftDay(firstMonth, -monthOffset)
      : view === 'week'
        ? shiftDay(day, -weekOffset(day))
        : day;
  const rangeDays =
    view === 'month' ? 42 : view === 'week' ? 7 : view === 'list' || view === 'timeline' ? 31 : 1;
  function navigate(offset: number) {
    if (full && view === 'month') {
      const date = new Date(`${day}T12:00:00`);
      const original = date.getDate();
      date.setDate(1);
      date.setMonth(date.getMonth() + offset);
      date.setDate(Math.min(original, new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate()));
      onDay(
        `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`,
      );
    } else onDay(shiftDay(day, offset * (full && view === 'week' ? 7 : 1)));
  }
  const scroller = useRef<HTMLDivElement>(null);
  const events = eventsForDay(data, day).filter((item) =>
    item.title.toLocaleLowerCase().includes(query.toLocaleLowerCase()),
  );
  const bounds = dayBounds(day, zone);
  const dayStart = bounds.start;
  const positioned = events
    .filter((event) => !event.allDay)
    .map((event) => ({
      event,
      start: Math.max(bounds.start, Date.parse(event.start)),
      end: Math.min(bounds.end, Date.parse(event.end)),
      column: 0,
      columns: 1,
    }));
  let group: typeof positioned = [],
    ends: number[] = [],
    groupEnd = 0;
  function finish() {
    for (const block of group) block.columns = ends.length;
    group = [];
    ends = [];
  }
  for (const block of positioned) {
    if (block.start >= groupEnd) finish();
    let column = ends.findIndex((end) => end <= block.start);
    if (column < 0) column = ends.length;
    block.column = column;
    ends[column] = block.end;
    group.push(block);
    groupEnd = Math.max(groupEnd, block.end);
  }
  finish();
  const wallMinute = (instant: number) => {
    if (instant <= bounds.start) return 0;
    if (instant >= bounds.end) return 1440;
    const wall = inputInZone(new Date(instant).toISOString(), zone);
    return Number(wall.slice(11, 13)) * 60 + Number(wall.slice(14, 16));
  };
  const timed = events.filter((item) => !item.allDay);
  const earliest = timed.length
    ? Math.min(
        ...timed.map((item) => Math.floor(wallMinute(Math.max(Date.parse(item.start), dayStart)) / 60)),
      )
    : 8;
  const latest = timed.length
    ? Math.max(...timed.map((item) => Math.ceil(wallMinute(Math.min(Date.parse(item.end), bounds.end)) / 60)))
    : 22;
  const firstHour = Math.min(8, earliest);
  const lastHour = Math.min(24, Math.max(22, latest));
  const hourHeight = 56;
  const nowWall = inputInZone(clock.toISOString(), zone);
  const nowPosition =
    (Number(nowWall.slice(11, 13)) + Number(nowWall.slice(14, 16)) / 60 - firstHour) * hourHeight;
  useEffect(() => {
    if (scroller.current) scroller.current.scrollTop = 0;
  }, [day]);
  const weekday = weekOffset(day);
  const overlapGroups = calendarOverlapGroups(events.filter((event) => !event.allDay));
  return (
    <section className={`panel schedule-panel ${full ? 'calendar-full' : ''}`}>
      <div className="section-heading calendar-heading">
        <div className="calendar-title">
          <h2>{full ? '日历' : '今日日程'}</h2>
          <span className="section-count">{events.length}</span>
        </div>
        <div className="calendar-actions">
          <button
            className="icon-button"
            aria-label={`上${full && view === 'week' ? '一周' : full && view === 'month' ? '个月' : '一天'}`}
            onClick={() => navigate(-1)}
          >
            <ChevronLeft size={17} />
          </button>
          <button className="date-button" onClick={() => onDay(localDay())}>
            {day === localDay()
              ? '今天'
              : `${new Date(`${day}T12:00:00`).getMonth() + 1}月${new Date(`${day}T12:00:00`).getDate()}日`}
          </button>
          <button
            className="icon-button"
            aria-label={`下${full && view === 'week' ? '一周' : full && view === 'month' ? '个月' : '一天'}`}
            onClick={() => navigate(1)}
          >
            <ChevronRight size={17} />
          </button>
          <span className="toolbar-divider" />
          <button className="add-button" aria-label="新建日程" onClick={() => onEdit({ kind: 'event' })}>
            <Plus size={16} />
            <span>新建日程</span>
          </button>
        </div>
      </div>
      {full && (
        <div className="tabs calendar-view-tabs">
          {[
            ['day', '日'],
            ['week', '周'],
            ['month', '月'],
            ['timeline', '时间轴'],
            ['list', '列表'],
          ].map(([value, label]) => (
            <button
              key={value}
              className={view === value ? 'selected' : ''}
              aria-pressed={view === value}
              onClick={() => changeView(value)}
            >
              {label}
            </button>
          ))}
          <select
            aria-label="重叠样式"
            value={overlap}
            disabled={!onSave}
            onChange={(event) =>
              persist({ ...data, preferences: { ...data.preferences, overlapStyle: event.target.value } })
            }
          >
            {['并排', '层叠', '聚合'].map((value) => (
              <option key={value}>{value}</option>
            ))}
          </select>
        </div>
      )}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      {full && view !== 'day' ? (
        <div className={`calendar-range calendar-range-${view}`}>
          {Array.from({ length: rangeDays }, (_, index) => {
            const date = shiftDay(rangeStart, index);
            const items = eventsForDay(data, date).filter(
              (item) =>
                item.title.toLowerCase().includes(query.toLowerCase()) &&
                (!['list', 'timeline'].includes(view) ||
                  localDay(new Date(item.start)) === date ||
                  (index === 0 && Date.parse(item.start) < dayBounds(date, zone).start)),
            );
            if (['list', 'timeline'].includes(view) && !items.length) return null;
            return (
              <div
                key={date}
                className="calendar-range-day"
                onDragOver={(event) => event.preventDefault()}
                onDrop={(event) => drop(event, date)}
              >
                <button
                  className="date-button"
                  onClick={() => {
                    onDay(date);
                    changeView('day');
                  }}
                >
                  {new Date(`${date}T12:00`).toLocaleDateString('zh-CN', {
                    month: 'numeric',
                    day: 'numeric',
                    weekday: 'short',
                  })}
                </button>
                {view === 'week' ? (
                  <Calendar
                    data={data}
                    day={date}
                    onDay={onDay}
                    onEdit={onEdit}
                    query={query}
                    clock={clock}
                    full={false}
                    onSave={onSave}
                    overlapStyle={overlap}
                  />
                ) : (
                  items.map((item) => (
                    <div className="calendar-range-event" key={item.id}>
                      <button
                        className={`task-body ${item.completed ? 'completed' : ''}`}
                        draggable={!!onSave && !item.locked && !item.completed}
                        onDragStart={(event) =>
                          event.dataTransfer.setData('application/flowday-event', item.id)
                        }
                        onClick={() => onEdit({ kind: 'event', item })}
                        style={{ borderLeft: `3px solid ${hexColor(item.color)}` }}
                      >
                        {item.allDay ? '全天' : time(item.start)} · {item.title}
                      </button>
                      {onSave && (
                        <input
                          type="checkbox"
                          aria-label={`完成日程：${item.title}`}
                          checked={item.completed === true}
                          onChange={() => persist(setEventCompleted(data, item.id, !item.completed))}
                        />
                      )}
                    </div>
                  ))
                )}
              </div>
            );
          })}
        </div>
      ) : (
        <>
          {full && (
            <div className="week-strip">
              {Array.from({ length: 7 }, (_, index) => {
                const date = shiftDay(day, index - weekday);
                return (
                  <button key={date} className={date === day ? 'selected' : ''} onClick={() => onDay(date)}>
                    <span>{weekdays[index]}</span>
                    <strong>{new Date(`${date}T12:00:00`).getDate()}</strong>
                    {date === day && <motion.i layoutId="week-day" />}
                  </button>
                );
              })}
            </div>
          )}
          {events.some((item) => item.allDay) && (
            <div className="all-day-row">
              <span>全天</span>
              {events
                .filter((item) => item.allDay)
                .map((item) => (
                  <button
                    key={item.id}
                    onClick={() => onEdit({ kind: 'event', item })}
                    draggable={!!onSave && !item.locked && !item.completed}
                    onDragStart={(event) => event.dataTransfer.setData('application/flowday-event', item.id)}
                    style={{ '--event-color': hexColor(item.color) } as CSSProperties}
                  >
                    {item.title}
                  </button>
                ))}
            </div>
          )}
          <div className="timeline-scroll" ref={scroller}>
            <div
              className="timeline"
              style={{ height: (lastHour - firstHour) * hourHeight + 28 }}
              onDragOver={(event) => event.preventDefault()}
              onDrop={(event) => {
                const rect = event.currentTarget.getBoundingClientRect();
                const minutes = Math.max(
                  0,
                  Math.min(
                    1439,
                    Math.round((((event.clientY - rect.top - 12) / hourHeight) * 60 + firstHour * 60) / 15) *
                      15,
                  ),
                );
                drop(event, day, Math.floor(minutes / 60), minutes % 60);
              }}
            >
              {Array.from({ length: lastHour - firstHour + 1 }, (_, index) => (
                <div className="hour-line" key={index} style={{ top: index * hourHeight + 12 }}>
                  <span>{String(firstHour + index).padStart(2, '0')}:00</span>
                  <button
                    aria-label={`在 ${String(firstHour + index).padStart(2, '0')}:00 新建日程`}
                    onClick={() =>
                      onEdit({
                        kind: 'event',
                        start: `${day}T${String(Math.min(firstHour + index, 23)).padStart(2, '0')}:00`,
                      })
                    }
                  />
                </div>
              ))}
              <AnimatePresence initial={false}>
                {positioned
                  .filter(
                    ({ event }) =>
                      overlap !== '聚合' ||
                      overlapGroups.find((group) => group.some((item) => item.id === event.id))?.[0].id ===
                        event.id,
                  )
                  .map(({ event, start, end, column, columns }) => {
                    const group = overlapGroups.find((group) =>
                      group.some((item) => item.id === event.id),
                    ) ?? [event];
                    const grouped = overlap === '聚合' && group.length > 1;
                    const top = (wallMinute(start) / 60 - firstHour) * hourHeight + 13;
                    const height = Math.max(
                      27,
                      (Math.max(15, wallMinute(end) - wallMinute(start)) / 60) * hourHeight - 6,
                    );
                    return (
                      <motion.button
                        key={`${day}-${event.id}`}
                        className={`event-block ${event.completed ? 'event-completed' : ''}`}
                        style={
                          {
                            top,
                            height,
                            left:
                              overlap === '层叠'
                                ? `calc(56px + ${column * 16}px)`
                                : overlap === '聚合'
                                  ? '56px'
                                  : `calc(56px + (100% - 72px) * ${column / columns})`,
                            width:
                              overlap === '层叠'
                                ? `calc(100% - ${77 + column * 16}px)`
                                : overlap === '聚合'
                                  ? 'calc(100% - 77px)'
                                  : `calc((100% - 72px) / ${columns} - 5px)`,
                            zIndex: overlap === '层叠' ? column + 1 : undefined,
                            '--event-color': hexColor(event.color),
                          } as CSSProperties
                        }
                        initial={{ opacity: 0, y: 8 }}
                        animate={{ opacity: 1, y: 0 }}
                        exit={{ opacity: 0 }}
                        transition={{ duration: 0.2, delay: Math.min(column * 0.03, 0.1) }}
                        onClick={() =>
                          grouped ? setAggregate(group) : onEdit({ kind: 'event', item: event })
                        }
                        aria-label={grouped ? `查看 ${group.length} 个重叠日程` : `编辑日程：${event.title}`}
                        draggable={!!onSave && !grouped && !event.locked && !event.completed}
                        onDragStartCapture={(native) =>
                          native.dataTransfer.setData('application/flowday-event', event.id)
                        }
                      >
                        {height > 45 && (
                          <span className="event-time">
                            {time(event.start)} — {time(event.end)}
                          </span>
                        )}
                        <strong>{grouped ? `${group.length} 个日程` : event.title}</strong>
                        {onSave && !grouped && !event.locked && !event.completed && (
                          <span
                            className="event-resize"
                            role="slider"
                            tabIndex={0}
                            aria-label={`调整 ${event.title} 结束时间`}
                            aria-valuenow={Math.round(
                              (Date.parse(event.end) - Date.parse(event.start)) / 60000,
                            )}
                            onClick={(native) => native.stopPropagation()}
                            onKeyDown={(native) => {
                              if (['ArrowUp', 'ArrowDown'].includes(native.key)) {
                                native.preventDefault();
                                native.stopPropagation();
                                const end =
                                  Date.parse(event.end) + (native.key === 'ArrowDown' ? 15 : -15) * 60000;
                                if (end > Date.parse(event.start))
                                  persist(
                                    editRecurring(data, 'events', {
                                      ...event,
                                      end: new Date(end).toISOString(),
                                    }),
                                  );
                              }
                            }}
                            onPointerDown={(native) => {
                              native.stopPropagation();
                              native.preventDefault();
                              native.currentTarget.setPointerCapture(native.pointerId);
                              resizing.current = {
                                id: event.id,
                                y: native.clientY,
                                end: Date.parse(event.end),
                              };
                            }}
                            onPointerUp={(native) => {
                              native.stopPropagation();
                              const resize = resizing.current;
                              resizing.current = null;
                              if (!resize || resize.id !== event.id) return;
                              const end =
                                resize.end +
                                Math.round(((native.clientY - resize.y) / hourHeight) * 4) * 15 * 60000;
                              if (end > Date.parse(event.start))
                                persist(
                                  editRecurring(data, 'events', {
                                    ...event,
                                    end: new Date(end).toISOString(),
                                  }),
                                );
                            }}
                          />
                        )}
                        {event.location && height > 80 && (
                          <span className="event-location">
                            <MapPin size={12} />
                            {event.location}
                          </span>
                        )}
                      </motion.button>
                    );
                  })}
              </AnimatePresence>
              {day === localDay(clock) &&
                nowPosition >= 0 &&
                nowPosition <= (lastHour - firstHour) * hourHeight && (
                  <div className="now-line" style={{ top: nowPosition + 12 }}>
                    <span>
                      {clock.toLocaleTimeString('zh-CN', {
                        timeZone: zone,
                        hour: '2-digit',
                        minute: '2-digit',
                        hour12: false,
                      })}
                    </span>
                    <i />
                  </div>
                )}
            </div>
          </div>
        </>
      )}
      {aggregate && (
        <ToolsDialog title="重叠日程" onClose={() => setAggregate(null)}>
          {aggregate.map((item) => (
            <button
              className="task-body"
              key={item.id}
              onClick={() => {
                setAggregate(null);
                onEdit({ kind: 'event', item });
              }}
            >
              {time(item.start)} – {time(item.end)} · {item.title}
            </button>
          ))}
        </ToolsDialog>
      )}
    </section>
  );
}

export function MiniCalendar({
  day,
  onDay,
  events,
  weekStartsMonday = true,
  timezone,
}: {
  day: string;
  onDay: (day: string) => void;
  events: CalendarEvent[];
  weekStartsMonday?: boolean;
  timezone?: string;
}) {
  const [month, setMonth] = useState(() => day.slice(0, 7));
  useEffect(() => setMonth(day.slice(0, 7)), [day]);
  const first = new Date(`${month}-01T12:00:00`);
  const offset = weekStartsMonday ? (first.getDay() + 6) % 7 : first.getDay();
  const start = shiftDay(localDay(first), -offset);
  const count = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
  const cells = Math.ceil((count + offset) / 7) * 7;
  const eventDays = new Set(
    events
      .filter((item) => !item.deletedAt)
      .map((item) => (timezone ? dayInZone(new Date(item.start), timezone) : localDay(new Date(item.start)))),
  );
  function move(offset: number) {
    const next = new Date(first);
    next.setMonth(next.getMonth() + offset);
    setMonth(localDay(next).slice(0, 7));
  }
  return (
    <section className="panel mini-calendar">
      <div className="section-heading">
        <h2>
          {first.getFullYear()}年{first.getMonth() + 1}月
        </h2>
        <div className="month-arrows">
          <button className="icon-button" aria-label="上个月" onClick={() => move(-1)}>
            <ChevronLeft size={16} />
          </button>
          <button className="icon-button" aria-label="下个月" onClick={() => move(1)}>
            <ChevronRight size={16} />
          </button>
        </div>
      </div>
      <div className="month-grid weekdays">
        {(weekStartsMonday
          ? ['一', '二', '三', '四', '五', '六', '日']
          : ['日', '一', '二', '三', '四', '五', '六']
        ).map((label) => (
          <span key={label}>{label}</span>
        ))}
      </div>
      <div className="month-grid">
        {Array.from({ length: cells }, (_, index) => {
          const date = shiftDay(start, index);
          return (
            <button
              key={date}
              aria-label={date}
              aria-pressed={date === day}
              className={`${date.slice(0, 7) !== month ? 'outside' : ''} ${date === day ? 'selected' : ''} ${date === localDay() ? 'current' : ''}`}
              onClick={() => onDay(date)}
            >
              {date === day && (
                <motion.span
                  className="day-selection"
                  layoutId="mini-day"
                  transition={{ type: 'spring', stiffness: 480, damping: 36 }}
                />
              )}
              <span>{new Date(`${date}T12:00:00`).getDate()}</span>
              {eventDays.has(date) && <i />}
            </button>
          );
        })}
      </div>
    </section>
  );
}
