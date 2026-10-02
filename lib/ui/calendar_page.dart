import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/calendar_layout.dart';
import '../domain/store.dart';
import 'editors.dart';
import 'theme.dart';
import 'mini_calendar.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.store});
  final FlowStore store;
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime selected = dayOnly(DateTime.now());
  DateTime calendarDay(DateTime day, [int offset = 0]) =>
      displayDate(day.year, day.month, day.day + offset);
  DateTime calendarHour(DateTime day, int hour) =>
      displayDate(day.year, day.month, day.day, hour);
  late String view;
  final hiddenProjects = <String?>{};
  final timeScroll = ScrollController(initialScrollOffset: 8 * 64);
  String get overlap =>
      widget.store.data.preferences['overlapStyle'] as String? ?? '并排';
  @override
  void dispose() {
    timeScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    view = widget.store.data.preferences['calendarView'] as String? ?? '月';
  }

  void step(int direction) => setState(() {
    selected = view == '月'
        ? displayDate(selected.year, selected.month + direction, 1)
        : calendarDay(selected, direction * (view == '周' ? 7 : 1));
  });
  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () =>
                            setState(() => selected = dayOnly(DateTime.now())),
                        child: const Text('今天'),
                      ),
                      IconButton(
                        onPressed: () => step(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        onPressed: () => step(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                      Text(
                        view == '月'
                            ? '${selected.year}年${selected.month}月'
                            : shortDate(selected),
                        style: TextStyle(
                          fontSize: narrow ? 15 : 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  ChoiceBar(
                    labels: const ['月', '周', '日', '时间轴', '列表'],
                    selected: view,
                    onSelected: (v) => setState(() {
                      view = v;
                      widget.store.data.preferences['calendarView'] = v;
                      widget.store.changed();
                    }),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '重叠样式',
                    initialValue: overlap,
                    onSelected: (v) => setState(() {
                      widget.store.data.preferences['overlapStyle'] = v;
                      widget.store.changed();
                    }),
                    itemBuilder: (_) => ['并排', '层叠', '聚合']
                        .map((v) => PopupMenuItem(value: v, child: Text(v)))
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        overlap,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => openEditor(
                      context,
                      EventEditor(
                        store: widget.store,
                        initialDate: calendarHour(selected, 9),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新建日程'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Panel(
                  padding: EdgeInsets.zero,
                  child: view == '月'
                      ? month()
                      : view == '列表' || view == '时间轴'
                      ? agenda()
                      : timeGrid(view == '周' ? 7 : 1),
                ),
              ),
            ],
          ),
        ),
        if (MediaQuery.sizeOf(context).width >= 1150) ...[
          const SizedBox(width: 16),
          SizedBox(width: 290, child: sidebar()),
        ],
      ],
    );
  }

  List<CalendarEvent> eventsOn(DateTime day) =>
      widget.store.events
          .where(
            (e) =>
                !hiddenProjects.contains(e.projectId) &&
                e.start.isBefore(calendarDay(day, 1)) &&
                e.end.isAfter(calendarDay(day)),
          )
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  Widget month() {
    final first = displayDate(selected.year, selected.month, 1);
    final start = calendarDay(first, -widget.store.weekOffset(first));
    final rowCount =
        ((displayDate(selected.year, selected.month + 1, 0).day +
                    widget.store.weekOffset(first)) /
                7)
            .ceil();
    return Column(
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children:
                (widget.store.preferenceFlag('weekStartsMonday')
                        ? ['一', '二', '三', '四', '五', '六', '日']
                        : ['日', '一', '二', '三', '四', '五', '六'])
                    .map(
                      (d) => Expanded(
                        child: Center(
                          child: Text(
                            '周$d',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => ListView(
              children: [
                SizedBox(
                  height: math.max(c.maxHeight, rowCount * 110.0),
                  child: Column(
                    children: List.generate(
                      rowCount,
                      (row) => Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: List.generate(7, (col) {
                            final day = calendarDay(start, row * 7 + col);
                            final entries = eventsOn(day);
                            return Expanded(
                              child: DragTarget<CalendarEvent>(
                                key: Key(
                                  'calendar-day-${day.year}-${day.month}-${day.day}',
                                ),
                                onWillAcceptWithDetails: (d) => !d.data.locked,
                                onAcceptWithDetails: (d) =>
                                    moveEvent(d.data, day),
                                builder: (context, candidate, rejected) =>
                                    InkWell(
                                      onTap: () {
                                        setState(() => selected = day);
                                        if (MediaQuery.sizeOf(context).width <
                                            1150) {
                                          showDay(day);
                                        }
                                      },
                                      onDoubleTap: () => openEditor(
                                        context,
                                        EventEditor(
                                          store: widget.store,
                                          initialDate: calendarHour(day, 9),
                                        ),
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color: candidate.isNotEmpty
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withValues(alpha: .1)
                                              : sameDay(day, DateTime.now())
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withValues(alpha: .06)
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.surface,
                                          border: Border.all(
                                            color: Theme.of(
                                              context,
                                            ).dividerColor,
                                            width: .5,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 27,
                                              height: 27,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color:
                                                    sameDay(day, DateTime.now())
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.primary
                                                    : null,
                                              ),
                                              child: Text(
                                                '${day.day}',
                                                style: TextStyle(
                                                  color:
                                                      sameDay(
                                                        day,
                                                        DateTime.now(),
                                                      )
                                                      ? Theme.of(
                                                          context,
                                                        ).colorScheme.onPrimary
                                                      : day.month ==
                                                            selected.month
                                                      ? Theme.of(
                                                          context,
                                                        ).colorScheme.onSurface
                                                      : Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            ...entries
                                                .take(3)
                                                .map(
                                                  (e) => Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom: 3,
                                                        ),
                                                    child:
                                                        LongPressDraggable<
                                                          CalendarEvent
                                                        >(
                                                          data: e,
                                                          maxSimultaneousDrags:
                                                              e.locked ? 0 : 1,
                                                          feedback: Material(
                                                            child: SizedBox(
                                                              width: 170,
                                                              child: eventChip(
                                                                e,
                                                              ),
                                                            ),
                                                          ),
                                                          child: eventChip(e),
                                                        ),
                                                  ),
                                                ),
                                            if (entries.length > 3)
                                              Text(
                                                '+${entries.length - 3}',
                                                style: TextStyle(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                  fontSize: 11,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget eventChip(CalendarEvent e) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    decoration: BoxDecoration(
      color: Color.alphaBlend(
        Color(e.color).withValues(alpha: .1),
        Theme.of(context).colorScheme.surface,
      ),
      borderRadius: BorderRadius.circular(4),
      border: Border(left: BorderSide(color: Color(e.color), width: 2)),
    ),
    child: Text(
      '${e.allDay ? '' : '${clockText(e.start)}  '}${e.title}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        color: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.onSurface
            : Color(e.color),
        decoration: e.completed ? TextDecoration.lineThrough : null,
      ),
    ),
  );
  Future<void> showDay(DateTime day) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            SectionTitle(
              dateText(day),
              action: IconButton(
                onPressed: () => openEditor(
                  context,
                  EventEditor(
                    store: widget.store,
                    initialDate: calendarHour(day, 9),
                  ),
                ),
                icon: const Icon(Icons.add),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.store,
                builder: (context, _) => ListView(
                  children: eventsOn(day)
                      .map((e) => EventTile(store: widget.store, event: e))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  void moveEvent(CalendarEvent e, DateTime day) {
    final duration = e.end.difference(e.start);
    final source = displayTime(e.start);
    e.start = displayDate(
      day.year,
      day.month,
      day.day,
      source.hour,
      source.minute,
    );
    e.end = e.start.add(duration);
    widget.store.changed();
  }

  Widget agenda() {
    final start = dayOnly(selected);
    final entries =
        widget.store.events
            .where(
              (e) =>
                  !hiddenProjects.contains(e.projectId) &&
                  e.end.isAfter(start) &&
                  e.start.isBefore(calendarDay(start, 31)),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i == 0 || !sameDay(entries[i - 1].start, entries[i].start))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Text(
                dateText(entries[i].start),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          if (view == '时间轴')
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 58,
                  child: Text(
                    clockText(entries[i].start),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5, right: 18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Expanded(
                  child: EventTile(store: widget.store, event: entries[i]),
                ),
              ],
            )
          else
            EventTile(store: widget.store, event: entries[i]),
        ],
      ],
    );
  }

  Widget sidebar() => ListView(
    children: [
      Panel(
        padding: const EdgeInsets.all(16),
        child: view == '月'
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(dateText(selected)),
                  ...eventsOn(
                    selected,
                  ).map((e) => EventTile(store: widget.store, event: e)),
                  TextButton.icon(
                    onPressed: () => openEditor(
                      context,
                      EventEditor(
                        store: widget.store,
                        initialDate: calendarHour(selected, 9),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('新建日程'),
                  ),
                ],
              )
            : MiniCalendar(
                weekStartsMonday: widget.store.preferenceFlag(
                  'weekStartsMonday',
                ),
                selected: selected,
                onSelected: (d) => setState(() => selected = calendarDay(d)),
                markedDays: widget.store.events
                    .where((e) => !hiddenProjects.contains(e.projectId))
                    .map((e) => displayTime(e.start))
                    .toList(),
              ),
      ),
      const SizedBox(height: 12),
      Panel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('我的日历'),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('个人日程'),
              value: !hiddenProjects.contains(null),
              onChanged: (v) => setState(
                () =>
                    v! ? hiddenProjects.remove(null) : hiddenProjects.add(null),
              ),
            ),
            ...widget.store.projects
                .where((p) => !p.archived)
                .map(
                  (p) => CheckboxListTile(
                    key: Key('calendar-project-${p.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: Color(p.color),
                    title: Text(p.title),
                    value: !hiddenProjects.contains(p.id),
                    onChanged: (v) => setState(
                      () => v!
                          ? hiddenProjects.remove(p.id)
                          : hiddenProjects.add(p.id),
                    ),
                  ),
                ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Panel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('待安排'),
            ...widget.store.tasks
                .where(
                  (t) =>
                      t.status != TaskStatus.done &&
                      t.status != TaskStatus.cancelled &&
                      !widget.store.events.any((e) => e.taskId == t.id),
                )
                .map(
                  (t) => Draggable<Object>(
                    data: t,
                    feedback: Material(
                      child: Container(
                        width: 220,
                        padding: const EdgeInsets.all(14),
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        child: Text(t.title),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(t.title),
                      subtitle: Text('${t.estimateMinutes / 60}h'),
                      trailing: Tag(
                        priorityLabels[t.priority.index],
                        color: priorityColor(t.priority),
                      ),
                      onTap: () => openEditor(
                        context,
                        EventEditor(
                          store: widget.store,
                          task: t,
                          initialDate: calendarHour(selected, 9),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    ],
  );

  void dropAt(Object value, DateTime start) {
    if (value is Task) {
      widget.store.addEvent(
        CalendarEvent(
          id: widget.store.newId(),
          title: value.title,
          start: start,
          end: start.add(
            Duration(minutes: math.max(15, value.estimateMinutes)),
          ),
          taskId: value.id,
          projectId: value.projectId,
          color:
              widget.store.project(value.projectId)?.color ?? blue.toARGB32(),
        ),
      );
    } else if (value is CalendarEvent && !value.locked) {
      final duration = value.end.difference(value.start);
      value.start = start;
      value.end = start.add(duration);
      widget.store.changed();
    }
    setState(() {});
  }

  List<CalendarEvent> overlapGroup(
    CalendarEvent e,
    List<CalendarEvent> entries,
  ) {
    final group = <CalendarEvent>[e];
    var added = true;
    while (added) {
      added = false;
      for (final candidate in entries) {
        if (!group.contains(candidate) &&
            group.any(
              (v) =>
                  v.start.isBefore(candidate.end) &&
                  v.end.isAfter(candidate.start),
            )) {
          group.add(candidate);
          added = true;
        }
      }
    }
    group.sort((a, b) {
      final time = a.start.compareTo(b.start);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
    return group;
  }

  Widget calendarBlock(CalendarEvent e, List<CalendarEvent> entries) {
    final overlaps = overlapGroup(e, entries);
    var resize = 0.0;
    final body = GestureDetector(
      onTap: () => overlap == '聚合' && overlaps.length > 1
          ? showModalBottomSheet<void>(
              context: context,
              builder: (_) => ListView(
                padding: const EdgeInsets.all(20),
                children: overlaps
                    .map((v) => EventTile(store: widget.store, event: v))
                    .toList(),
              ),
            )
          : openEditor(context, EventEditor(store: widget.store, event: e)),
      child: Container(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            Color(e.color).withValues(alpha: .14),
            Theme.of(context).colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border(left: BorderSide(color: Color(e.color), width: 3)),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: LayoutBuilder(
                  builder: (context, c) => c.maxHeight < 35
                      ? Text(
                          e.title,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Theme.of(context).colorScheme.onSurface
                                : Color(e.color),
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (c.maxWidth > 260)
                              SizedBox(
                                width: 110,
                                child: Text(
                                  '${clockText(e.start)} – ${clockText(e.end)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onSurface
                                        : Color(e.color),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    overlap == '聚合' && overlaps.length > 1
                                        ? '${overlaps.length} 个日程'
                                        : e.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (c.maxHeight > 50 &&
                                      e.location.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      e.location,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (e.locked)
                              Icon(
                                Icons.lock_outline,
                                size: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                          ],
                        ),
                ),
              ),
            ),
            if (!e.locked)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 9,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) => resize = 0,
                    onVerticalDragUpdate: (d) => resize += d.delta.dy,
                    onVerticalDragEnd: (_) {
                      final step = widget.store.preferenceMinutes(
                        'timeStepMinutes',
                        15,
                      );
                      final minutes = (resize / 64 * 60 / step).round() * step;
                      final end = e.end.add(Duration(minutes: minutes));
                      if (end.isAfter(e.start)) {
                        e.end = end;
                        widget.store.changed();
                        setState(() {});
                      }
                    },
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 2,
                        child: ColoredBox(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Draggable<Object>(
      data: e,
      maxSimultaneousDrags: e.locked ? 0 : 1,
      feedback: Material(
        child: SizedBox(width: 230, height: 70, child: eventChip(e)),
      ),
      childWhenDragging: Opacity(opacity: .4, child: body),
      child: body,
    );
  }

  Widget timeGrid(int days) {
    final first = days == 7
        ? calendarDay(selected, -widget.store.weekOffset(selected))
        : selected;
    return LayoutBuilder(
      builder: (context, c) {
        final width = math.max(c.maxWidth, days * 140.0 + 52);
        final dayWidth = (width - 52) / days;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              children: [
                SizedBox(
                  height: 45,
                  child: Row(
                    children: [
                      const SizedBox(width: 52),
                      ...List.generate(
                        days,
                        (i) => Expanded(
                          child: Center(
                            child: Text(
                              shortDate(calendarDay(first, i)),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (List.generate(
                  days,
                  (i) => eventsOn(calendarDay(first, i)).any((e) => e.allDay),
                ).any((v) => v))
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(
                          '全天',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      ...List.generate(
                        days,
                        (i) => Expanded(
                          child: Column(
                            children: eventsOn(calendarDay(first, i))
                                .where((e) => e.allDay)
                                .map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.all(3),
                                    child: InkWell(
                                      onTap: () => openEditor(
                                        context,
                                        EventEditor(
                                          store: widget.store,
                                          event: e,
                                        ),
                                      ),
                                      child: eventChip(e),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: timeScroll,
                    child: SizedBox(
                      height: 24 * 64,
                      child: Stack(
                        children: [
                          ...List.generate(
                            24,
                            (h) => Positioned(
                              top: h * 64,
                              left: 0,
                              right: 0,
                              child: SizedBox(
                                height: 64,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 52,
                                      child: Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: Text(
                                          '${h.toString().padLeft(2, '0')}:00',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                    ...List.generate(
                                      days,
                                      (i) => Expanded(
                                        child: GestureDetector(
                                          onDoubleTap: () => openEditor(
                                            context,
                                            EventEditor(
                                              store: widget.store,
                                              initialDate: calendarHour(
                                                calendarDay(first, i),
                                                h,
                                              ),
                                            ),
                                          ),
                                          child: DragTarget<Object>(
                                            key: Key('calendar-slot-$i-$h'),
                                            onWillAcceptWithDetails: (d) =>
                                                d.data is Task ||
                                                (d.data is CalendarEvent &&
                                                    !(d.data as CalendarEvent)
                                                        .locked),
                                            onAcceptWithDetails: (d) => dropAt(
                                              d.data,
                                              calendarHour(
                                                calendarDay(first, i),
                                                h,
                                              ),
                                            ),
                                            builder:
                                                (
                                                  context,
                                                  candidates,
                                                  rejected,
                                                ) => Container(
                                                  decoration: BoxDecoration(
                                                    border: Border.all(
                                                      color: Theme.of(
                                                        context,
                                                      ).dividerColor,
                                                      width: .5,
                                                    ),
                                                  ),
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          ...List.generate(days, (i) {
                            final day = calendarDay(first, i);
                            final entries = eventsOn(
                              day,
                            ).where((e) => !e.allDay).toList();
                            final lanes = calendarLanes(entries);
                            return entries
                                .where(
                                  (e) =>
                                      overlap != '聚合' ||
                                      overlapGroup(e, entries).first.id == e.id,
                                )
                                .map((e) {
                                  final column = lanes[e.id]!.lane;
                                  final count = lanes[e.id]!.count;
                                  final visibleStart = e.start.isBefore(day)
                                      ? day
                                      : e.start;
                                  final visibleEnd =
                                      e.end.isAfter(calendarDay(day, 1))
                                      ? calendarDay(day, 1)
                                      : e.end;
                                  final startTime = displayTime(visibleStart);
                                  final endTime = displayTime(visibleEnd);
                                  final startMinutes =
                                      startTime.hour * 60 + startTime.minute;
                                  final endMinutes = sameDay(visibleEnd, day)
                                      ? endTime.hour * 60 + endTime.minute
                                      : 1440;
                                  return Positioned(
                                    left:
                                        52 +
                                        i * dayWidth +
                                        (overlap == '层叠'
                                            ? column * 16
                                            : overlap == '聚合'
                                            ? 0
                                            : column * dayWidth / count) +
                                        3,
                                    top: startMinutes / 60 * 64 + 2,
                                    width: overlap == '并排'
                                        ? dayWidth / count - 6
                                        : dayWidth -
                                              (overlap == '层叠'
                                                  ? column * 16
                                                  : 0) -
                                              6,
                                    height: math.max(
                                      25,
                                      (endMinutes - startMinutes) / 60 * 64 - 4,
                                    ),
                                    child: calendarBlock(e, entries),
                                  );
                                })
                                .toList();
                          }).expand((v) => v),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.store, required this.event});
  final FlowStore store;
  final CalendarEvent event;
  @override
  Widget build(BuildContext context) {
    final e = event;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => openEditor(context, EventEditor(store: store, event: e)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              Color(e.color).withValues(alpha: .10),
              Theme.of(context).colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: Color(e.color), width: 3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.allDay
                          ? '全天'
                          : '${clockText(e.start)} – ${clockText(e.end)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      e.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: e.completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (e.location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        e.location,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (e.locked)
                Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              IconButton(
                onPressed: e.completed ? null : () => store.completeEvent(e.id),
                icon: Icon(
                  e.completed
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: e.completed
                      ? palette[2]
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
