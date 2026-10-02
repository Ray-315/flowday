import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/store.dart';
import 'theme.dart';
import 'recurrence_form.dart';
import '../data/sync_controller.dart';
import 'event_sync_status.dart';
import 'event_reminder_rules.dart';
import 'sync_scope.dart';
import 'strong_reminder_options.dart';

RepeatRule? _defaultRepeat(FlowStore store) {
  final frequency = RepeatFrequency.values
      .where((x) => x.name == store.data.preferences['defaultRepeat'])
      .firstOrNull;
  return frequency == null ? null : RepeatRule(frequency: frequency);
}

class TaskEditor extends StatefulWidget {
  const TaskEditor({
    super.key,
    required this.store,
    this.task,
    this.projectId,
    this.parentId,
    this.initialTitle,
    this.sync,
  });
  final FlowStore store;
  final Task? task;
  final String? projectId, parentId, initialTitle;
  final SyncController? sync;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title, description, estimate, actual, tags;
  late String? projectId;
  late TaskStatus status;
  bool statusEdited = false;
  late Priority priority;
  late Difficulty difficulty;
  DateTime? plannedStart;
  RepeatRule? repeatRule;
  bool actualEdited = false;
  bool? strongReminder;
  int? reminderInterval, maxReminders;
  bool strongEdited = false, intervalEdited = false, maximumEdited = false;
  DateTime? deadline;
  bool splittable = true;
  String? error;
  @override
  void initState() {
    super.initState();
    final t = widget.task;
    strongReminder = t?.strongReminder;
    reminderInterval = t?.reminderInterval;
    maxReminders = t?.maxReminders;
    title = TextEditingController(text: t?.title ?? widget.initialTitle ?? '');
    description = TextEditingController(text: t?.description ?? '');
    estimate = TextEditingController(
      text:
          '${t?.estimateMinutes ?? widget.store.preferenceMinutes('defaultEstimateMinutes')}',
    );
    tags = TextEditingController(text: t?.tags.join('，') ?? '');
    actual = TextEditingController(text: '${t?.actualMinutes ?? 0}');
    difficulty =
        t?.difficulty ??
        Difficulty.values
            .where(
              (x) =>
                  x.name ==
                  (widget.store.data.preferences['defaultDifficulty'] ??
                      widget.store.data.preferences['defaultTaskDifficulty']),
            )
            .firstOrNull ??
        Difficulty.normal;
    plannedStart = t?.plannedStart;
    repeatRule = t?.repeatRule == null
        ? (t == null ? _defaultRepeat(widget.store) : null)
        : RepeatRule.fromJson(t!.repeatRule!.toJson());
    projectId = t?.projectId ?? widget.projectId;
    status = t?.status ?? TaskStatus.todo;
    priority =
        t?.priority ?? widget.store.preferencePriority('defaultTaskPriority');
    deadline = t?.deadline;
    splittable = t?.splittable ?? true;
  }

