import { Select } from './Select';
import { useEffect, useRef, useState, type PointerEvent, type KeyboardEvent } from 'react';
import { Plus, Copy, ClipboardPaste, Undo2, Redo2, Trash2, Network, CalendarPlus, X } from './icons';
import type { Editing } from './App';
import { dateTimeInput, type Workspace } from './workspace';
import {
  addWorkflowEdge,
  captureWorkflow,
  copyWorkflowSelection,
  deleteWorkflowSelection,
  layoutWorkflow,
  moveWorkflowSelection,
  workflowDragIds,
  workflowSelectionBounds,
  selectWorkflowNodes,
  pasteWorkflowSelection,
  refreshWorkflow,
  restoreWorkflow,
  saveWorkflowNode,
  selectBranch,
  setNodeStatus,
  workflowEdges,
  workflowNodes,
  isProjectHidden,
  type FlowEdge,
  type FlowNode,
  type NodeKind,
  type NodeStatus,
  type WorkflowSnapshot,
  type WorkflowPoint,
} from './domain';
import './workflow.css';

const kinds: Record<NodeKind, string> = {
  task: '任务',
  condition: '条件',
  delay: '延迟',
  milestone: '里程碑',
  note: '备注',
  link: '项目跳转',
  group: '分组',
};
const statuses: Record<NodeStatus, string> = {
  locked: '锁定',
  ready: '就绪',
  doing: '进行中',
  waiting: '等待',
  done: '完成',
  skipped: '跳过',
};
export type WorkflowProps = {
  data: Workspace;
  onSave: (data: Workspace) => boolean;
  onProject?: (id: string) => void;
  onEdit?: (editing: Editing) => void;
  projectId?: string | null;
  nodeId?: string | null;
};

