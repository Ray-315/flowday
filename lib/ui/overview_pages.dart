import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../domain/models.dart';
import '../domain/store.dart';
import 'editors.dart';
import 'theme.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({super.key, required this.store});
  final FlowStore store;
  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  final input = TextEditingController();
  bool processed = false;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: input,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: '记录想法、日程或任务'),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () {
                  if (input.text.trim().isEmpty) return;
                  widget.store.capture(input.text);
                  input.clear();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('保存到 Inbox'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      ChoiceBar(
        labels: const ['待处理', '已处理'],
        selected: processed ? '已处理' : '待处理',
        onSelected: (v) => setState(() => processed = v == '已处理'),
      ),
      const SizedBox(height: 18),
      Expanded(
        child: ListView(
          children: widget.store.data.captures
              .where((c) => c.processed == processed)
              .toList()
              .reversed
              .map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(c.text, style: const TextStyle(height: 1.7)),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          children: [
                            Text(
                              '${shortDate(c.createdAt)} ${clockText(c.createdAt)}',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            Wrap(
                              spacing: 10,
                              children: [
                                if (!c.processed)
                                  TextButton(
                                    onPressed: () async {
                                      final ids = widget.store.tasks
                                          .map((t) => t.id)
                                          .toSet();
                                      await openEditor(
                                        context,
                                        TaskEditor(
                                          store: widget.store,
                                          initialTitle: c.text,
                                        ),
                                      );
                                      if (widget.store.tasks.any(
                                        (t) => !ids.contains(t.id),
                                      )) {
                                        c.processed = true;
                                        widget.store.changed();
                                      }
                                    },
                                    child: const Text('转为任务'),
                                  ),
                                TextButton(
                                  onPressed: () {
                                    c.processed = !c.processed;
                                    widget.store.changed();
                                  },
                                  child: Text(c.processed ? '移回待处理' : '标记已处理'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    ],
  );
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.store, this.initialDate});
  final FlowStore store;
  final DateTime? initialDate;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String period = '周';
  late DateTime date;
  DateTimeRange? customRange;
  FlowStore get store => widget.store;
  @override
  void initState() {
    super.initState();
    date = widget.initialDate ?? DateTime.now();
  }

  DateTime get start => switch (period) {
    '日' => dayOnly(date),
    '月' => displayDate(displayTime(date).year, displayTime(date).month, 1),
    '自定义' => customRange?.start ?? dayOnly(date),
    _ => addDays(dayOnly(date), -store.weekOffset(displayTime(date))),
  };
  DateTime get end => switch (period) {
    '日' => addDays(start, 1),
    '月' => displayDate(start.year, start.month + 1, 1),
    '自定义' => addDays(customRange?.end ?? dayOnly(date), 1),
    _ => addDays(start, 7),
  };
  DateTime addDays(DateTime value, int days) =>
      displayDate(value.year, value.month, value.day + days);
  int get spanDays => DateTime.utc(
    end.year,
    end.month,
    end.day,
  ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
  bool inPeriod(DateTime? value) =>
      value != null && !value.isBefore(start) && value.isBefore(end);
  int overlap(CalendarEvent event, DateTime from, DateTime to) {
    final a = event.start.isAfter(from) ? event.start : from;
    final b = event.end.isBefore(to) ? event.end : to;
    return b.isAfter(a) ? b.difference(a).inMinutes : 0;
  }

  double projectProgress(String id, List<Task> tasks) {
    final values = tasks.where((t) => t.projectId == id).toList();
    return values.isEmpty
        ? 0
        : values
                  .where(
                    (t) =>
                        t.status == TaskStatus.done && inPeriod(t.completedAt),
                  )
                  .length /
              values.length;
  }

  bool activeProject(String? id) {
    final seen = <String>{};
    while (id != null && seen.add(id)) {
      final value = store.project(id);
      if (value == null || value.deletedAt != null) return false;
      id = value.parentId;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => report(context),
  );
  Widget report(BuildContext context) {
    final blocks = store.events
        .where((e) => overlap(e, start, end) > 0)
        .toList();
    final taskIds = blocks.map((e) => e.taskId).toSet();
    final tasks = store.data.tasks
        .where(
          (t) =>
              t.deletedAt == null &&
              activeProject(t.projectId) &&
              t.status != TaskStatus.cancelled &&
              (inPeriod(t.completedAt) ||
                  inPeriod(t.plannedStart) ||
                  inPeriod(t.deadline) ||
                  taskIds.contains(t.id)),
        )
        .toList();
    final done = tasks
        .where((t) => t.status == TaskStatus.done && inPeriod(t.completedAt))
        .length;
    final blockActual = blocks
        .where((e) => e.completed)
        .fold<int>(
          0,
          (sum, event) =>
              sum +
              (event.actualMinutes *
                      overlap(event, start, end) /
                      event.end.difference(event.start).inMinutes)
                  .round(),
        );
    final manualActual = tasks
        .where(
          (t) =>
              inPeriod(t.completedAt) ||
              (t.completedAt == null && inPeriod(t.plannedStart)),
        )
        .fold<int>(0, (sum, task) {
          final linkedActual = store.events
              .where((e) => e.taskId == task.id && e.completed)
              .fold<int>(0, (v, e) => v + e.actualMinutes);
          return sum +
              (task.actualMinutes - linkedActual).clamp(0, task.actualMinutes);
        });
    final actual = blockActual + manualActual;
    final estimated = tasks.fold<int>(0, (v, t) => v + t.estimateMinutes);
    final stats = [
      ('完成任务', '$done', Icons.task_alt, Theme.of(context).colorScheme.primary),
      (
        '实际投入',
        '${(actual / 60).toStringAsFixed(1)} h',
        Icons.schedule,
        palette[2],
      ),
      (
        '预计耗时',
        '${(estimated / 60).toStringAsFixed(1)} h',
        Icons.hourglass_bottom,
        palette[4],
      ),
      (
        '完成率',
        '${tasks.isEmpty ? 0 : (done / tasks.length * 100).round()}%',
        Icons.pie_chart_outline,
        palette[1],
      ),
    ];
    return ListView(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceBar(
              labels: const ['日', '周', '月', '自定义'],
              selected: period,
              onSelected: (value) async {
                if (value == '自定义') {
                  final range = await showDateRangePicker(
                    context: context,
                    initialDateRange: customRange,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (range == null || !mounted) return;
                  setState(() {
                    customRange = DateTimeRange(
                      start: displayDate(
                        range.start.year,
                        range.start.month,
                        range.start.day,
                      ),
                      end: displayDate(
                        range.end.year,
                        range.end.month,
                        range.end.day,
                      ),
                    );
                    period = value;
                  });
                } else {
                  setState(() => period = value);
                }
              },
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final value = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (value != null) {
                  setState(
                    () =>
                        date = displayDate(value.year, value.month, value.day),
                  );
                }
              },
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('${dateText(start)} – ${dateText(addDays(end, -1))}'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 16,
            runSpacing: 16,
            children: stats
                .map(
                  (s) => SizedBox(
                    width:
                        (c.maxWidth - (c.maxWidth > 750 ? 48 : 16)) /
                        (c.maxWidth > 750 ? 4 : 2),
                    child: Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(s.$3, color: s.$4),
                          const SizedBox(height: 16),
                          Text(
                            s.$1,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            s.$2,
                            style: const TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 20),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('项目进度'),
              ...store.projects
                  .where((p) => !p.archived)
                  .map(
                    (p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.folder_outlined,
                                color: Color(p.color),
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Text(p.title)),
                              Text(
                                '${(projectProgress(p.id, tasks) * 100).round()}%',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: projectProgress(p.id, tasks),
                            minHeight: 7,
                            borderRadius: BorderRadius.circular(5),
                            color: Color(p.color),
                            backgroundColor: Theme.of(context).dividerColor,
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('已安排工时'),
              SizedBox(
                height: 190,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(spanDays.clamp(1, 7), (i) {
                    final count = spanDays.clamp(1, 7);
                    final from = addDays(start, (spanDays * i / count).floor());
                    final to = addDays(
                      start,
                      (spanDays * (i + 1) / count).floor(),
                    );
                    final minutes = store.events.fold<int>(
                      0,
                      (v, e) => v + overlap(e, from, to),
                    );
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${(minutes / 60).toStringAsFixed(1)}h',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: (minutes / 60 * 12)
                                  .clamp(2, 135)
                                  .toDouble(),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: .7),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${from.month}/${from.day}',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        pressurePanel(context),
        const SizedBox(height: 20),
        reviewPanel(),
      ],
    );
  }

  Widget pressurePanel(BuildContext context) {
    final count = spanDays.clamp(1, 31);
    final values = List<double>.generate(count, (i) {
      final from = addDays(start, (spanDays * i / count).floor());
      final to = addDays(start, (spanDays * (i + 1) / count).floor());
      final blocks = store.events
          .where((e) => overlap(e, from, to) > 0)
          .toList();
      final scheduled = blocks.fold<int>(
        0,
        (sum, e) => sum + overlap(e, from, to),
      );
      final todo = store.tasks
          .where(
            (t) =>
                t.status != TaskStatus.done &&
                t.status != TaskStatus.cancelled &&
                !blocks.any((e) => e.taskId == t.id) &&
                ((t.plannedStart != null &&
                        !t.plannedStart!.isBefore(from) &&
                        t.plannedStart!.isBefore(to)) ||
                    (t.plannedStart == null &&
                        t.deadline != null &&
                        !t.deadline!.isBefore(from) &&
                        t.deadline!.isBefore(to))),
          )
          .fold<int>(0, (sum, t) => sum + t.estimateMinutes);
      return (scheduled + todo) / 60;
    });
    final maximum = math.max(1.0, values.fold<double>(0, math.max));
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('压力曲线'),
          SizedBox(
            height: 150,
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${maximum.toStringAsFixed(1)}h'),
                      const Text('0h'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomPaint(
                    key: const Key('reports-pressure-curve'),
                    painter: PressureCurvePainter(
                      values: values,
                      maximum: maximum,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    size: const Size(double.infinity, 150),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(shortDate(start)),
              Text(shortDate(addDays(end, -1))),
            ],
          ),
        ],
      ),
    );
  }

  Widget reviewPanel() {
    final day = dayOnly(date),
        tomorrow = addDays(dayOnly(date), 1),
        afterTomorrow = addDays(dayOnly(date), 2);
    bool inDay(DateTime? value) =>
        value != null && !value.isBefore(day) && value.isBefore(tomorrow);
    final blocks = store.events
        .where((e) => overlap(e, day, tomorrow) > 0)
        .toList();
    final relevant = store.data.tasks
        .where(
          (t) =>
              t.deletedAt == null &&
              activeProject(t.projectId) &&
              t.status != TaskStatus.cancelled &&
              (inDay(t.completedAt) ||
                  inDay(t.plannedStart) ||
                  (t.deadline != null &&
                      t.deadline!.isBefore(tomorrow) &&
                      t.status != TaskStatus.done) ||
                  blocks.any((e) => e.taskId == t.id)),
        )
        .toList();
    final completed = relevant
        .where((t) => t.status == TaskStatus.done && inDay(t.completedAt))
        .length;
    final incomplete = relevant
        .where((t) => t.status != TaskStatus.done)
        .length;
    final blockActual = blocks
        .where((e) => e.completed)
        .fold<int>(
          0,
          (sum, e) =>
              sum +
              (e.actualMinutes *
                      overlap(e, day, tomorrow) /
                      e.end.difference(e.start).inMinutes)
                  .round(),
        );
    final manualActual = relevant
        .where(
          (t) =>
              inDay(t.completedAt) ||
              (t.completedAt == null && inDay(t.plannedStart)),
        )
        .fold<int>(0, (sum, t) {
          final linked = store.events
              .where((e) => e.taskId == t.id && e.completed)
              .fold<int>(0, (value, e) => value + e.actualMinutes);
          return sum + (t.actualMinutes - linked).clamp(0, t.actualMinutes);
        });
    final nextEvents =
        store.events
            .where((e) => overlap(e, tomorrow, afterTomorrow) > 0)
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final nextTasks = store.tasks.where(
      (t) =>
          t.status != TaskStatus.done &&
          t.status != TaskStatus.cancelled &&
          !nextEvents.any((e) => e.taskId == t.id) &&
          (t.plannedStart != null &&
                  !t.plannedStart!.isBefore(tomorrow) &&
                  t.plannedStart!.isBefore(afterTomorrow) ||
              t.deadline != null &&
                  !t.deadline!.isBefore(tomorrow) &&
                  t.deadline!.isBefore(afterTomorrow)),
    );
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle('晚间回顾 · ${shortDate(day)}'),
          Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              Text(
                '完成 $completed 项',
                key: const Key('report-review-completed'),
              ),
              Text(
                '未完成 $incomplete 项',
                key: const Key('report-review-incomplete'),
              ),
              Text(
                '实际投入 ${((blockActual + manualActual) / 60).toStringAsFixed(1)}h',
                key: const Key('report-review-actual'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SectionTitle('次日安排'),
          ...nextEvents.map(
            (e) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e.title),
              subtitle: Text(
                e.allDay ? '全天' : '${clockText(e.start)} – ${clockText(e.end)}',
              ),
              onTap: () =>
                  openEditor(context, EventEditor(store: store, event: e)),
            ),
          ),
          ...nextTasks.map(
            (t) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.title),
              onTap: () =>
                  openEditor(context, TaskEditor(store: store, task: t)),
            ),
          ),
        ],
      ),
    );
  }
}

class PressureCurvePainter extends CustomPainter {
  const PressureCurvePainter({
    required this.values,
    required this.maximum,
    required this.color,
  });
  final List<double> values;
  final double maximum;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final points = List<Offset>.generate(
      values.length,
      (i) => Offset(
        values.length == 1
            ? size.width / 2
            : i * size.width / (values.length - 1),
        size.height - values[i] / maximum * (size.height - 6) - 3,
      ),
    );
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final point in points) {
      canvas.drawCircle(point, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(PressureCurvePainter old) =>
      old.color != color ||
      old.maximum != maximum ||
      old.values.length != values.length ||
      old.values.indexed.any((entry) => entry.$2 != values[entry.$1]);
}

class NoticesPage extends StatefulWidget {
  const NoticesPage({
    super.key,
    required this.store,
    this.onOpenTask,
    this.onOpenEvent,
    this.onOpenProject,
    this.onOpenNode,
  });
  final FlowStore store;
  final ValueChanged<Task>? onOpenTask;
  final ValueChanged<CalendarEvent>? onOpenEvent;
  final ValueChanged<String>? onOpenProject;
  final ValueChanged<FlowNode>? onOpenNode;
  @override
  State<NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<NoticesPage> {
  String filter = '全部';
  FlowStore get store => widget.store;
  String category(AppNotice notice) {
    final explicit = const {
      'reminder': '提醒',
      'task': '提醒',
      'event': '提醒',
      'sync': '同步',
      'calendar_conflict': '同步',
      'sync_conflict': '同步',
      'workflow': '工作流',
      'node': '工作流',
      'review': '回顾',
      'daily_review': '回顾',
      'weekly_report': '回顾',
      'ai': 'AI',
      'system': '系统',
      '提醒': '提醒',
      '同步': '同步',
      '工作流': '工作流',
      '回顾': '回顾',
      '系统': '系统',
    }[notice.type];
    if (explicit != null) return explicit;
    final title = notice.title;
    if (title.contains('同步') || title.contains('冲突')) return '同步';
    if (title.contains('节点') || title.contains('工作流')) return '工作流';
    if (title.contains('回顾') || title.contains('周报')) return '回顾';
    if (title.contains('提醒')) return '提醒';
    return '系统';
  }

  void openNotice(AppNotice notice) {
    notice.read = true;
    store.changed();
    final node = store.data.nodes
        .where((n) => n.id == notice.nodeId)
        .firstOrNull;
    if (node != null && store.project(node.projectId)?.deletedAt == null) {
      if (widget.onOpenNode != null) {
        widget.onOpenNode!(node);
        return;
      }
      if (widget.onOpenProject != null) {
        widget.onOpenProject!(node.projectId);
        return;
      }
    }
    final event = store.events.where((e) => e.id == notice.eventId).firstOrNull;
    if (event != null) {
      if (widget.onOpenEvent != null) {
        widget.onOpenEvent!(event);
      } else {
        openEditor(context, EventEditor(store: store, event: event));
      }
      return;
    }
    final task = store.data.tasks
        .where((t) => t.id == notice.taskId && t.deletedAt == null)
        .firstOrNull;
    if (task != null) {
      if (widget.onOpenTask != null) {
        widget.onOpenTask!(task);
      } else {
        openEditor(context, TaskEditor(store: store, task: task));
      }
      return;
    }
    final project = store.project(notice.projectId ?? node?.projectId);
    if (project != null && project.deletedAt == null) {
      if (widget.onOpenProject != null) {
        widget.onOpenProject!(project.id);
      } else {
        editProject(context, store, project: project);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => Panel(
      child: Column(
        children: [
          SectionTitle(
            '通知',
            action: TextButton(
              onPressed: store.markAllRead,
              child: const Text('全部标为已读'),
            ),
          ),
          ChoiceBar(
            labels: const ['全部', '提醒', '同步', '工作流', 'AI', '回顾', '系统'],
            selected: filter,
            onSelected: (value) => setState(() => filter = value),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: store.data.notices.reversed
                  .where((n) => filter == '全部' || category(n) == filter)
                  .map(
                    (n) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      leading: Icon(
                        n.read
                            ? Icons.notifications_none
                            : Icons.notifications_active_outlined,
                        color: n.read
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(n.title),
                      subtitle: Text(n.body),
                      trailing: TextButton(
                        onPressed: () {
                          n.read = true;
                          n.acknowledged = true;
                          store.changed();
                        },
                        child: Text(n.acknowledged ? '已知晓' : '知晓'),
                      ),
                      onTap: () => openNotice(n),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    ),
  );
}

class TrashPage extends StatelessWidget {
  const TrashPage({super.key, required this.store});
  final FlowStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => Panel(
      child: ListView(
        children: [
          const SectionTitle('回收站'),
          ...store.data.projects
              .where((p) => p.deletedAt != null)
              .map(
                (p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.folder_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(p.title),
                  subtitle: Text('${dateText(p.deletedAt!)} · 项目'),
                  trailing: TextButton(
                    onPressed: () => store.restoreProject(p.id),
                    child: const Text('恢复'),
                  ),
                ),
              ),
          ...store.data.tasks
              .where((t) => t.deletedAt != null)
              .map(
                (t) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.check_box_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(t.title),
                  subtitle: Text('${dateText(t.deletedAt!)} · 任务'),
                  trailing: TextButton(
                    onPressed: () => store.restoreTask(t.id),
                    child: const Text('恢复'),
                  ),
                ),
              ),
          ...store.data.events
              .where((e) => e.deletedAt != null)
              .map(
                (e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.event_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(e.title),
                  subtitle: Text('${dateText(e.deletedAt!)} · 日程'),
                  trailing: TextButton(
                    onPressed: () => store.restoreEvent(e.id),
                    child: const Text('恢复'),
                  ),
                ),
              ),
        ],
      ),
    ),
  );
}
