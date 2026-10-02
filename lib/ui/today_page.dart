import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/calendar_layout.dart';
import '../domain/models.dart';
import '../domain/store.dart';
import 'editors.dart';
import 'mini_calendar.dart';
import 'theme.dart';
import 'today_customization.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({
    super.key,
    required this.store,
    required this.navigate,
    this.onParse,
    this.onOpenWorkflow,
  });
  final FlowStore store;
  final ValueChanged<String> navigate;
  final ValueChanged<String>? onParse;
  final ValueChanged<String>? onOpenWorkflow;
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  DateTime selected = dayOnly(DateTime.now());
  DateTime get nextDay =>
      displayDate(selected.year, selected.month, selected.day + 1);
  String filter = '今天';
  final input = TextEditingController();
  late final Timer clock;
  @override
  void initState() {
    super.initState();
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    clock.cancel();
    input.dispose();
    super.dispose();
  }

  List<CalendarEvent> get events =>
      widget.store.events
          .where((e) => e.start.isBefore(nextDay) && e.end.isAfter(selected))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  List<Task> get tasks => widget.store.tasks
      .where((t) => t.parentId == null && t.status != TaskStatus.cancelled)
      .toList();
  bool plannedToday(Task t) =>
      t.deadline != null && sameDay(t.deadline!, selected) ||
      t.plannedStart != null && sameDay(t.plannedStart!, selected) ||
      events.any((e) => e.taskId == t.id);
  void capture() {
    if (input.text.trim().isEmpty) return;
    if (widget.onParse != null) {
      widget.onParse!(input.text.trim());
      return;
    }
    openEditor(
      context,
      TaskEditor(store: widget.store, initialTitle: input.text.trim()),
    );
    input.clear();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => LayoutBuilder(
      builder: (context, c) {
        final order = todayModuleOrder(widget.store);
        final hidden = todayHiddenModules(widget.store);
        final defaultLayout =
            order.join(',') == todayModules.keys.join(',') &&
            hidden.length == defaultTodayHidden.length &&
            hidden.containsAll(defaultTodayHidden);
        if (!defaultLayout) {
          return ListView(
            children: [
              for (final id in order.where((x) => !hidden.contains(x)))
                Padding(
                  key: ValueKey('today-section-$id'),
                  padding: const EdgeInsets.only(bottom: 14),
                  child: module(id),
                ),
            ],
          );
        }
        final wide = c.maxWidth >= 970;
        final todo = todoPanel();
        final bottom = LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 440
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: calendar()),
                    const SizedBox(width: 14),
                    Expanded(child: overview()),
                  ],
                )
              : Column(
                  children: [
                    calendar(),
                    const SizedBox(height: 14),
                    overview(),
                  ],
                ),
        );
        return ListView(
          children: [
            Panel(
              padding: const EdgeInsets.all(10),
              child: TextField(
                key: const Key('today-capture'),
                controller: input,
                onSubmitted: (_) => capture(),
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    Icons.auto_awesome,
                    color: palette[1],
                    size: 21,
                  ),
                  hintText: '试试输入：明天下午两点安排一个小时写论文，顺便提醒我…',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                  suffixIcon: IconButton(
                    key: const Key('today-capture-submit'),
                    onPressed: capture,
                    icon: Icon(
                      Icons.send_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  filled: false,
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 57, child: timeline()),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 43,
                    child: Column(
                      children: [todo, const SizedBox(height: 14), bottom],
                    ),
                  ),
                ],
              )
            else ...[
              timeline(),
              const SizedBox(height: 14),
              todo,
              const SizedBox(height: 14),
              bottom,
            ],
          ],
        );
      },
    ),
  );
  Widget module(String id) => switch (id) {
    'capture' => Panel(
      padding: const EdgeInsets.all(10),
      child: TextField(
        key: const Key('today-capture'),
        controller: input,
        onSubmitted: (_) => capture(),
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.auto_awesome, color: palette[1], size: 21),
          hintText: '试试输入：明天下午两点安排一个小时写论文，顺便提醒我…',
          suffixIcon: IconButton(
            key: const Key('today-capture-submit'),
            onPressed: capture,
            icon: const Icon(Icons.send_outlined, size: 20),
          ),
          filled: false,
        ),
      ),
    ),
    'timeline' => timeline(),
    'todo' => todoPanel(),
    'calendar' => calendar(),
    'overview' => overview(),
    'workflow' => workflowSummary(),
    'overdue' => overdueSummary(),
    'pressure' => pressureSummary(),
    _ => noticesSummary(),
  };

  Widget workflowSummary() {
    final projects = widget.store.projects.where((p) => !p.archived).toList();
    final nodes = widget.store.data.nodes.where(
      (n) => const [
        NodeStatus.ready,
        NodeStatus.doing,
        NodeStatus.waiting,
      ].contains(n.status),
    );
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('工作流当前节点'),
          for (final project in projects.where(
            (p) => nodes.any((n) => n.projectId == p.id),
          )) ...[
            Text(
              project.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            ...nodes
                .where((n) => n.projectId == project.id)
                .map(
                  (n) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(n.title),
                    trailing: Text(
                      const [
                        '已锁定',
                        '可开始',
                        '进行中',
                        '等待',
                        '已完成',
                        '已跳过',
                      ][n.status.index],
                    ),
                    onTap: () => widget.onOpenWorkflow != null
                        ? widget.onOpenWorkflow!(project.id)
                        : widget.navigate('workflow'),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget overdueSummary() {
    final now = DateTime.now();
    final overdue = tasks.where(
      (t) =>
          t.deadline != null &&
          t.deadline!.isBefore(now) &&
          t.status != TaskStatus.done,
    );
    final blocks = widget.store.events.where(
      (e) => e.taskId != null && !e.completed && e.end.isBefore(now),
    );
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('逾期'),
          ...overdue.map(
            (t) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.title),
              subtitle: Text(
                '${shortDate(t.deadline!)} ${clockText(t.deadline!)}',
              ),
              trailing: IconButton(
                onPressed: () =>
                    widget.store.setTaskStatus(t.id, TaskStatus.done),
                icon: const Icon(Icons.check),
              ),
              onTap: () =>
                  openEditor(context, TaskEditor(store: widget.store, task: t)),
            ),
          ),
          ...blocks.map(
            (e) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e.title),
              subtitle: Text(
                '${shortDate(e.start)} ${clockText(e.start)} – ${clockText(e.end)}',
              ),
              trailing: IconButton(
                onPressed: () => widget.store.completeEvent(e.id),
                icon: const Icon(Icons.check),
              ),
              onTap: () => openEditor(
                context,
                EventEditor(store: widget.store, event: e),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget pressureSummary() {
    final week = displayDate(
      selected.year,
      selected.month,
      selected.day - widget.store.weekOffset(selected),
    );
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('本周压力'),
          for (var i = 0; i < 7; i++)
            Builder(
              builder: (context) {
                final day = displayDate(week.year, week.month, week.day + i);
                final end = displayDate(
                  week.year,
                  week.month,
                  week.day + i + 1,
                );
                final blocks = widget.store.events
                    .where((e) => e.start.isBefore(end) && e.end.isAfter(day))
                    .toList();
                final scheduled = blocks.fold<int>(0, (sum, e) {
                  final start = e.start.isAfter(day) ? e.start : day;
                  final finish = e.end.isBefore(end) ? e.end : end;
                  return sum + finish.difference(start).inMinutes;
                });
                final estimated = tasks
                    .where(
                      (t) =>
                          t.status != TaskStatus.done &&
                          !blocks.any((e) => e.taskId == t.id) &&
                          (t.plannedStart != null &&
                                  sameDay(t.plannedStart!, day) ||
                              t.deadline != null && sameDay(t.deadline!, day)),
                    )
                    .fold<int>(0, (sum, t) => sum + t.estimateMinutes);
                final hours = scheduled + estimated;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(shortDate(day))),
                          Text(
                            '日程 ${(scheduled / 60).toStringAsFixed(1)}h · 待办 ${(estimated / 60).toStringAsFixed(1)}h',
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: (hours / 480).clamp(0, 1),
                        color: hours > 480
                            ? palette[3]
                            : Theme.of(context).colorScheme.primary,
                        backgroundColor: Theme.of(context).dividerColor,
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget noticesSummary() => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          '通知摘要',
          action: TextButton(
            onPressed: () => widget.navigate('notices'),
            child: const Text('查看全部'),
          ),
        ),
        ...widget.store.data.notices
            .where((n) => !n.read || !n.acknowledged)
            .take(5)
            .map(
              (n) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(n.title),
                subtitle: Text(n.body),
                trailing: TextButton(
                  onPressed: () {
                    n.read = true;
                    n.acknowledged = true;
                    widget.store.changed();
                  },
                  child: const Text('已知晓'),
                ),
                onTap: () => widget.navigate('notices'),
              ),
            ),
        if (widget.store.error != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('同步错误'),
            subtitle: Text(widget.store.error!),
          ),
      ],
    ),
  );

  Widget timeline() {
    final now = displayTime(DateTime.now());
    final timed = events.where((e) => !e.allDay).toList();
    final startHour = timed.fold<int>(
      8,
      (v, e) => math.min(
        v,
        sameDay(e.start, selected) ? displayTime(e.start).hour : 0,
      ),
    );
    final endHour = timed.fold<int>(
      23,
      (v, e) => math.max(
        v,
        sameDay(e.end, selected)
            ? displayTime(e.end).hour + (displayTime(e.end).minute > 0 ? 1 : 0)
            : 24,
      ),
    );
    final hours = endHour - startHour;
    const hourHeight = 46.0;
    final lanes = calendarLanes(timed);
    return Panel(
      key: const Key('today-timeline'),
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 20),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, c) => Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_month_outlined, size: 22),
                    SizedBox(width: 10),
                    Text(
                      '今日日程',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(
                        () => selected = displayDate(
                          selected.year,
                          selected.month,
                          selected.day - 1,
                        ),
                      ),
                      icon: const Icon(Icons.chevron_left, size: 18),
                    ),
                    Text(
                      '${selected.year}年${selected.month}月${selected.day}日',
                      style: TextStyle(fontSize: c.maxWidth < 450 ? 11 : 12),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => selected = nextDay),
                      icon: const Icon(Icons.chevron_right, size: 18),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => selected = dayOnly(DateTime.now())),
                      child: const Text('今天'),
                    ),
                    TextButton.icon(
                      onPressed: () => openEditor(
                        context,
                        EventEditor(
                          store: widget.store,
                          initialDate: displayDate(
                            selected.year,
                            selected.month,
                            selected.day,
                            9,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('新建日程'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...events
              .where((e) => e.allDay)
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.only(left: 48, bottom: 8),
                  child: InkWell(
                    onTap: () => openEditor(
                      context,
                      EventEditor(store: widget.store, event: e),
                    ),
                    child: eventBlock(e, compact: true),
                  ),
                ),
              ),
          SizedBox(
            height: hours * hourHeight + 28,
            child: LayoutBuilder(
              builder: (context, c) => Stack(
                children: [
                  for (int i = 0; i <= hours; i++)
                    Positioned(
                      top: i * hourHeight,
                      left: 0,
                      right: 0,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 48,
                            child: Text(
                              '${(startHour + i).toString().padLeft(2, '0')}:00',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Divider(
                                height: 1,
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ...timed.map((e) {
                    final start = e.start.isBefore(selected)
                        ? selected
                        : e.start;
                    final end = e.end.isAfter(nextDay) ? nextDay : e.end;
                    final lane = lanes[e.id]!;
                    final wallStart = displayTime(start);
                    final wallEnd = displayTime(end);
                    final startMinutes = wallStart.hour * 60 + wallStart.minute;
                    final endMinutes = sameDay(end, selected)
                        ? wallEnd.hour * 60 + wallEnd.minute
                        : 1440;
                    final top =
                        (startMinutes / 60 - startHour) * hourHeight + 7;
                    final h = math.max(
                      28.0,
                      (endMinutes - startMinutes) / 60 * hourHeight - 8,
                    );
                    final width = (c.maxWidth - 56) / lane.count;
                    return Positioned(
                      top: top,
                      left: 56 + lane.lane * width,
                      width: width - 3,
                      height: h,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(7),
                        onTap: () => openEditor(
                          context,
                          EventEditor(store: widget.store, event: e),
                        ),
                        child: eventBlock(e, compact: h < 60),
                      ),
                    );
                  }),
                  if (sameDay(now, selected) &&
                      now.hour >= startHour &&
                      now.hour < endHour)
                    Positioned(
                      key: const Key('today-current-time'),
                      top:
                          ((now.hour + now.minute / 60) - startHour) *
                              hourHeight +
                          7,
                      left: 48,
                      right: 0,
                      child: IgnorePointer(
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: palette[3],
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Container(height: 1, color: palette[3]),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget eventBlock(CalendarEvent e, {bool compact = false}) => Container(
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 5 : 9),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border(left: BorderSide(color: Color(e.color), width: 3)),
      gradient: LinearGradient(
        colors: [
          Color.alphaBlend(
            Color(e.color).withValues(alpha: .13),
            Theme.of(context).colorScheme.surface,
          ),
          Color.alphaBlend(
            Color(e.color).withValues(alpha: .09),
            Theme.of(context).colorScheme.surface,
          ),
        ],
      ),
    ),
    child: LayoutBuilder(
      builder: (context, c) {
        final time = e.allDay
            ? '全天'
            : '${clockText(e.start)} - ${clockText(e.end)}';
        if (compact || c.maxHeight < 38) {
          return Text(
            '$time  ${e.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          );
        }
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              e.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context).colorScheme.onSurface
                    : Color.lerp(
                        Theme.of(context).colorScheme.onSurface,
                        Color(e.color),
                        .35,
                      ),
                decoration: e.completed ? TextDecoration.lineThrough : null,
              ),
            ),
            if (e.location.isNotEmpty &&
                c.maxHeight >= (c.maxWidth > 360 ? 45 : 65)) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      e.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
        return c.maxWidth > 360
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 106,
                    child: Text(
                      time,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(child: details),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    time,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(child: details),
                ],
              );
      },
    ),
  );
  Widget todoPanel() {
    final visible = tasks
        .where(
          (t) => switch (filter) {
            '今天' => plannedToday(t),
            '本周' =>
              t.deadline != null &&
                  !t.deadline!.isBefore(
                    displayDate(
                      selected.year,
                      selected.month,
                      selected.day - widget.store.weekOffset(selected),
                    ),
                  ) &&
                  t.deadline!.isBefore(
                    displayDate(
                      selected.year,
                      selected.month,
                      selected.day - widget.store.weekOffset(selected) + 7,
                    ),
                  ),
            '高优先级' => t.priority.index >= Priority.high.index,
            _ => true,
          },
        )
        .toList();
    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            '任务 (${tasks.length})',
            action: TextButton.icon(
              onPressed: () =>
                  openEditor(context, TaskEditor(store: widget.store)),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新建任务'),
            ),
          ),
          ChoiceBar(
            labels: const ['全部', '今天', '本周', '高优先级'],
            selected: filter,
            onSelected: (v) => setState(() => filter = v),
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty) const SizedBox(height: 100),
          ...visible
              .take(8)
              .map(
                (t) => InkWell(
                  onTap: () => openEditor(
                    context,
                    TaskEditor(store: widget.store, task: t),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 29,
                          height: 30,
                          child: Checkbox(
                            value: t.status == TaskStatus.done,
                            onChanged: (v) => widget.store.setTaskStatus(
                              t.id,
                              v! ? TaskStatus.done : TaskStatus.todo,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                              const SizedBox(height: 7),
                              Wrap(
                                spacing: 10,
                                runSpacing: 5,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (t.deadline != null)
                                    Text(
                                      '${sameDay(t.deadline!, DateTime.now()) ? '今天' : shortDate(t.deadline!)} ${clockText(t.deadline!)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            t.deadline!.isBefore(
                                                  DateTime.now(),
                                                ) &&
                                                t.status != TaskStatus.done
                                            ? palette[3]
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  Tag(
                                    priorityLabels[t.priority.index],
                                    color: priorityColor(t.priority),
                                  ),
                                  Text(
                                    '${(t.estimateMinutes / 60).toStringAsFixed(t.estimateMinutes % 60 == 0 ? 0 : 1)}h',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  ),
                                  ...t.tags
                                      .take(2)
                                      .map(
                                        (tag) => Tag(tag, color: palette[1]),
                                      ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Icon(
                            Icons.keyboard_arrow_down,
                            size: 17,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget calendar() => Panel(
    key: const Key('today-mini-calendar'),
    padding: const EdgeInsets.all(15),
    child: MiniCalendar(
      weekStartsMonday: widget.store.preferenceFlag('weekStartsMonday'),
      selected: selected,
      onSelected: (v) =>
          setState(() => selected = displayDate(v.year, v.month, v.day)),
      markedDays: widget.store.events.map((e) => displayTime(e.start)).toList(),
    ),
  );
  Widget overview() {
    final planned = tasks.where(plannedToday).toList();
    final done = planned.where((t) => t.status == TaskStatus.done).length;
    final rate = planned.isEmpty ? 0.0 : done / planned.length;
    final metrics = [
      (
        '总日程',
        events.length,
        Theme.of(context).colorScheme.primary,
        Icons.calendar_today_outlined,
      ),
      (
        '待办任务',
        planned.where((t) => t.status != TaskStatus.done).length,
        palette[4],
        Icons.assignment_outlined,
      ),
      ('已完成', done, palette[2], Icons.task_alt),
      (
        '进行中',
        planned.where((t) => t.status == TaskStatus.doing).length,
        palette[4],
        Icons.play_circle_outline,
      ),
      (
        '逾期',
        planned
            .where(
              (t) =>
                  t.deadline != null &&
                  t.deadline!.isBefore(DateTime.now()) &&
                  t.status != TaskStatus.done,
            )
            .length,
        palette[3],
        Icons.event_busy_outlined,
      ),
    ];
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '本日概览',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) => Wrap(
              spacing: 10,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: c.maxWidth >= 210 ? c.maxWidth - 100 : c.maxWidth,
                  child: Column(
                    children: metrics
                        .map(
                          (m) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Row(
                              children: [
                                Icon(m.$4, size: 16, color: m.$3),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    m.$1,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${m.$2}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                SizedBox(
                  width: 80,
                  height: 80,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 76,
                        height: 76,
                        child: CircularProgressIndicator(
                          value: rate,
                          strokeWidth: 7,
                          backgroundColor: Theme.of(context).dividerColor,
                          color: palette[2],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(rate * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '今日完成',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
        ],
      ),
    );
  }
}
