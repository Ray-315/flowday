import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/store.dart';
import 'editors.dart';
import 'theme.dart';

class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.store,
    required this.task,
    this.compact = false,
    this.selected,
    this.onSelected,
  });
  final FlowStore store;
  final Task task;
  final bool compact;
  final bool? selected;
  final ValueChanged<bool>? onSelected;
  @override
  Widget build(BuildContext context) {
    final project = store.project(task.projectId);
    final done = task.status == TaskStatus.done;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: InkWell(
        onTap: () => openEditor(context, TaskEditor(store: store, task: task)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Checkbox(
                value: selected ?? done,
                onChanged: (v) => onSelected != null
                    ? onSelected!(v!)
                    : store.setTaskStatus(
                        task.id,
                        v! ? TaskStatus.done : TaskStatus.todo,
                      ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (task.deadline != null)
                          Text(
                            '${shortDate(task.deadline!)} ${clockText(task.deadline!)}',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  !done &&
                                      task.deadline!.isBefore(DateTime.now())
                                  ? palette[3]
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        Tag(
                          priorityLabels[task.priority.index],
                          color: priorityColor(task.priority),
                        ),
                        Text(
                          '${task.estimateMinutes / 60}h',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        if (project != null)
                          Tag(project.title, color: Color(project.color)),
                      ],
                    ),
                  ],
                ),
              ),
              if (!compact)
                IconButton(
                  onPressed: () => openEditor(
                    context,
                    EventEditor(store: store, task: task),
                  ),
                  icon: Icon(
                    Icons.calendar_month_outlined,
                    size: 19,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 18,
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class TodoPage extends StatefulWidget {
  const TodoPage({
    super.key,
    required this.store,
    this.projectId,
    this.onSchedule,
    this.attachmentBuilder,
  });
  final FlowStore store;
  final String? projectId;
  final ValueChanged<List<String>>? onSchedule;
  final Widget Function(Task)? attachmentBuilder;
  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  String filter = '全部';
  String? project, priority, tag, selected;
  final collapsed = <String>{};
  final selectedIds = <String>{};
  bool batch = false, archiveView = false;
  void toggleSelected(String id, bool value) =>
      setState(() => value ? selectedIds.add(id) : selectedIds.remove(id));
  List<Task> get batchTasks => widget.store.data.tasks
      .where((t) => selectedIds.contains(t.id) && t.deletedAt == null)
      .toList();
  Future<bool> previewBatch(
    String action,
    String Function(Task) difference,
  ) async {
    final tasks = batchTasks;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('$action · ${tasks.length} 个任务'),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: tasks
                    .map(
                      (t) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.title),
                        subtitle: Text(difference(t)),
                      ),
                    )
                    .toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> moveBatch(String value) async {
    final projectId = value.isEmpty ? null : value;
    final destination = widget.store.project(projectId)?.title ?? '无项目';
    if (!await previewBatch(
      '移动项目',
      (t) =>
          '${widget.store.project(t.projectId)?.title ?? '无项目'} → $destination',
    )) {
      return;
    }
    for (final task in batchTasks) {
      widget.store.updateTask(
        Task.fromJson(task.toJson())..projectId = projectId,
      );
    }
    if (mounted) setState(selectedIds.clear);
  }

  Future<void> tagsBatch() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => const _BatchTagsDialog(),
    );
    if (value == null || !mounted) return;
    final tags = value
        .split(RegExp('[,，]'))
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toSet()
        .toList();
    if (!await previewBatch(
      '修改标签',
      (t) =>
          '${t.tags.isEmpty ? '无标签' : t.tags.join('、')} → ${tags.isEmpty ? '无标签' : tags.join('、')}',
    )) {
      return;
    }
    for (final task in batchTasks) {
      widget.store.updateTask(
        Task.fromJson(task.toJson())..tags = List.from(tags),
      );
    }
    if (mounted) setState(selectedIds.clear);
  }

  Future<void> archiveBatch() async {
    if (!await previewBatch(
      archiveView ? '取消归档' : '归档',
      (_) => archiveView ? '已归档 → 待办列表' : '待办列表 → 已归档',
    )) {
      return;
    }
    for (final task in batchTasks) {
      widget.store.updateTask(
        Task.fromJson(task.toJson())..archived = !archiveView,
      );
    }
    if (mounted) setState(selectedIds.clear);
  }

  Future<void> deleteBatch() async {
    if (!await previewBatch('移入回收站', (_) => '待办列表 → 回收站')) return;
    for (final task in batchTasks) {
      widget.store.deleteTask(task.id);
    }
    if (mounted) setState(selectedIds.clear);
  }

  String group(Task t) {
    final now = DateTime.now();
    if (t.status == TaskStatus.done) return '已完成';
    if (t.deadline != null && t.deadline!.isBefore(dayOnly(now))) return '逾期';
    if (t.deadline != null && sameDay(t.deadline!, now)) return '今天';
    if (t.deadline != null &&
        t.deadline!.isBefore(
          dayOnly(now).add(Duration(days: 8 - now.weekday)),
        )) {
      return '本周';
    }
    return '待办';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final items =
          (archiveView
                  ? widget.store.data.tasks.where(
                      (t) => t.archived && t.deletedAt == null,
                    )
                  : widget.store.tasks)
              .where(
                (t) =>
                    t.parentId == null &&
                    ((widget.projectId ?? project) == null ||
                        t.projectId == (widget.projectId ?? project)) &&
                    (priority == null ||
                        priorityLabels[t.priority.index] == priority) &&
                    (tag == null || t.tags.contains(tag)) &&
                    (filter == '全部' || group(t) == filter),
              )
              .toList()
            ..sort((a, b) => b.priority.index.compareTo(a.priority.index));
      final current =
          items.where((t) => t.id == selected).firstOrNull ?? items.firstOrNull;
      final wide = MediaQuery.sizeOf(context).width >= 1150;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        archiveView = !archiveView;
                        selectedIds.clear();
                      }),
                      child: Text(archiveView ? '待办列表' : '已归档'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        batch = !batch;
                        selectedIds.clear();
                      }),
                      child: Text(batch ? '结束选择' : '批量选择'),
                    ),
                    FilledButton.icon(
                      onPressed: () => openEditor(
                        context,
                        TaskEditor(
                          store: widget.store,
                          projectId: widget.projectId,
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('新建任务'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (batch)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Checkbox(
                          key: const Key('todo-select-all'),
                          value:
                              items.isNotEmpty &&
                              items.every((t) => selectedIds.contains(t.id)),
                          onChanged: (v) => setState(() {
                            if (v!) {
                              selectedIds.addAll(items.map((t) => t.id));
                            } else {
                              selectedIds.removeAll(items.map((t) => t.id));
                            }
                          }),
                        ),
                        Text('已选 ${selectedIds.length} 项'),
                        PopupMenuButton<String>(
                          enabled: selectedIds.isNotEmpty,
                          onSelected: moveBatch,
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: '', child: Text('无项目')),
                            ...widget.store.projects
                                .where((p) => !p.archived)
                                .map(
                                  (p) => PopupMenuItem(
                                    value: p.id,
                                    child: Text(p.title),
                                  ),
                                ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('移动项目'),
                          ),
                        ),
                        TextButton(
                          onPressed: selectedIds.isEmpty ? null : tagsBatch,
                          child: const Text('修改标签'),
                        ),
                        TextButton(
                          onPressed: selectedIds.isEmpty ? null : archiveBatch,
                          child: Text(archiveView ? '取消归档' : '归档'),
                        ),
                        TextButton(
                          onPressed: selectedIds.isEmpty ? null : deleteBatch,
                          child: const Text('移入回收站'),
                        ),
                        TextButton(
                          onPressed:
                              selectedIds.isEmpty || widget.onSchedule == null
                              ? null
                              : () =>
                                    widget.onSchedule!(List.from(selectedIds)),
                          child: const Text('安排本周'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Panel(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ChoiceBar(
                              labels: const ['全部', '今天', '本周', '逾期', '已完成'],
                              selected: filter,
                              onSelected: (s) => setState(() => filter = s),
                            ),
                            PopupMenuButton<String>(
                              tooltip: '优先级',
                              onSelected: (s) => setState(
                                () => priority = s.isEmpty ? null : s,
                              ),
                              itemBuilder: (_) => ['', ...priorityLabels]
                                  .map(
                                    (s) => PopupMenuItem(
                                      value: s,
                                      child: Text(s.isEmpty ? '全部优先级' : s),
                                    ),
                                  )
                                  .toList(),
                              child: _filter(priority ?? '优先级'),
                            ),
                            if (widget.projectId == null)
                              PopupMenuButton<String>(
                                tooltip: '项目',
                                onSelected: (s) => setState(
                                  () => project = s.isEmpty ? null : s,
                                ),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: '',
                                    child: Text('全部项目'),
                                  ),
                                  ...widget.store.projects.map(
                                    (p) => PopupMenuItem(
                                      value: p.id,
                                      child: Text(p.title),
                                    ),
                                  ),
                                ],
                                child: _filter(
                                  widget.store.project(project)?.title ?? '项目',
                                ),
                              ),
                            PopupMenuButton<String>(
                              tooltip: '标签',
                              onSelected: (s) =>
                                  setState(() => tag = s.isEmpty ? null : s),
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: '',
                                  child: Text('全部标签'),
                                ),
                                ...widget.store.tasks
                                    .expand((t) => t.tags)
                                    .toSet()
                                    .map(
                                      (s) => PopupMenuItem(
                                        value: s,
                                        child: Text(s),
                                      ),
                                    ),
                              ],
                              child: _filter(tag ?? '标签'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (wide) _tableHeader(),
                        Expanded(
                          child: ListView(
                            children: [
                              for (final name in [
                                '今天',
                                '本周',
                                '逾期',
                                '待办',
                                '已完成',
                              ])
                                if (items.any((t) => group(t) == name)) ...[
                                  InkWell(
                                    onTap: () => setState(
                                      () => collapsed.contains(name)
                                          ? collapsed.remove(name)
                                          : collapsed.add(name),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            collapsed.contains(name)
                                                ? Icons.chevron_right
                                                : Icons.expand_more,
                                            size: 18,
                                            color: name == '逾期'
                                                ? palette[3]
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            '${items.where((t) => group(t) == name).length}',
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (!collapsed.contains(name))
                                    ...items
                                        .where((t) => group(t) == name)
                                        .map(
                                          (t) => wide
                                              ? _tableRow(
                                                  t,
                                                  current?.id == t.id,
                                                )
                                              : TaskRow(
                                                  store: widget.store,
                                                  task: t,
                                                  selected: batch
                                                      ? selectedIds.contains(
                                                          t.id,
                                                        )
                                                      : null,
                                                  onSelected: batch
                                                      ? (v) => toggleSelected(
                                                          t.id,
                                                          v,
                                                        )
                                                      : null,
                                                ),
                                        ),
                                ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (wide && current != null) ...[
            const SizedBox(width: 16),
            SizedBox(
              width: 310,
              child: Panel(
                key: const Key('todo-detail'),
                child: _detail(current),
              ),
            ),
          ],
        ],
      );
    },
  );
  Widget _filter(String title) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(fontSize: 12)),
        const Icon(Icons.expand_more, size: 16),
      ],
    ),
  );
  Widget _cell(Widget child, int flex) => Expanded(
    flex: flex,
    child: Padding(padding: const EdgeInsets.only(right: 8), child: child),
  );
  Widget _tableHeader() => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Row(
      children: [
        const SizedBox(width: 38),
        for (final c in [
          ('任务', 30),
          ('优先级', 12),
          ('截止日期', 18),
          ('预计耗时', 14),
          ('标签', 13),
          ('所属项目', 20),
        ])
          _cell(
            Text(
              c.$1,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            c.$2,
          ),
      ],
    ),
  );
  Widget _tableRow(Task t, bool active) => InkWell(
    key: Key('todo-row-${t.id}'),
    onTap: () => setState(() => selected = t.id),
    child: Container(
      height: 53,
      decoration: BoxDecoration(
        color: active
            ? Theme.of(context).colorScheme.surfaceContainerLow
            : null,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Checkbox(
              value: batch
                  ? selectedIds.contains(t.id)
                  : t.status == TaskStatus.done,
              onChanged: (v) => batch
                  ? toggleSelected(t.id, v!)
                  : widget.store.setTaskStatus(
                      t.id,
                      v! ? TaskStatus.done : TaskStatus.todo,
                    ),
            ),
          ),
          _cell(
            Text(
              t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                decoration: t.status == TaskStatus.done
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
            30,
          ),
          _cell(
            Align(
              alignment: Alignment.centerLeft,
              child: Tag(
                priorityLabels[t.priority.index],
                color: priorityColor(t.priority),
              ),
            ),
            12,
          ),
          _cell(
            Text(
              t.deadline == null
                  ? '—'
                  : sameDay(t.deadline!, DateTime.now())
                  ? '今天 ${clockText(t.deadline!)}'
                  : shortDate(t.deadline!),
              style: TextStyle(
                fontSize: 12,
                color: group(t) == '逾期'
                    ? palette[3]
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            18,
          ),
          _cell(
            Text(
              '${t.estimateMinutes / 60}h',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            14,
          ),
          _cell(
            Text(
              t.tags.join('、'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 12,
              ),
            ),
            13,
          ),
          _cell(
            Text(
              widget.store.project(t.projectId)?.title ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            20,
          ),
        ],
      ),
    ),
  );
  Widget _detail(Task t) {
    final children = widget.store.tasks
        .where((s) => s.parentId == t.id)
        .toList();
    final done = children.where((s) => s.status == TaskStatus.done).length;
    final events = widget.store.events.where((e) => e.taskId == t.id).toList();
    return ListView(
      children: [
        Row(
          children: [
            Checkbox(
              value: t.status == TaskStatus.done,
              onChanged: (v) => widget.store.setTaskStatus(
                t.id,
                v! ? TaskStatus.done : TaskStatus.todo,
              ),
            ),
            Expanded(
              child: Text(
                t.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: () =>
                  openEditor(context, TaskEditor(store: widget.store, task: t)),
              icon: Icon(
                Icons.more_horiz,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            Tag(
              priorityLabels[t.priority.index],
              color: priorityColor(t.priority),
            ),
            if (t.deadline != null)
              Text(
                '${shortDate(t.deadline!)} ${clockText(t.deadline!)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            Text(
              '${t.estimateMinutes / 60}h',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: t.tags.map((s) => Tag(s)).toList(),
        ),
        if (t.projectId != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text('▱  ${widget.store.project(t.projectId)?.title ?? ''}'),
          ),
        if (t.description.isNotEmpty)
          Text(
            t.description,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.8,
            ),
          ),
        const SizedBox(height: 26),
        if (widget.attachmentBuilder != null) widget.attachmentBuilder!(t),
        Text(
          '子任务  $done/${children.length}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: children.isEmpty ? 0 : done / children.length,
          color: palette[2],
          backgroundColor: Theme.of(context).dividerColor,
          borderRadius: BorderRadius.circular(4),
          minHeight: 6,
        ),
        const SizedBox(height: 12),
        ...children.map(
          (s) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(s.title, style: const TextStyle(fontSize: 13)),
            value: s.status == TaskStatus.done,
            onChanged: (v) => widget.store.setTaskStatus(
              s.id,
              v! ? TaskStatus.done : TaskStatus.todo,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () => openEditor(
            context,
            TaskEditor(
              store: widget.store,
              parentId: t.id,
              projectId: t.projectId,
            ),
          ),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('添加子任务'),
        ),
        const SizedBox(height: 22),
        Text(
          '时间安排  ${events.length}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...events.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => openEditor(
                context,
                EventEditor(store: widget.store, event: e),
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  border: Border(
                    left: BorderSide(color: Color(e.color), width: 3),
                  ),
                ),
                child: Text(
                  '${shortDate(e.start)} ${clockText(e.start)} – ${clockText(e.end)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () =>
              openEditor(context, EventEditor(store: widget.store, task: t)),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('添加时间块'),
        ),
      ],
    );
  }
}

class _BatchTagsDialog extends StatefulWidget {
  const _BatchTagsDialog();
  @override
  State<_BatchTagsDialog> createState() => _BatchTagsDialogState();
}

class _BatchTagsDialogState extends State<_BatchTagsDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('修改标签'),
    content: TextField(
      controller: controller,
      decoration: const InputDecoration(labelText: '标签（逗号分隔）'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('下一步'),
      ),
    ],
  );
}

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({
    super.key,
    required this.store,
    required this.openWorkflow,
    this.attachmentBuilder,
  });
  final FlowStore store;
  final ValueChanged<String> openWorkflow;
  final Widget Function(Project)? attachmentBuilder;
  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  String? parent, selected;
  bool archived = false;
  @override
  Widget build(BuildContext context) {
    final projects = widget.store.projects
        .where((p) => p.parentId == parent && p.archived == archived)
        .toList();
    final current =
        projects.where((p) => p.id == selected).firstOrNull ??
        projects.firstOrNull;
    final width = MediaQuery.sizeOf(context).width;
    final folders = projects
        .where(
          (p) => widget.store.projects.any(
            (child) => child.parentId == p.id && child.archived == archived,
          ),
        )
        .toList();
    final grid = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          children: [
            ChoiceBar(
              labels: const ['全部', '已归档'],
              selected: archived ? '已归档' : '全部',
              onSelected: (v) => setState(() => archived = v == '已归档'),
            ),
            FilledButton.icon(
              onPressed: () =>
                  editProject(context, widget.store, parentId: parent),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建项目'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: () => setState(() => parent = null),
              child: const Text('全部项目'),
            ),
            if (parent != null) ...[
              const Icon(Icons.chevron_right, size: 18),
              Text(widget.store.project(parent)?.title ?? ''),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (folders.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('文件夹', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: folders.length,
              separatorBuilder: (_, i) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final p = folders[i];
                return SizedBox(
                  width: 180,
                  child: InkWell(
                    onTap: () => setState(() => parent = p.id),
                    child: Panel(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder_rounded,
                            color: Color(p.color),
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  p.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${widget.store.projects.where((c) => c.parentId == p.id && c.archived == archived).length} 个项目',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('项目', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: c.maxWidth > 750
                    ? 3
                    : c.maxWidth > 560
                    ? 2
                    : 1,
                mainAxisExtent: 190,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
              ),
              itemCount: projects.length + 1,
              itemBuilder: (context, i) {
                if (i == projects.length) {
                  return OutlinedButton.icon(
                    onPressed: () =>
                        editProject(context, widget.store, parentId: parent),
                    icon: const Icon(Icons.add),
                    label: const Text('新建项目'),
                  );
                }
                final p = projects[i];
                final progress = widget.store.progress(p.id);
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() => selected = p.id);
                    if (width < 1150) openEditor(context, projectDetail(p));
                  },
                  child: Panel(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.circle, size: 20, color: Color(p.color)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                p.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  editProject(
                                    context,
                                    widget.store,
                                    project: p,
                                  );
                                }
                                if (v == 'children') {
                                  setState(() => parent = p.id);
                                }
                                if (v == 'archive') {
                                  p.archived = !p.archived;
                                  widget.store.changed();
                                }
                                if (v == 'delete' &&
                                    await confirm(
                                      context,
                                      '移入回收站',
                                      '确认将「${p.title}」移入回收站？',
                                    )) {
                                  widget.store.deleteProject(p.id);
                                  if (mounted) setState(() => selected = null);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('编辑'),
                                ),
                                const PopupMenuItem(
                                  value: 'children',
                                  child: Text('打开子项目'),
                                ),
                                PopupMenuItem(
                                  value: 'archive',
                                  child: Text(p.archived ? '取消归档' : '归档'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('移入回收站'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Text(
                            p.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              height: 1.6,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(4),
                                color: palette[2],
                                backgroundColor: Theme.of(context).dividerColor,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              '${(progress * 100).round()}%',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Icon(
                              Icons.check_box_outlined,
                              size: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${widget.store.tasks.where((t) => t.projectId == p.id && t.status == TaskStatus.done).length} / ${widget.store.tasks.where((t) => t.projectId == p.id && t.status != TaskStatus.cancelled).length}',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => setState(() => parent = p.id),
                              child: const Text('子项目'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: grid),
        if (width >= 1150 && current != null) ...[
          const SizedBox(width: 20),
          SizedBox(width: 310, child: Panel(child: projectDetail(current))),
        ],
      ],
    );
  }

  Widget projectDetail(Project p) => ListView(
    shrinkWrap: true,
    padding: const EdgeInsets.all(8),
    children: [
      SectionTitle(
        p.title,
        action: IconButton(
          onPressed: () => editProject(context, widget.store, project: p),
          icon: const Icon(Icons.edit_outlined, size: 19),
        ),
      ),
      Text(
        p.description,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.8,
        ),
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          Tag(
            p.archived
                ? '已归档'
                : widget.store.progress(p.id) == 1
                ? '已完成'
                : '进行中',
            color: Color(p.color),
          ),
          Text(
            '${(widget.store.progress(p.id) * 100).round()}%',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      LinearProgressIndicator(
        value: widget.store.progress(p.id),
        color: palette[2],
        backgroundColor: Theme.of(context).dividerColor,
        minHeight: 7,
        borderRadius: BorderRadius.circular(5),
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          Icon(
            Icons.check_box_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            '${widget.store.data.tasks.where((t) => t.projectId == p.id && t.deletedAt == null && t.status == TaskStatus.done).length} / ${widget.store.data.tasks.where((t) => t.projectId == p.id && t.deletedAt == null && t.status != TaskStatus.cancelled).length}',
          ),
          if (p.deadline != null) ...[
            const Spacer(),
            Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              shortDate(p.deadline!),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: () => widget.openWorkflow(p.id),
        icon: const Icon(Icons.account_tree_outlined, size: 18),
        label: const Text('打开工作流'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => openEditor(
          context,
          TaskEditor(store: widget.store, projectId: p.id),
        ),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('添加任务'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => editProject(context, widget.store, parentId: p.id),
        icon: const Icon(Icons.create_new_folder_outlined, size: 18),
        label: const Text('新建子项目'),
      ),
      const SizedBox(height: 24),
      if (widget.attachmentBuilder != null) widget.attachmentBuilder!(p),
      ...widget.store.tasks
          .where((t) => t.projectId == p.id)
          .map((t) => TaskRow(store: widget.store, task: t, compact: true)),
    ],
  );
}