  @override
  void dispose() {
    for (final c in [title, description, estimate, actual, tags]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final scope = widget.task?.seriesId == null
        ? RepeatScope.thisOnly
        : await chooseRepeatScope(context, '修改重复任务');
    if (scope == null || !mounted) return;
    try {
      final latest = widget.store.data.tasks
          .where((task) => task.id == widget.task?.id)
          .firstOrNull;
      final task = latest != null
          ? Task.fromJson(latest.toJson())
          : Task(
              id: widget.task?.id ?? widget.store.newId(),
              title: title.text.trim(),
              projectId: widget.store.project(projectId)?.id,
              parentId: latest != null
                  ? latest.parentId
                  : (widget.task?.parentId ?? widget.parentId),
              description: description.text,
              status: statusEdited ? status : (latest?.status ?? status),
              priority: priority,
              estimateMinutes: int.parse(estimate.text),
              actualMinutes: 0,
              deadline: deadline,
              completedAt: latest?.completedAt,
              deletedAt: latest?.deletedAt,
              splittable: splittable,
              tags: tags.text
                  .split(RegExp('[,，]'))
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList(),
            );
      task.title = title.text.trim();
      task.projectId = widget.store.project(projectId)?.id;
      task.description = description.text;
      task.status = statusEdited ? status : (latest?.status ?? status);
      task.priority = priority;
      task.difficulty = difficulty;
      task.estimateMinutes = int.parse(estimate.text);
      if (actualEdited || latest == null) {
        task.actualMinutes = int.parse(actual.text);
      }
      task.plannedStart = plannedStart;
      task.deadline = deadline;
      task.repeatRule = repeatRule;
      if (strongEdited) task.strongReminder = strongReminder;
      if (intervalEdited) task.reminderInterval = reminderInterval;
      if (maximumEdited) task.maxReminders = maxReminders;
      task.splittable = splittable;
      task.tags = tags.text
          .split(RegExp('[,，]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (widget.task == null) {
        widget.store.addTask(task);
      } else {
        widget.store.updateTask(task, scope: scope);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      editorHeader(context, widget.task == null ? '新建任务' : '任务详情'),
      Expanded(
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                key: const Key('task-title'),
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(labelText: '任务名称'),
                validator: requiredTitle,
              ),
              const SizedBox(height: 20),
              projectField(
                widget.store,
                projectId,
                (v) => setState(() => projectId = v),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FlowSelect<TaskStatus>(
                      initialValue: status,
                      decoration: const InputDecoration(labelText: '状态'),
                      items: TaskStatus.values
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(taskLabels[v.index]),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        status = v!;
                        statusEdited = true;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FlowSelect<Priority>(
                      initialValue: priority,
                      decoration: const InputDecoration(labelText: '优先级'),
                      items: Priority.values
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(priorityLabels[v.index]),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => priority = v!,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FlowSelect<Difficulty>(
                key: const Key('task-difficulty'),
                initialValue: difficulty,
                decoration: const InputDecoration(labelText: '难度'),
                items: Difficulty.values
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(const ['低', '中', '高'][v.index]),
                      ),
                    )
                    .toList(),
                onChanged: (v) => difficulty = v!,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await pickDateTime(
                    context,
                    plannedStart ?? DateTime.now(),
                  );
                  if (date != null) setState(() => plannedStart = date);
                },
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(
                  plannedStart == null
                      ? '设置计划开始'
                      : '计划开始 ${dateText(plannedStart!)} ${clockText(plannedStart!)}',
                ),
              ),
              if (plannedStart != null)
                TextButton(
                  onPressed: () => setState(() => plannedStart = null),
                  child: const Text('清除计划开始'),
                ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await pickDateTime(
                    context,
                    deadline ?? DateTime.now(),
                  );
                  if (date != null) setState(() => deadline = date);
                },
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  deadline == null
                      ? '设置截止时间'
                      : '${dateText(deadline!)} ${clockText(deadline!)}',
                ),
              ),
              if (deadline != null)
                TextButton(
                  onPressed: () => setState(() => deadline = null),
                  child: const Text('清除截止时间'),
                ),
              const SizedBox(height: 20),
              TextFormField(
                controller: estimate,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '预计耗时（分钟）'),
                validator: (v) =>
                    int.tryParse(v ?? '') == null || int.parse(v!) < 0
                    ? '请输入非负整数'
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('允许拆分时间块'),
                value: splittable,
                onChanged: (v) => setState(() => splittable = v),
              ),
              TextFormField(
                key: const Key('task-actual'),
                controller: actual,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '实际耗时（分钟）'),
                validator: (v) =>
                    int.tryParse(v ?? '') == null || int.parse(v!) < 0
                    ? '请输入非负整数'
                    : null,
                onChanged: (_) => actualEdited = true,
              ),
              const SizedBox(height: 20),
              StrongReminderOptions(
                strong: strongReminder,
                interval: reminderInterval,
                maximum: maxReminders,
                onStrong: (v) {
                  strongReminder = v;
                  strongEdited = true;
                },
                onInterval: (v) {
                  reminderInterval = v;
                  intervalEdited = true;
                },
                onMaximum: (v) {
                  maxReminders = v;
                  maximumEdited = true;
                },
              ),
              const SizedBox(height: 16),
              RecurrenceForm(
                initialRule: repeatRule,
                onChanged: (v) => repeatRule = v,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: tags,
                decoration: const InputDecoration(labelText: '标签（逗号分隔）'),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: description,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(labelText: '备注'),
              ),
              if (widget.task != null) ...[
                const SizedBox(height: 24),
                SectionTitle(
                  '子任务',
                  action: TextButton(
                    onPressed: () => openEditor(
                      context,
                      TaskEditor(
                        store: widget.store,
                        parentId: widget.task!.id,
                        projectId: projectId,
                      ),
                    ),
                    child: const Text('添加'),
                  ),
                ),
                ListenableBuilder(
                  listenable: widget.store,
                  builder: (context, _) => Column(
                    children: widget.store.tasks
                        .where((t) => t.parentId == widget.task!.id)
                        .map(
                          (t) => CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(t.title),
                            value: t.status == TaskStatus.done,
                            onChanged: (v) => widget.store.setTaskStatus(
                              t.id,
                              v! ? TaskStatus.done : TaskStatus.todo,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 20),
                SectionTitle(
                  '时间安排',
                  action: TextButton(
                    onPressed: () => openEditor(
                      context,
                      EventEditor(
                        store: widget.store,
                        task: widget.task,
                        sync: widget.sync,
                      ),
                    ),
                    child: const Text('添加时间块'),
                  ),
                ),
                ListenableBuilder(
                  listenable: widget.store,
                  builder: (context, _) => Column(
                    children: widget.store.events
                        .where((e) => e.taskId == widget.task!.id)
                        .map(
                          (e) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${shortDate(e.start)} ${clockText(e.start)} – ${clockText(e.end)}',
                            ),
                            trailing: e.completed
                                ? const Icon(
                                    Icons.check_circle,
                                    color: Color(0xff20b69c),
                                  )
                                : IconButton(
                                    onPressed: () =>
                                        widget.store.completeEvent(e.id),
                                    icon: const Icon(
                                      Icons.radio_button_unchecked,
                                    ),
                                  ),
                            onTap: () => openEditor(
                              context,
                              EventEditor(
                                store: widget.store,
                                event: e,
                                sync: widget.sync,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            if (widget.task != null)
              TextButton(
                onPressed: () async {
                  final scope = widget.task!.seriesId == null
                      ? RepeatScope.thisOnly
                      : await chooseRepeatScope(context, '删除重复任务');
                  if (scope == null || !context.mounted) return;
                  widget.store.deleteTask(widget.task!.id, scope: scope);
                  Navigator.pop(context);
                },
                child: Text(
                  '移入回收站',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: save, child: const Text('保存')),
          ],
        ),
      ),
    ],
  );
}

String? requiredTitle(String? v) =>
    v == null || v.trim().isEmpty ? '请输入名称' : null;
Widget editorHeader(BuildContext context, String title) => Container(
  padding: const EdgeInsets.fromLTRB(24, 14, 12, 14),
  decoration: BoxDecoration(
    border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
  ),
  child: Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
        ),
      ),
      IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close),
      ),
    ],
  ),
);
Widget projectField(
  FlowStore store,
  String? value,
  ValueChanged<String?> onChanged,
) => FlowSelect<String>(
  key: ValueKey(store.project(value)?.id),
  initialValue: store.project(value)?.id,
  isExpanded: true,
  decoration: const InputDecoration(labelText: '所属项目'),
  items: [
    const DropdownMenuItem<String>(value: null, child: Text('无项目')),
    ...store.data.projects
        .where((project) => project.deletedAt == null || project.id == value)
        .map(
          (p) => DropdownMenuItem(
            value: p.id,
            child: Text(p.title, overflow: TextOverflow.ellipsis),
          ),
        ),
  ],
  onChanged: onChanged,
);

