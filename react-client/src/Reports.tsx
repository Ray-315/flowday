import { useState } from 'react';
import type { Editing } from './App';
import { shiftDay, type Workspace } from './workspace';
import { dayBounds, zoneFor } from './timezone';
export function reportStatistics(data: Workspace, start: string, end: string) {
  const from = Date.parse(start),
    to = Date.parse(end);
  if (!Number.isFinite(from) || !Number.isFinite(to) || from >= to) throw new Error('统计日期范围无效');
  const inPeriod = (value: unknown) =>
    typeof value === 'string' && Date.parse(value) >= from && Date.parse(value) < to;
  const active = (projectId: unknown) =>
    !projectId ||
    data.projects.some((project) => project.id === projectId && !project.deletedAt && !project.archived);
  const events = data.events.filter(
    (event) =>
      !event.deletedAt &&
      active(event.projectId) &&
      Date.parse(event.start) < to &&
      Date.parse(event.end) > from,
  );
  const ids = new Set(events.map((event) => event.taskId));
  const tasks = data.tasks.filter(
    (task) =>
      !task.deletedAt &&
      active(task.projectId) &&
      task.status !== 'cancelled' &&
      (inPeriod(task.completedAt) ||
        inPeriod(task.plannedStart) ||
        inPeriod(task.deadline) ||
        ids.has(task.id)),
  );
  const done = tasks.filter((task) => task.status === 'done' && inPeriod(task.completedAt));
  const actual =
    events
      .filter((event) => event.completed)
      .reduce(
        (sum, event) =>
          sum +
          Math.round(
            (Number(event.actualMinutes ?? 0) *
              (Math.min(to, Date.parse(event.end)) - Math.max(from, Date.parse(event.start)))) /
              (Date.parse(event.end) - Date.parse(event.start)),
          ),
        0,
      ) +
    tasks
      .filter((task) => inPeriod(task.completedAt) || (!task.completedAt && inPeriod(task.plannedStart)))
      .reduce(
        (sum, task) =>
          sum +
          Math.max(
            0,
            Number(task.actualMinutes ?? 0) -
              data.events
                .filter((event) => !event.deletedAt && event.taskId === task.id && event.completed)
                .reduce((minutes, event) => minutes + Number(event.actualMinutes ?? 0), 0),
          ),
        0,
      );
  const distribution = [
    ...data.projects
      .filter((project) => !project.deletedAt && !project.archived)
      .map((project) => ({ id: project.id, title: project.title })),
    { id: '', title: '无项目' },
  ]
    .map((project) => {
      const owned = tasks.filter((task) => (task.projectId ?? '') === project.id);
      const ownedEvents = events.filter((event) => (event.projectId ?? '') === project.id);
      return {
        ...project,
        tasks: owned.length,
        done: owned.filter((task) => task.status === 'done' && inPeriod(task.completedAt)).length,
        planned: Math.round(
          ownedEvents.reduce(
            (sum, event) =>
              sum + (Math.min(to, Date.parse(event.end)) - Math.max(from, Date.parse(event.start))) / 60000,
            0,
          ),
        ),
      };
    })
    .filter((project) => project.tasks || project.planned);
  const pressure = Array.from({ length: Math.min(366, Math.ceil((to - from) / 86400000)) }, (_, index) => {
    const dayStart = from + index * 86400000,
      dayEnd = Math.min(to, dayStart + 86400000);
    return {
      day: new Date(dayStart).toISOString().slice(0, 10),
      minutes: Math.round(
        events.reduce(
          (sum, event) =>
            sum +
            Math.max(
              0,
              Math.min(dayEnd, Date.parse(event.end)) - Math.max(dayStart, Date.parse(event.start)),
            ) /
              60000,
          0,
        ),
      ),
    };
  });
  return {
    tasks,
    events,
    distribution,
    pressure,
    done: done.length,
    actual,
    estimated: tasks.reduce((sum, task) => sum + Number(task.estimateMinutes ?? 0), 0),
    completion: tasks.length ? Math.round((done.length / tasks.length) * 100) : 0,
  };
}
export function Reports({
  data,
  day,
  onEdit,
}: {
  data: Workspace;
  day: string;
  onEdit?: (editing: Editing) => void;
}) {
  const [start, setStart] = useState(shiftDay(day, -6));
  const [end, setEnd] = useState(day);
  const valid = !!start && !!end && start <= end;
  const zone = zoneFor(data);
  const stats = valid
    ? reportStatistics(
        data,
        new Date(dayBounds(start, zone).start).toISOString(),
        new Date(dayBounds(end, zone).end).toISOString(),
      )
    : null;
  function exportCSV() {
    if (!stats) return;
    const escape = (value: string) =>
      `"${(/^[=+@\-\t\r]/.test(value) ? "'" : '') + value.replace(/"/g, '""')}"`;
    const rows = [
      ['完成任务', '实际分钟', '预计分钟', '完成率'],
      [String(stats.done), String(stats.actual), String(stats.estimated), `${stats.completion}%`],
    ];
    const url = URL.createObjectURL(
      new Blob(['\ufeff' + rows.map((row) => row.map(escape).join(',')).join('\r\n')], {
        type: 'text/csv;charset=utf-8',
      }),
    );
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `flowday-statistics-${start}-${end}.csv`;
    anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  return (
    <section className="panel editor-fields">
      <div className="section-heading">
        <h2>统计分析</h2>
        <button className="secondary-button" onClick={exportCSV} disabled={!stats}>
          导出 CSV
        </button>
      </div>
      <div className="tabs">
        {[
          ['日', 0],
          ['周', 6],
          ['月', 29],
        ].map(([label, offset]) => (
          <button
            key={label}
            onClick={() => {
              setStart(shiftDay(day, -Number(offset)));
              setEnd(day);
            }}
          >
            {label}
          </button>
        ))}
      </div>
      <div className="field-pair">
        <label className="field">
          <span>开始日期</span>
          <input type="date" value={start} onChange={(event) => setStart(event.target.value)} />
        </label>
        <label className="field">
          <span>结束日期</span>
          <input type="date" value={end} onChange={(event) => setEnd(event.target.value)} />
        </label>
      </div>
      {stats ? (
        <>
          <div className="report-stats">
            {[
              ['完成任务', stats.done],
              ['实际投入', `${(stats.actual / 60).toFixed(1)} h`],
              ['预计耗时', `${(stats.estimated / 60).toFixed(1)} h`],
              ['完成率', `${stats.completion}%`],
            ].map(([label, value]) => (
              <div key={label}>
                <span>{label}</span>
                <strong>{value}</strong>
              </div>
            ))}
          </div>
          <h3>项目分布</h3>
          <table className="report-table">
            <thead>
              <tr>
                <th>项目</th>
                <th>任务</th>
                <th>完成</th>
                <th>排程分钟</th>
              </tr>
            </thead>
            <tbody>
              {stats.distribution.map((project) => (
                <tr key={project.id}>
                  <td>{project.title}</td>
                  <td>{project.tasks}</td>
                  <td>{project.done}</td>
                  <td>{project.planned}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <details>
            <summary>每日负荷</summary>
            <div className="report-pressure">
              {stats.pressure.map((entry) => (
                <div key={entry.day}>
                  <span>{entry.day}</span>
                  <meter
                    min="0"
                    max={Math.max(480, ...stats.pressure.map((item) => item.minutes))}
                    value={entry.minutes}
                  />
                  <span>{entry.minutes} 分钟</span>
                </div>
              ))}
            </div>
          </details>
          <h3>任务回顾</h3>
          {stats.tasks.map((task) => (
            <button
              className="task-body"
              key={task.id}
              onClick={() => onEdit?.({ kind: 'task', item: task })}
            >
              {task.title} · {task.status === 'done' ? '已完成' : '未完成'} ·{' '}
              {Number(task.actualMinutes ?? 0)} 分钟
            </button>
          ))}
        </>
      ) : (
        <p className="form-error" role="alert">
          统计日期范围无效
        </p>
      )}
    </section>
  );
}
