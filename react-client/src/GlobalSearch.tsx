import type { Editing } from './App';
import type { Workspace } from './workspace';
import { activeTasks, activeEvents, isProjectHidden } from './domain';
export type SearchResult = {
  kind: 'task' | 'event' | 'project' | 'node' | 'attachment';
  id: string;
  title: string;
  ownerType?: string;
  ownerId?: string;
};
export function globalSearchResults(
  data: Workspace,
  query: string,
  cloudAttachments: Record<string, unknown>[] = [],
): SearchResult[] {
  const term = query.trim().toLocaleLowerCase();
  if (!term) return [];
  const results: SearchResult[] = [];
  const owners = new Map<string, string>();
  const matches = (...values: unknown[]) => values.join(' ').toLocaleLowerCase().includes(term);
  for (const [kind, values] of [
    ['task', activeTasks(data)],
    ['event', activeEvents(data)],
    ['project', data.projects.filter((project) => !isProjectHidden(data, project.id))],
  ] as const) {
    for (const item of values.filter((item) => !item.deletedAt && !item.archived)) {
      owners.set(item.id, kind);
      if (matches(item.title, item.description, item.notes, (item.tags as string[] | undefined)?.join(' ')))
        results.push({ kind, id: item.id, title: item.title });
      for (const attachment of (item.attachments as Record<string, unknown>[] | undefined) ?? [])
        if (matches(attachment.title, attachment.content))
          results.push({
            kind: 'attachment',
            id: String(attachment.id),
            title: String(attachment.title),
            ownerId: item.id,
            ownerType: kind,
          });
    }
  }
  for (const node of data.nodes as Record<string, unknown>[])
    if (owners.get(String(node.projectId)) === 'project' && matches(node.title, node.description))
      results.push({
        kind: 'node',
        id: String(node.id),
        title: String(node.title),
        ownerId: String(node.projectId),
      });
  for (const attachment of cloudAttachments)
    if (
      !attachment.deletedAt &&
      owners.has(String(attachment.ownerId)) &&
      matches(attachment.name, attachment.markdown, attachment.url) &&
      !results.some((result) => result.kind === 'attachment' && result.id === attachment.id)
    )
      results.push({
        kind: 'attachment',
        id: String(attachment.id),
        title: String(attachment.name),
        ownerType: String(attachment.ownerType),
        ownerId: String(attachment.ownerId),
      });
  return results.slice(0, 100);
}
export function GlobalSearch({
  data,
  query,
  onEdit,
  onProject,
  onNode,
  cloudAttachments = [],
}: {
  data: Workspace;
  query: string;
  onEdit: (editing: Editing) => void;
  onProject?: (id: string) => void;
  onNode?: (id: string, projectId: string) => void;
  cloudAttachments?: Record<string, unknown>[];
}) {
  const labels = { task: '任务', event: '日程', project: '项目', node: '节点', attachment: '附件' };
  function open(result: SearchResult) {
    const kind = result.kind === 'attachment' ? result.ownerType : result.kind;
    const id = result.kind === 'attachment' ? result.ownerId : result.id;
    if (kind === 'node') {
      onNode?.(result.id, result.ownerId!);
      return;
    }
    if (kind === 'project' && onProject) {
      onProject(id!);
      return;
    }
    if (kind === 'task') {
      const item = data.tasks.find((item) => item.id === id);
      if (item) onEdit({ kind, item });
    }
    if (kind === 'event') {
      const item = data.events.find((item) => item.id === id);
      if (item) onEdit({ kind, item });
    }
    if (kind === 'project') {
      const item = data.projects.find((item) => item.id === id);
      if (item) onEdit({ kind, item });
    }
  }
  return (
    <section className="panel editor-fields">
      <div className="section-heading">
        <h2>搜索</h2>
      </div>
      {globalSearchResults(data, query, cloudAttachments).map((result) => (
        <button className="task-body" key={`${result.kind}-${result.id}`} onClick={() => open(result)}>
          {result.title} · {labels[result.kind]}
        </button>
      ))}
    </section>
  );
}
