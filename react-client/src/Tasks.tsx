import { useState } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import { ArrowUpRight, Plus } from './icons';
import type { Editing } from './App';
import { zoneFor, dayInZone } from './timezone';
import { hexColor, type Workspace } from './workspace';
import { isProjectHidden, archiveItem, restoreItem, setTaskStatus, trashItem } from './domain';

type Props = {
  data: Workspace;
  day: string;
  query: string;
  project: string | null;
  onEdit: (editing: Editing) => void;
  onToggle: (id: string) => void;
  full?: boolean;
  onSave?: (data: Workspace) => boolean;
};
export function Tasks({ data, day, query, project, onEdit, onToggle, full, onSave }: Props) {
  const zone = zoneFor(data);
  const localDay = (date: Date) => dayInZone(date, zone);
  const [filter, setFilter] = useState('全部');
  const [selected, setSelected] = useState<string[]>([]);
  const [error, setError] = useState('');
  function batch(action: 'done' | 'archive' | 'trash' | 'restore') {
    let next = data;
    for (const id of selected)
      next =
        action === 'done'
          ? setTaskStatus(next, id, 'done')
          : action === 'archive'
            ? archiveItem(next, 'tasks', id, filter !== '归档')
            : action === 'trash'
              ? trashItem(next, 'tasks', id)
              : restoreItem(next, 'tasks', id);
    if (onSave?.(next)) {
      setSelected([]);
      setError('');
    } else setError('保存失败');
  }
  const tasks = data.tasks.filter(
    (item) =>
      (filter === '回收站' ? !!item.deletedAt : !item.deletedAt) &&
      (filter === '归档' ? !!item.archived : filter === '回收站' || !item.archived) &&
      (filter === '回收站' || item.status !== 'cancelled') &&
      (!project || item.projectId === project) &&
      (filter === '回收站' || filter === '归档' || !isProjectHidden(data, item.projectId)),
  );
  const filtered = tasks.filter(
    (item) =>
      item.title.toLocaleLowerCase().includes(query.toLocaleLowerCase()) &&
      (['归档', '回收站'].includes(filter)
        ? true
        : filter === '已完成'
          ? item.status === 'done'
          : item.status !== 'done' &&
            (filter === '今天'
              ? Boolean(item.deadline && localDay(new Date(item.deadline)) === day)
              : filter === '高优先级'
                ? ['high', 'urgent'].includes(item.priority)
                : true)),
  );
  return (
    <section className={`panel tasks-panel ${full ? 'tasks-full' : ''}`}>
      <div className="section-heading">
        <h2 aria-label="任务">
          任务 <span className="section-count">{tasks.filter((item) => item.status !== 'done').length}</span>
        </h2>
        <button className="add-button" aria-label="新建任务" onClick={() => onEdit({ kind: 'task' })}>
          <Plus size={16} />
          <span>新建任务</span>
        </button>
      </div>
      <div className="tabs" aria-label="任务筛选">
        {['全部', '今天', '高优先级', '已完成', ...(full && onSave ? ['归档', '回收站'] : [])].map(
          (label) => (
            <button
              key={label}
              className={filter === label ? 'selected' : ''}
              aria-pressed={filter === label}
              onClick={() => {
                setFilter(label);
                setSelected([]);
              }}
            >
              {filter === label && (
                <motion.span
                  className="tab-selection"
                  layoutId={`task-filter-${full ? 'full' : 'today'}`}
                  transition={{ type: 'spring', stiffness: 500, damping: 38 }}
                />
              )}
              <span>{label}</span>
            </button>
          ),
        )}
      </div>
      {!!selected.length && onSave && (
        <div className="batch-actions">
          <span>{selected.length} 项</span>
          {filter === '回收站' ? (
            <button className="secondary-button" onClick={() => batch('restore')}>
              恢复
            </button>
          ) : (
            <>
              <button className="secondary-button" onClick={() => batch('done')}>
                完成
              </button>
              <button className="secondary-button" onClick={() => batch('archive')}>
                {filter === '归档' ? '取消归档' : '归档'}
              </button>
              <button className="secondary-button" onClick={() => batch('trash')}>
                删除
              </button>
            </>
          )}
        </div>
      )}
      {error && (
        <p className="form-error" role="alert">
          {error}
        </p>
      )}
      <div className="task-list">
        <AnimatePresence initial={false} mode="popLayout">
          {filtered.map((task) => {
            const owner = data.projects.find((item) => item.id === task.projectId);
            const minutes = typeof task.estimateMinutes === 'number' ? task.estimateMinutes : 0;
            const deadline = task.deadline ? new Date(task.deadline) : null;
            return (
              <motion.div
                layout="position"
                key={task.id}
                className={`task-row ${task.status === 'done' ? 'completed' : ''}`}
                initial={{ opacity: 0, y: 9 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, x: 12 }}
                transition={{ duration: 0.18 }}
                draggable={!task.deletedAt && task.status !== 'done'}
                onDragStartCapture={(event) => {
                  event.dataTransfer.setData('application/flowday-task', task.id);
                  event.dataTransfer.effectAllowed = 'copy';
                }}
              >
                {full && onSave && (
                  <input
                    type="checkbox"
                    aria-label={`选择任务：${task.title}`}
                    checked={selected.includes(task.id)}
                    onChange={(event) =>
                      setSelected(
                        event.target.checked
                          ? [...selected, task.id]
                          : selected.filter((id) => id !== task.id),
                      )
                    }
                  />
                )}
                <label className="task-checkbox">
                  <input
                    type="checkbox"
                    aria-label={`完成任务：${task.title}`}
                    checked={task.status === 'done'}
                    onChange={() => onToggle(task.id)}
                  />
                  <span>
                    <svg viewBox="0 0 16 16">
                      <motion.path
                        d="M3.5 8.5 6.5 11.5 12.5 4.5"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="1.8"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        initial={false}
                        animate={{
                          pathLength: task.status === 'done' ? 1 : 0,
                          opacity: task.status === 'done' ? 1 : 0,
                        }}
                      />
                    </svg>
                  </span>
                </label>
                <button
                  className="task-body"
                  aria-label={`编辑任务：${task.title}`}
                  onClick={() => onEdit({ kind: 'task', item: task })}
                >
                  <span className="task-title">{task.title}</span>
                  <span className="task-meta">
                    {owner && (
                      <span className="task-project">
                        <i style={{ background: hexColor(owner.color) }} />
                        {owner.title}
                      </span>
                    )}
                    {deadline && (
                      <span>
                        {localDay(deadline) === day
                          ? '今天'
                          : `${deadline.getMonth() + 1}/${deadline.getDate()}`}{' '}
                        {deadline.toLocaleTimeString('zh-CN', {
                          hour: '2-digit',
                          minute: '2-digit',
                          timeZone: zone,
                          hour12: false,
                        })}
                      </span>
                    )}
                    {minutes > 0 && (
                      <span>
                        {minutes >= 60 ? `${Math.round((minutes / 60) * 10) / 10}h` : `${minutes}min`}
                      </span>
                    )}
                  </span>
                </button>
                {['high', 'urgent'].includes(task.priority) && (
                  <span
                    className={`priority ${task.priority}`}
                    aria-label={task.priority === 'urgent' ? '紧急' : '高优先级'}
                  >
                    {task.priority === 'urgent' ? '紧急' : '高'}
                  </span>
                )}
                <button
                  className="task-open icon-button"
                  aria-label={`打开任务：${task.title}`}
                  onClick={() => onEdit({ kind: 'task', item: task })}
                >
                  <ArrowUpRight size={17} />
                </button>
              </motion.div>
            );
          })}
        </AnimatePresence>
      </div>
      <form
        className="quick-add"
        onSubmit={(event) => {
          event.preventDefault();
          const form = event.currentTarget;
          const input = form.elements.namedItem('title') as HTMLInputElement;
          if (input.value.trim())
            onEdit({
              kind: 'task',
              item: {
                id: '',
                title: input.value.trim(),
                status: 'todo',
                priority: 'normal',
                projectId: project,
              },
            });
          input.value = '';
        }}
      >
        <Plus size={17} />
        <input name="title" aria-label="快速添加任务" placeholder="添加任务…" autoComplete="off" />
        <button aria-label="继续添加任务" type="submit">
          <ArrowUpRight size={16} />
        </button>
      </form>
    </section>
  );
}