Future<DateTime?> pickDateTime(BuildContext context, DateTime value) async {
  final date = await showDatePicker(
    context: context,
    initialDate: value,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(value),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

class EventEditor extends StatefulWidget {
  const EventEditor({
    super.key,
    required this.store,
    this.event,
    this.task,
    this.initialDate,
    this.sync,
  });
  final FlowStore store;
  final CalendarEvent? event;
  final Task? task;
  final DateTime? initialDate;
  final SyncController? sync;
  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title, location, notes, actual, reminder;
  RepeatRule? repeatRule;
  bool actualEdited = false;
  bool? strongReminder;
  int? reminderInterval, maxReminders;
  bool strongEdited = false, intervalEdited = false, maximumEdited = false;
  bool reminderEdited = false, reminderRulesEdited = false;
  List<Map<String, dynamic>>? reminderRules;
  late DateTime start, end;
  late String? projectId;
  late bool locked, allDay;
  late int color;
  String? error;
  @override
  void initState() {
    super.initState();
    final e = widget.event;
    strongReminder = e?.strongReminder;
    reminderInterval = e?.reminderInterval;
    maxReminders = e?.maxReminders;
    title = TextEditingController(text: e?.title ?? widget.task?.title ?? '');
    location = TextEditingController(text: e?.location ?? '');
    notes = TextEditingController(text: e?.notes ?? '');
    actual = TextEditingController(text: '${e?.actualMinutes ?? 0}');
    reminder = TextEditingController(
      text: e?.reminderLeadMinutes?.toString() ?? '',
    );
    reminderRules = e?.reminderRules
        ?.map((r) => Map<String, dynamic>.from(r))
        .toList();
    repeatRule = e?.repeatRule == null
        ? (e == null ? _defaultRepeat(widget.store) : null)
        : RepeatRule.fromJson(e!.repeatRule!.toJson());
    start = e?.start ?? widget.initialDate ?? DateTime.now();
    end =
        e?.end ??
        start.add(
          Duration(
            minutes: widget.task?.estimateMinutes == 0
                ? widget.store.preferenceMinutes('defaultEventMinutes')
                : widget.task?.estimateMinutes ??
                      widget.store.preferenceMinutes('defaultEventMinutes'),
          ),
        );
    projectId = e?.projectId ?? widget.task?.projectId;
    locked = e?.locked ?? false;
    allDay = e?.allDay ?? false;
    color = e?.color ?? blue.toARGB32();
  }

  @override
  void dispose() {
    title.dispose();
    location.dispose();
    notes.dispose();
    actual.dispose();
    reminder.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (!end.isAfter(start)) {
      setState(() => error = '结束时间必须晚于开始时间');
      return;
    }
    if (widget.event?.locked == true &&
        (start != widget.event!.start || end != widget.event!.end)) {
      if (!await confirm(context, '移动锁定日程', '确认修改此锁定日程的时间？')) return;
    }
    if (!mounted) return;
    final scope = widget.event?.seriesId == null
        ? RepeatScope.thisOnly
        : await chooseRepeatScope(context, '修改重复日程');
    if (scope == null || !mounted) return;
    try {
      final latest = widget.store.data.events
          .where((e) => e.id == widget.event?.id)
          .firstOrNull;
      final e = latest != null
          ? CalendarEvent.fromJson(latest.toJson())
          : CalendarEvent(
              id: widget.event?.id ?? widget.store.newId(),
              title: title.text.trim(),
              start: start,
              end: end,
              projectId: widget.store.project(projectId)?.id,
              taskId: widget.event?.taskId ?? widget.task?.id,
              color: color,
              location: location.text,
              notes: notes.text,
              locked: locked,
              allDay: allDay,
              completed: widget.event?.completed ?? false,
              actualMinutes: widget.event?.actualMinutes ?? 0,
            );
      e.title = title.text.trim();
      e.start = start;
      e.end = end;
      e.projectId = widget.store.project(projectId)?.id;
      e.color = color;
      e.location = location.text;
      e.notes = notes.text;
      e.locked = locked;
      e.allDay = allDay;
      e.repeatRule = repeatRule;
      if (reminderEdited) {
        e.reminderLeadMinutes = reminder.text.trim().isEmpty
            ? null
            : int.parse(reminder.text.trim());
      }
      if (reminderRulesEdited) e.reminderRules = reminderRules;
      if (strongEdited) e.strongReminder = strongReminder;
      if (intervalEdited) e.reminderInterval = reminderInterval;
      if (maximumEdited) e.maxReminders = maxReminders;
      if (actualEdited || latest == null) {
        e.actualMinutes = int.parse(actual.text);
      }
      if (widget.event == null) {
        widget.store.addEvent(e);
      } else {
        widget.store.updateEvent(e, scope: scope);
      }
      Navigator.pop(context);
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      editorHeader(context, widget.event == null ? '新建日程' : '日程详情'),
      Expanded(
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '日程名称',
                  prefixIcon: Icon(Icons.event_outlined, size: 20),
                ),
                validator: requiredTitle,
              ),
              const SizedBox(height: 20),
              projectField(widget.store, projectId, (v) => projectId = v),
              if (widget.event != null &&
                  (widget.sync ?? SyncScope.of(context)) != null &&
                  identical(
                    (widget.sync ?? SyncScope.of(context))!.store,
                    widget.store,
                  ))
                EventSyncStatus(
                  sync: (widget.sync ?? SyncScope.of(context))!,
                  eventId: widget.event!.id,
                ),
              const SizedBox(height: 20),
              _EventTimeField(
                label: '开始时间',
                value: start,
                onPressed: () async {
                  final value = await pickDateTime(context, start);
                  if (value != null) {
                    setState(() {
                      final length = end.difference(start);
                      start = value;
                      end = start.add(length);
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              _EventTimeField(
                label: '结束时间',
                value: end,
                onPressed: () async {
                  final value = await pickDateTime(context, end);
                  if (value != null) setState(() => end = value);
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('全天'),
                value: allDay,
                onChanged: (v) => setState(() => allDay = v),
              ),
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                title: const Text('更多设置'),
                children: [
                  TextFormField(
                    key: const Key('event-reminder'),
                    controller: reminder,
                    onChanged: (_) => reminderEdited = true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '提前提醒（分钟）'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final value = int.tryParse(v.trim());
                      return value == null || value < 0 || value > 10080
                          ? '请输入 0–10080 分钟'
                          : null;
                    },
                  ),
                  const SizedBox(height: 16),
                  EventReminderRules(
                    initialRules: reminderRules,
                    onChanged: (v) {
                      reminderRules = v;
                      reminderRulesEdited = true;
                    },
                    pickDate: (v) => pickDateTime(context, v),
                  ),
                  const SizedBox(height: 16),
                  StrongReminderOptions(
                    strong: strongReminder,
                    interval: reminderInterval,
                    maximum: maxReminders,
                    onStrong: (v) {
                      strongReminder = v;
                      strongEdited = true;
                    },
                    onInterval: (v) {
                      reminderInterval = v;
                      intervalEdited = true;
                    },
                    onMaximum: (v) {
                      maxReminders = v;
                      maximumEdited = true;
                    },
                  ),
                  const SizedBox(height: 16),
                  RecurrenceForm(
                    initialRule: repeatRule,
                    onChanged: (v) => repeatRule = v,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('event-actual'),
                    controller: actual,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '实际耗时（分钟）'),
                    validator: (v) =>
                        int.tryParse(v ?? '') == null || int.parse(v!) < 0
                        ? '请输入非负整数'
                        : null,
                    onChanged: (_) => actualEdited = true,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: location,
                    decoration: const InputDecoration(labelText: '地点'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: notes,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: '备注'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('锁定日程'),
                    value: locked,
                    onChanged: (v) => setState(() => locked = v),
                  ),
                  Wrap(
                    spacing: 12,
                    children: palette
                        .map(
                          (c) => IconButton(
                            onPressed: () =>
                                setState(() => color = c.toARGB32()),
                            icon: Icon(
                              color == c.toARGB32()
                                  ? Icons.check_circle
                                  : Icons.circle,
                              color: c,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 10,
          children: [
            if (widget.event != null)
              TextButton(
                onPressed: () async {
                  final scope = widget.event!.seriesId == null
                      ? RepeatScope.thisOnly
                      : await chooseRepeatScope(context, '删除重复日程');
                  if (scope == null || !context.mounted) return;
                  widget.store.deleteEvent(widget.event!.id, scope: scope);
                  Navigator.pop(context);
                },
                child: Text(
                  '移入回收站',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (widget.event != null && !widget.event!.completed)
              OutlinedButton(
                onPressed: () {
                  widget.store.completeEvent(widget.event!.id);
                  Navigator.pop(context);
                },
                child: const Text('完成日程'),
              ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            SizedBox(
              width: 112,
              child: FilledButton(onPressed: save, child: const Text('保存')),
            ),
          ],
        ),
      ),
    ],
  );
}

class _EventTimeField extends StatelessWidget {
  const _EventTimeField({
    required this.label,
    required this.value,
    required this.onPressed,
  });
  final String label;
  final DateTime value;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$label ${dateText(value)} ${clockText(value)}',
    child: InkWell(
      key: ValueKey('event-time-$label'),
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.schedule_outlined, size: 20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(dateText(value), overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Text(
              clockText(value),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.expand_more,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> editProject(
  BuildContext context,
  FlowStore store, {
  Project? project,
  String? parentId,
}) async {
  final title = TextEditingController(text: project?.title ?? '');
  final description = TextEditingController(text: project?.description ?? '');
  final key = GlobalKey<FormState>();
  int color = project?.color ?? blue.toARGB32();
  String? parent = project?.parentId ?? parentId;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(project == null ? '新建项目 / 文件夹' : '编辑项目'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: key,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: title,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '名称'),
                    validator: requiredTitle,
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: description,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: '项目说明'),
                  ),
                  const SizedBox(height: 18),
                  FlowSelect<String>(
                    initialValue: parent,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '父级项目'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('顶层'),
                      ),
                      ...store.projects
                          .where((p) => p.id != project?.id)
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.id,
                              child: Text(p.title),
                            ),
                          ),
                    ],
                    onChanged: (v) => parent = v,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    children: palette
                        .map(
                          (c) => IconButton(
                            onPressed: () =>
                                setState(() => color = c.toARGB32()),
                            icon: Icon(
                              color == c.toARGB32()
                                  ? Icons.check_circle
                                  : Icons.circle,
                              color: c,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!key.currentState!.validate()) return;
              try {
                if (project == null) {
                  store.addProject(
                    Project(
                      id: store.newId(),
                      title: title.text.trim(),
                      description: description.text,
                      parentId: parent,
                      color: color,
                    ),
                  );
                } else {
                  store.moveProject(project.id, parent);
                  project.title = title.text.trim();
                  project.description = description.text;
                  project.color = color;
                  store.changed();
                }
                Navigator.pop(context);
              } catch (e) {
                setState(() => error = '$e');
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  description.dispose();
}