export function Workflow({
  data,
  onSave,
  onProject,
  onEdit,
  projectId: focusProjectId,
  nodeId: focusNodeId,
}: WorkflowProps) {
  const projects = data.projects.filter((p) => !isProjectHidden(data, p.id));
  const [projectId, setProjectId] = useState(projects[0]?.id ?? '');
  const [selection, setSelection] = useState<string[]>([]);
  const [draft, setDraft] = useState<FlowNode | null>(null);
  const [edgeDraft, setEdgeDraft] = useState<FlowEdge | null>(null);
  const [connecting, setConnecting] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [zoom, setZoom] = useState(1);
  const [drag, setDrag] = useState<{
    id: string;
    startX: number;
    startY: number;
    dx: number;
    dy: number;
    ids: string[];
  } | null>(null);
  const [box, setBox] = useState<{ start: WorkflowPoint; end: WorkflowPoint; initial: string[] } | null>(
    null,
  );
  const [, renderHistory] = useState(0);
  const clipboard = useRef<WorkflowSnapshot | null>(null);
  const appliedFocus = useRef<string | null>(null);
  const undo = useRef<WorkflowSnapshot[]>([]),
    redo = useRef<WorkflowSnapshot[]>([]);
  const viewport = useRef<HTMLDivElement>(null);
  const modal = useRef<HTMLDialogElement>(null);
  const nodes = workflowNodes(data).filter((n) => n.projectId === projectId);
  const edges = workflowEdges(data).filter((e) => e.projectId === projectId);
  const selected = nodes.find((n) => selection.includes(n.id));
  const hidden = (node: FlowNode) => {
    let parent = node.groupId;
    const visited = new Set<string>();
    while (parent && !visited.has(parent)) {
      visited.add(parent);
      const group = nodes.find((n) => n.id === parent);
      if (group?.collapsed) return true;
      parent = group?.groupId;
    }
    return false;
  };
  const visible = nodes.filter((n) => !hidden(n));
  const movingIds = new Set(drag?.ids ?? []);
  const selectionBox = box ? workflowSelectionBounds(box.start, box.end) : null;
  const position = (node: FlowNode) => ({
    x: node.x + (movingIds.has(node.id) ? (drag?.dx ?? 0) : 0),
    y: node.y + (movingIds.has(node.id) ? (drag?.dy ?? 0) : 0),
  });
  const width = Math.max(1400, ...nodes.map((n) => n.x + 300)),
    height = Math.max(800, ...nodes.map((n) => n.y + 200));

  useEffect(() => {
    if (!projects.some((p) => p.id === projectId)) setProjectId(projects[0]?.id ?? '');
  }, [data.projects, projectId]);
  useEffect(() => {
    undo.current = [];
    redo.current = [];
    setSelection([]);
    setConnecting(null);
    renderHistory((n) => n + 1);
  }, [projectId]);
  useEffect(() => {
    const request = JSON.stringify([focusProjectId, focusNodeId]);
    if (appliedFocus.current === request) return;
    const target = focusNodeId ? workflowNodes(data).find((n) => n.id === focusNodeId) : undefined;
    const desired = target?.projectId ?? focusProjectId;
    if (!desired || !projects.some((p) => p.id === desired)) return;
    if (desired !== projectId) {
      setProjectId(desired);
      return;
    }
    appliedFocus.current = request;
    if (target) {
      setSelection([target.id]);
      const view = viewport.current;
      if (view) {
        view.scrollLeft = Math.max(0, target.x * zoom - view.clientWidth / 2 + 100 * zoom);
        view.scrollTop = Math.max(0, target.y * zoom - view.clientHeight / 2 + 43 * zoom);
        view.focus({ preventScroll: true });
      }
    }
  }, [focusProjectId, focusNodeId, projectId]);
  useEffect(() => {
    const refresh = () => {
      const next = refreshWorkflow(data);
      if (JSON.stringify(next.nodes) !== JSON.stringify(data.nodes)) onSave(next);
    };
    refresh();
    const timer = setInterval(refresh, 30000);
    return () => clearInterval(timer);
  }, [data, onSave]);
  useEffect(() => {
    if (draft || edgeDraft) {
      modal.current?.showModal();
      modal.current?.querySelector<HTMLInputElement>('input')?.focus();
    }
    return () => {
      modal.current?.close();
    };
  }, [Boolean(draft || edgeDraft)]);

  function apply(operation: () => Workspace) {
    try {
      const next = operation();
      if (!onSave(next)) return false;
      undo.current.push(captureWorkflow(data, projectId));
      if (undo.current.length > 100) undo.current.shift();
      redo.current = [];
      renderHistory((n) => n + 1);
      setError('');
      return true;
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : '无法保存工作流');
      return false;
    }
  }
  function history(forward = false) {
    const source = forward ? redo.current : undo.current,
      destination = forward ? undo.current : redo.current;
    const snapshot = source.at(-1);
    if (!snapshot) return;
    if (onSave(restoreWorkflow(data, snapshot))) {
      destination.push(captureWorkflow(data, projectId));
      source.pop();
      setSelection([]);
      setError('');
      renderHistory((n) => n + 1);
    }
  }
  function copy() {
    clipboard.current = copyWorkflowSelection(data, selection);
    renderHistory((n) => n + 1);
  }
  function paste() {
    if (!clipboard.current) return;
    const next = pasteWorkflowSelection(data, clipboard.current, projectId);
    const existing = new Set(workflowNodes(data).map((node) => node.id));
    if (apply(() => next))
      setSelection(
        workflowNodes(next)
          .filter((node) => !existing.has(node.id))
          .map((node) => node.id),
      );
  }
  function create(kind?: NodeKind) {
    if (!projectId) return;
    const defaultKind = data.preferences.workflowDefaultKind;
    kind ??= ['task', 'milestone', 'note'].includes(String(defaultKind)) ? (defaultKind as NodeKind) : 'task';
    setDraft({
      id: crypto.randomUUID(),
      projectId,
      title: '',
      description: '',
      kind,
      status: 'ready',
      x: 40 + (viewport.current?.scrollLeft ?? 0) / zoom,
      y: 40 + (viewport.current?.scrollTop ?? 0) / zoom,
      anyPredecessor: false,
      collapsed: false,
    });
  }
  function connect(targetId: string) {
    if (!connecting) {
      setConnecting(targetId);
      return;
    }
    if (
      connecting !== targetId &&
      apply(() =>
        addWorkflowEdge(data, {
          id: crypto.randomUUID(),
          projectId,
          sourceId: connecting,
          targetId,
          label: '',
          active: true,
          delayMinutes: 0,
        }),
      )
    )
      setConnecting(null);
  }
  function startDrag(event: PointerEvent<HTMLDivElement>, node: FlowNode) {
    if (event.button !== 0 || (event.target as HTMLElement).closest('button')) return;
    if (event.ctrlKey || event.metaKey) {
      setSelection((ids) => (ids.includes(node.id) ? ids.filter((id) => id !== node.id) : [...ids, node.id]));
      return;
    }
    const ids = workflowDragIds(nodes, selection, node.id);
    if (!selection.includes(node.id)) setSelection([node.id]);
    viewport.current?.focus({ preventScroll: true });
    event.currentTarget.setPointerCapture(event.pointerId);
    setDrag({ id: node.id, startX: event.clientX, startY: event.clientY, dx: 0, dy: 0, ids });
  }
  function canvasPoint(event: PointerEvent<HTMLDivElement>): WorkflowPoint {
    const rect = event.currentTarget.getBoundingClientRect();
    return { x: (event.clientX - rect.left) / zoom, y: (event.clientY - rect.top) / zoom };
  }
  function shortcuts(e: KeyboardEvent<HTMLElement>) {
    if (
      draft ||
      edgeDraft ||
      (e.target as HTMLElement).closest('input,textarea,select,[role=combobox],[role=listbox],[contenteditable="true"]')
    )
      return;
    const key = e.key.toLowerCase(),
      modified = e.ctrlKey || e.metaKey;
    if (modified && key === 'c') {
      e.preventDefault();
      copy();
    } else if (modified && key === 'v') {
      e.preventDefault();
      paste();
    } else if (modified && key === 'z') {
      e.preventDefault();
      history(e.shiftKey);
    } else if (modified && key === 'y') {
      e.preventDefault();
      history(true);
    } else if (e.key === 'Delete' && selection.length) {
      e.preventDefault();
      if (apply(() => deleteWorkflowSelection(data, selection))) setSelection([]);
    } else if (e.key === 'Escape') {
      setConnecting(null);
      setBox(null);
    }
  }
  function calendar(node: FlowNode) {
    const task = data.tasks.find((t) => t.id === node.taskId);
    if (!task) return;
    const existing = data.events.find((e) => e.taskId === task.id && !e.deletedAt);
    if (existing) {
      onEdit?.({ kind: 'event', item: existing });
      return;
    }
    const start = typeof task.plannedStart === 'string' ? task.plannedStart : new Date().toISOString();
    const event = {
      id: crypto.randomUUID(),
      title: task.title,
      start,
      end: new Date(Date.parse(start) + Number(task.estimateMinutes ?? 60) * 60000).toISOString(),
      color: data.projects.find((p) => p.id === task.projectId)?.color ?? 0xff4b70e8,
      projectId: task.projectId,
      taskId: task.id,
      completed: false,
      locked: false,
      allDay: false,
      actualMinutes: 0,
      tags: [],
      attachments: [],
    };
    if (onSave({ ...data, events: [...data.events, event] })) onEdit?.({ kind: 'event', item: event });
  }
  function groupSelection() {
    const group: FlowNode = {
      id: crypto.randomUUID(),
      projectId,
      title: '分组',
      kind: 'group',
      status: 'ready',
      x: Math.min(...nodes.filter((n) => selection.includes(n.id)).map((n) => n.x)) - 20,
      y: Math.min(...nodes.filter((n) => selection.includes(n.id)).map((n) => n.y)) - 40,
      anyPredecessor: false,
    };
    if (
      apply(() => {
        const next = saveWorkflowNode(data, group);
        return {
          ...next,
          nodes: workflowNodes(next).map((n) => (selection.includes(n.id) ? { ...n, groupId: group.id } : n)),
        };
      })
    ) {
      setSelection([group.id]);
      setDraft(group);
    }
  }

  return (
    <section className="workflow-page" aria-label="工作流" onKeyDown={shortcuts}>
      <div className="workflow-toolbar">
        <Select aria-label="工作流项目" value={projectId} onChange={(e) => setProjectId(e.target.value)}>
          {projects.map((p) => (
            <option key={p.id} value={p.id}>
              {p.title}
            </option>
          ))}
        </Select>
        <button className="secondary-button" onClick={() => create()} disabled={!projectId}>
          <Plus size={16} />
          节点
        </button>
        <button className="icon-button" aria-label="复制" disabled={!selection.length} onClick={copy}>
          <Copy size={17} />
        </button>
        <button
          className="icon-button"
          aria-label="粘贴"
          disabled={!clipboard.current?.nodes.length || !projectId}
          onClick={paste}
        >
          <ClipboardPaste size={17} />
        </button>
        <button
          className="icon-button"
          aria-label="撤销"
          disabled={!undo.current.length}
          onClick={() => history()}
        >
          <Undo2 size={17} />
        </button>
        <button
          className="icon-button"
          aria-label="重做"
          disabled={!redo.current.length}
          onClick={() => history(true)}
        >
          <Redo2 size={17} />
        </button>
        <button
          className="icon-button"
          aria-label="删除"
          disabled={!selection.length}
          onClick={() => {
            if (apply(() => deleteWorkflowSelection(data, selection))) setSelection([]);
          }}
        >
          <Trash2 size={17} />
        </button>
        <button
          className="icon-button"
          aria-label="自动布局"
          disabled={!nodes.length}
          onClick={() => apply(() => layoutWorkflow(data, projectId))}
        >
          <Network size={17} />
        </button>
        <button className="secondary-button" disabled={!selection.length} onClick={groupSelection}>
          分组
        </button>
        <input
          aria-label="工作流缩放"
          type="range"
          min="0.25"
          max="2"
          step="0.05"
          value={zoom}
          onChange={(e) => setZoom(Number(e.target.value))}
        />
        {connecting && (
          <button className="icon-button" aria-label="取消连接" onClick={() => setConnecting(null)}>
            <X size={17} />
          </button>
        )}
      </div>
      {error && (
        <div className="form-error" role="alert">
          {error}
        </div>
      )}
      <div className="workflow-body">
        <div ref={viewport} className="workflow-viewport" tabIndex={0}>
          <div style={{ width: width * zoom, height: height * zoom }}>
            <div
              className="workflow-canvas"
              style={{ width, height, transform: `scale(${zoom})` }}
              onPointerDown={(e) => {
                if (e.target !== e.currentTarget || e.button !== 0) return;
                e.preventDefault();
                viewport.current?.focus({ preventScroll: true });
                e.currentTarget.setPointerCapture(e.pointerId);
                const point = canvasPoint(e);
                setBox({ start: point, end: point, initial: e.ctrlKey || e.metaKey ? selection : [] });
                if (!e.ctrlKey && !e.metaKey) setSelection([]);
              }}
              onPointerMove={(e) => {
                if (box) setBox({ ...box, end: canvasPoint(e) });
              }}
              onPointerUp={(e) => {
                if (box) {
                  setSelection([
                    ...new Set([
                      ...box.initial,
                      ...selectWorkflowNodes(visible, workflowSelectionBounds(box.start, canvasPoint(e))),
                    ]),
                  ]);
                  setBox(null);
                }
              }}
              onPointerCancel={() => setBox(null)}
            >
              <svg className="workflow-edges" width={width} height={height}>
                <defs>
                  <marker
                    id="workflow-arrow"
                    viewBox="0 0 10 10"
                    refX="9"
                    refY="5"
                    markerWidth="7"
                    markerHeight="7"
                    orient="auto-start-reverse"
                  >
                    <path d="M 0 0 L 10 5 L 0 10 z" fill="currentColor" />
                  </marker>
                </defs>
                {edges.map((edge) => {
                  const source = visible.find((n) => n.id === edge.sourceId),
                    target = visible.find((n) => n.id === edge.targetId);
                  if (!source || !target) return null;
                  const a = position(source),
                    b = position(target),
                    x = a.x + 200,
                    y = a.y + 43,
                    tx = b.x,
                    ty = b.y + 43;
                  return (
                    <g
                      key={edge.id}
                      className={`workflow-edge ${selection.includes(edge.id) ? 'selected' : ''} ${edge.active ? '' : 'inactive'}`}
                      onClick={() => {
                        setSelection([edge.id]);
                        setEdgeDraft({ ...edge });
                      }}
                    >
                      <path
                        d={`M${x},${y} C${x + 80},${y} ${tx - 80},${ty} ${tx},${ty}`}
                        markerEnd="url(#workflow-arrow)"
                      />
                      <path
                        className="workflow-edge-hit"
                        d={`M${x},${y} C${x + 80},${y} ${tx - 80},${ty} ${tx},${ty}`}
                      />
                      {edge.label && (
                        <text x={(x + tx) / 2} y={(y + ty) / 2 - 9}>
                          {edge.label}
                        </text>
                      )}
                    </g>
                  );
                })}
              </svg>
              {visible.map((node) => {
                const p = position(node);
                return (
                  <div
                    key={node.id}
                    className={`workflow-node ${selection.includes(node.id) ? 'selected' : ''} kind-${node.kind}`}
                    style={{ left: p.x, top: p.y }}
                    role="button"
                    tabIndex={0}
                    aria-label={node.title}
                    aria-pressed={selection.includes(node.id)}
                    onDoubleClick={() => setDraft({ ...node })}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        e.stopPropagation();
                        setDraft({ ...node });
                      }
                    }}
                    onPointerDown={(e) => startDrag(e, node)}
                    onPointerMove={(e) => {
                      if (drag?.id === node.id)
                        setDrag({
                          ...drag,
                          dx: (e.clientX - drag.startX) / zoom,
                          dy: (e.clientY - drag.startY) / zoom,
                        });
                    }}
                    onPointerUp={() => {
                      if (drag?.id === node.id) {
                        if (Math.abs(drag.dx) + Math.abs(drag.dy) > 1)
                          apply(() => moveWorkflowSelection(data, drag.ids, drag.id, drag.dx, drag.dy));
                        setDrag(null);
                      }
                    }}
                    onPointerCancel={() => setDrag(null)}
                  >
                    <button
                      className={`workflow-port input ${connecting ? 'connecting' : ''}`}
                      aria-label={`连接到${node.title}`}
                      onClick={() => connect(node.id)}
                    />
                    <span className="workflow-node-kind">{kinds[node.kind]}</span>
                    <strong>{node.title}</strong>
                    <span className="workflow-node-status">{statuses[node.status]}</span>
                    <button
                      className={`workflow-port output ${connecting === node.id ? 'connecting' : ''}`}
                      aria-label={`从${node.title}连接`}
                      onClick={() => setConnecting(connecting === node.id ? null : node.id)}
                    />
                  </div>
                );
              })}
              {selectionBox && (
                <div
                  className="workflow-selection-box"
                  style={{
                    left: selectionBox.left,
                    top: selectionBox.top,
                    width: selectionBox.right - selectionBox.left,
                    height: selectionBox.bottom - selectionBox.top,
                  }}
                />
              )}
            </div>
          </div>
        </div>
        {selected && (
          <aside className="workflow-inspector">
            <h3>{selected.title}</h3>
            <button className="secondary-button" onClick={() => setDraft({ ...selected })}>
              编辑节点
            </button>
            <label>
              状态
              <Select
                aria-label="节点状态"
                value={selected.status}
                onChange={(e) => apply(() => setNodeStatus(data, selected.id, e.target.value as NodeStatus))}
              >
                {Object.entries(statuses).map(([value, title]) => (
                  <option key={value} value={value}>
                    {title}
                  </option>
                ))}
              </Select>
            </label>
            {selected.kind === 'condition' && (
              <label>
                条件出口
                <Select
                  aria-label="条件出口"
                  value={selected.selectedBranchEdgeId ?? ''}
                  onChange={(e) =>
                    e.target.value && apply(() => selectBranch(data, selected.id, e.target.value))
                  }
                >
                  <option value="">—</option>
                  {edges
                    .filter((e) => e.sourceId === selected.id)
                    .map((e) => (
                      <option key={e.id} value={e.id}>
                        {e.label || nodes.find((n) => n.id === e.targetId)?.title}
                      </option>
                    ))}
                </Select>
              </label>
            )}
            {selected.kind === 'group' && (
              <button
                className="secondary-button"
                onClick={() =>
                  apply(() => saveWorkflowNode(data, { ...selected, collapsed: !selected.collapsed }))
                }
              >
                {selected.collapsed ? '展开分组' : '折叠分组'}
              </button>
            )}
            {selected.kind === 'link' && selected.targetProjectId && (
              <button
                className="secondary-button"
                onClick={() => {
                  setProjectId(selected.targetProjectId!);
                  onProject?.(selected.targetProjectId!);
                }}
              >
                打开工作流
              </button>
            )}
            {selected.taskId && (
              <>
                <button
                  className="secondary-button"
                  onClick={() =>
                    onEdit?.({ kind: 'task', item: data.tasks.find((t) => t.id === selected.taskId) })
                  }
                >
                  编辑任务
                </button>
                <button className="secondary-button" onClick={() => calendar(selected)}>
                  <CalendarPlus size={16} />
                  日历时间块
                </button>
              </>
            )}
          </aside>
        )}
      </div>
      {nodes.length > 0 && (
        <svg
          className="workflow-minimap"
          aria-label="工作流缩略图"
          role="img"
          viewBox={`0 0 ${width} ${height}`}
          onClick={(e) => {
            const rect = e.currentTarget.getBoundingClientRect();
            viewport.current?.scrollTo({
              left: ((e.clientX - rect.left) / rect.width) * width * zoom - viewport.current.clientWidth / 2,
              top: ((e.clientY - rect.top) / rect.height) * height * zoom - viewport.current.clientHeight / 2,
            });
          }}
        >
          {visible.map((n) => (
            <rect
              key={n.id}
              x={n.x}
              y={n.y}
              width="200"
              height="86"
              className={selection.includes(n.id) ? 'selected' : ''}
            />
          ))}
        </svg>
      )}
      {(draft || edgeDraft) && (
        <dialog
          className="editor-dialog workflow-dialog"
          ref={modal}
          onCancel={(e) => {
            e.preventDefault();
            setDraft(null);
            setEdgeDraft(null);
          }}
        >
          <div className="dialog-header">
            <h2>{draft ? '节点' : '连线'}</h2>
            <button
              className="icon-button"
              aria-label="关闭"
              onClick={() => {
                setDraft(null);
                setEdgeDraft(null);
              }}
            >
              <X size={19} />
            </button>
          </div>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              if (draft) {
                const node = { ...draft };
                const createTask =
                  node.kind === 'task' && !node.taskId && data.preferences.workflowAutoTodo !== false;
                if (createTask) node.taskId = crypto.randomUUID();
                if (apply(() => saveWorkflowNode(data, node, createTask))) {
                  setDraft(null);
                  setSelection([node.id]);
                }
              }
              if (
                edgeDraft &&
                apply(() =>
                  refreshWorkflow({
                    ...data,
                    edges: workflowEdges(data).map((edge) => (edge.id === edgeDraft.id ? edgeDraft : edge)),
                  }),
                )
              )
                setEdgeDraft(null);
            }}
          >
            <div className="form-fields">
              {draft && (
                <>
                  <label>
                    名称
                    <input
                      aria-label="节点名称"
                      required
                      value={draft.title}
                      onChange={(e) => setDraft({ ...draft, title: e.target.value })}
                    />
                  </label>
                  <label>
                    类型
                    <Select
                      aria-label="节点类型"
                      value={draft.kind}
                      onChange={(e) =>
                        setDraft({
                          ...draft,
                          kind: e.target.value as NodeKind,
                          taskId: null,
                          selectedBranchEdgeId: null,
                        })
                      }
                    >
                      {Object.entries(kinds).map(([value, title]) => (
                        <option key={value} value={value}>
                          {title}
                        </option>
                      ))}
                    </Select>
                  </label>
                  <label>
                    描述
                    <textarea
                      value={String(draft.description ?? '')}
                      onChange={(e) => setDraft({ ...draft, description: e.target.value })}
                    />
                  </label>
                  <label>
                    前置条件
                    <Select
                      value={draft.anyPredecessor ? 'or' : 'and'}
                      onChange={(e) => setDraft({ ...draft, anyPredecessor: e.target.value === 'or' })}
                    >
                      <option value="and">AND</option>
                      <option value="or">OR</option>
                    </Select>
                  </label>
                  <label>
                    分组
                    <Select
                      value={draft.groupId ?? ''}
                      onChange={(e) => setDraft({ ...draft, groupId: e.target.value || null })}
                    >
                      <option value="">—</option>
                      {nodes
                        .filter((n) => n.kind === 'group' && n.id !== draft.id)
                        .map((n) => (
                          <option key={n.id} value={n.id}>
                            {n.title}
                          </option>
                        ))}
                    </Select>
                  </label>
                  {draft.kind === 'task' && (
                    <label>
                      关联任务
                      <Select
                        value={draft.taskId ?? ''}
                        onChange={(e) => setDraft({ ...draft, taskId: e.target.value || null })}
                      >
                        <option value="">
                          {data.preferences.workflowAutoTodo === false ? '—' : '新建任务'}
                        </option>
                        {data.tasks
                          .filter((t) => !t.deletedAt && !t.archived)
                          .map((t) => (
                            <option key={t.id} value={t.id}>
                              {t.title}
                            </option>
                          ))}
                      </Select>
                    </label>
                  )}
                  {draft.kind === 'link' && (
                    <label>
                      目标项目
                      <Select
                        value={draft.targetProjectId ?? ''}
                        onChange={(e) => setDraft({ ...draft, targetProjectId: e.target.value || null })}
                      >
                        <option value="">—</option>
                        {projects.map((p) => (
                          <option key={p.id} value={p.id}>
                            {p.title}
                          </option>
                        ))}
                      </Select>
                    </label>
                  )}
                </>
              )}
              {edgeDraft && (
                <>
                  <label>
                    名称
                    <input
                      value={edgeDraft.label}
                      onChange={(e) => setEdgeDraft({ ...edgeDraft, label: e.target.value })}
                    />
                  </label>
                  <label>
                    延迟（分钟）
                    <input
                      required
                      type="number"
                      min="0"
                      step="1"
                      value={edgeDraft.delayMinutes}
                      onChange={(e) => setEdgeDraft({ ...edgeDraft, delayMinutes: Number(e.target.value) })}
                    />
                  </label>
                  <label>
                    可用时间
                    <input
                      type="datetime-local"
                      value={edgeDraft.availableAt ? dateTimeInput(edgeDraft.availableAt) : ''}
                      onChange={(e) =>
                        setEdgeDraft({
                          ...edgeDraft,
                          availableAt: e.target.value ? new Date(e.target.value).toISOString() : null,
                        })
                      }
                    />
                  </label>
                  <label>
                    <input
                      type="checkbox"
                      checked={edgeDraft.active}
                      onChange={(e) => setEdgeDraft({ ...edgeDraft, active: e.target.checked })}
                    />
                    启用
                  </label>
                </>
              )}
              {error && (
                <p className="form-error" role="alert">
                  {error}
                </p>
              )}
            </div>
            <div className="dialog-actions">
              <button
                className="secondary-button"
                type="button"
                onClick={() => {
                  setDraft(null);
                  setEdgeDraft(null);
                }}
              >
                取消
              </button>
              <button className="primary-button" type="submit">
                保存
              </button>
            </div>
          </form>
        </dialog>
      )}
    </section>
  );
}
