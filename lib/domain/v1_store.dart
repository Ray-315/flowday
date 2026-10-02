part of 'store.dart';

extension FlowStoreV1 on FlowStore {
  Iterable<DateTime> _dates(
    RepeatRule rule,
    DateTime anchor,
    DateTime until,
  ) sync* {
    for (var index = 1; index < (rule.count ?? 1000); index++) {
      final date = rule.occurrence(anchor, index);
      if (date.isAfter(until) ||
          (rule.until != null && date.isAfter(rule.until!))) {
        break;
      }
      yield date;
    }
  }

  void _expandTask(Task task, {DateTime? until}) {
    final rule = task.repeatRule;
    if (rule == null ||
        (task.deletedAt != null &&
            !data.tasks.any(
              (x) => x.seriesId == task.seriesId && x.deletedAt == null,
            ))) {
      return;
    }
    final anchor =
        task.occurrenceDate ??
        task.plannedStart ??
        task.deadline ??
        DateTime.now();
    task.seriesId ??= task.id;
    task.occurrenceDate ??= anchor;
    for (final date in _dates(
      rule,
      anchor,
      until ?? anchor.add(const Duration(days: 366)),
    )) {
      if (data.tasks.any(
        (x) => x.seriesId == task.seriesId && x.occurrenceDate == date,
      )) {
        continue;
      }
      final copy = Task.fromJson(task.toJson());
      copy.id = newId();
      copy.occurrenceDate = date;
      final shift = date.difference(anchor);
      copy.plannedStart = task.plannedStart?.add(shift);
      copy.deadline = task.deadline?.add(shift);
      copy.status = TaskStatus.todo;
      copy.completedAt = null;
      copy.actualMinutes = 0;
      copy.deletedAt = null;
      data.tasks.add(copy);
    }
  }

  void _expandEvent(CalendarEvent event, {DateTime? until}) {
    final rule = event.repeatRule;
    if (rule == null ||
        (event.deletedAt != null &&
            !data.events.any(
              (x) => x.seriesId == event.seriesId && x.deletedAt == null,
            ))) {
      return;
    }
    final anchor = event.occurrenceDate ?? event.start;
    event.seriesId ??= event.id;
    event.occurrenceDate ??= anchor;
    for (final date in _dates(
      rule,
      anchor,
      until ?? anchor.add(const Duration(days: 366)),
    )) {
      if (data.events.any(
        (x) => x.seriesId == event.seriesId && x.occurrenceDate == date,
      )) {
        continue;
      }
      final copy = CalendarEvent.fromJson(event.toJson());
      copy.id = newId();
      copy.occurrenceDate = date;
      final shift = date.difference(anchor);
      copy.start = event.start.add(shift);
      copy.end = event.end.add(shift);
      copy.completed = false;
      copy.actualMinutes = 0;
      copy.deletedAt = null;
      data.events.add(copy);
    }
  }

  void materializeRecurring({required DateTime until}) {
    final taskSeries = <String>{}, eventSeries = <String>{};
    for (final task
        in List<Task>.from(data.tasks)..sort(
          (a, b) => (a.occurrenceDate ?? DateTime(1900)).compareTo(
            b.occurrenceDate ?? DateTime(1900),
          ),
        )) {
      if (task.repeatRule != null && taskSeries.add(task.seriesId ?? task.id)) {
        _expandTask(task, until: until);
      }
    }
    for (final event
        in List<CalendarEvent>.from(data.events)..sort(
          (a, b) => (a.occurrenceDate ?? a.start).compareTo(
            b.occurrenceDate ?? b.start,
          ),
        )) {
      if (event.repeatRule != null &&
          eventSeries.add(event.seriesId ?? event.id)) {
        _expandEvent(event, until: until);
      }
    }
    changed();
  }

  void _updateFutureTasks(Task old, Task value) {
    if (old.seriesId == null) {
      _expandTask(value);
      return;
    }
    final anchor = old.occurrenceDate ?? old.plannedStart ?? old.deadline!;
    if (jsonEncode(old.repeatRule?.toJson()) !=
        jsonEncode(value.repeatRule?.toJson())) {
      _endTaskSeries(old.seriesId!, anchor);
      value.seriesId = newId();
      value.occurrenceDate = value.plannedStart ?? value.deadline ?? anchor;
      _expandTask(value);
      return;
    }
    for (final task in data.tasks.where(
      (x) =>
          x.id != old.id &&
          x.seriesId == old.seriesId &&
          (x.occurrenceDate ?? anchor).isAfter(anchor),
    )) {
      final offset = task.occurrenceDate!.difference(anchor);
      task.title = value.title;
      task.description = value.description;
      task.projectId = value.projectId;
      task.priority = value.priority;
      task.difficulty = value.difficulty;
      task.estimateMinutes = value.estimateMinutes;
      task.splittable = value.splittable;
      task.tags = List.from(value.tags);
      task.attachments = value.attachments
          .map((x) => Attachment.fromJson(x.toJson()))
          .toList();
      task.plannedStart = value.plannedStart?.add(offset);
      task.deadline = value.deadline?.add(offset);
    }
    value.seriesId = old.seriesId;
    value.occurrenceDate = old.occurrenceDate;
  }

  void updateEvent(
    CalendarEvent value, {
    RepeatScope scope = RepeatScope.thisOnly,
  }) {
    final old = _event(value.id);
    final next = _copy();
    next.events[next.events.indexWhere((x) => x.id == value.id)] = value;
    next.validate();
    if (scope == RepeatScope.thisAndFuture && old.seriesId != null) {
      final anchor = old.occurrenceDate ?? old.start;
      final ruleChanged =
          jsonEncode(old.repeatRule?.toJson()) !=
          jsonEncode(value.repeatRule?.toJson());
      if (ruleChanged) {
        _endEventSeries(old.seriesId!, anchor);
        value.seriesId = newId();
        value.occurrenceDate = value.start;
        _expandEvent(value);
      }
      for (final event in data.events.where(
        (x) =>
            x.id != old.id &&
            x.seriesId == old.seriesId &&
            (x.occurrenceDate ?? x.start).isAfter(anchor),
      )) {
        if (ruleChanged) continue;
        final offset = (event.occurrenceDate ?? event.start).difference(anchor);
        event.title = value.title;
        event.start = value.start.add(offset);
        event.end = value.end.add(offset);
        event.projectId = value.projectId;
        event.location = value.location;
        event.notes = value.notes;
        event.color = value.color;
        event.locked = value.locked;
        event.allDay = value.allDay;
        event.reminderLeadMinutes = value.reminderLeadMinutes;
        event.strongReminder = value.strongReminder;
        event.reminderInterval = value.reminderInterval;
        event.maxReminders = value.maxReminders;
        event.reminderRules = value.reminderRules
            ?.map((x) => Map<String, dynamic>.from(x))
            .toList();
        event.tags = List.from(value.tags);
        event.attachments = value.attachments
            .map((x) => Attachment.fromJson(x.toJson()))
            .toList();
      }
    }
    value.seriesId ??= old.seriesId;
    value.occurrenceDate ??= old.occurrenceDate;
    data.events[data.events.indexWhere((x) => x.id == value.id)] = value;
    if (old.seriesId == null) _expandEvent(value);
    _recalculateActualMinutes(old.taskId);
    _recalculateActualMinutes(value.taskId);
    changed();
  }

  void _endTaskSeries(String seriesId, DateTime anchor) {
    for (final task in data.tasks.where((x) => x.seriesId == seriesId)) {
      if ((task.occurrenceDate ?? anchor).isAfter(anchor)) {
        task.deletedAt = DateTime.now();
      }
      if (task.repeatRule != null) {
        task.repeatRule = RepeatRule.fromJson(task.repeatRule!.toJson())
          ..until = anchor.subtract(const Duration(microseconds: 1));
      }
    }
  }

  void _endEventSeries(String seriesId, DateTime anchor) {
    for (final event in data.events.where((x) => x.seriesId == seriesId)) {
      if ((event.occurrenceDate ?? event.start).isAfter(anchor)) {
        event.deletedAt = DateTime.now();
      }
      if (event.repeatRule != null) {
        event.repeatRule = RepeatRule.fromJson(event.repeatRule!.toJson())
          ..until = anchor.subtract(const Duration(microseconds: 1));
      }
      _recalculateActualMinutes(event.taskId);
    }
  }

  void setEventActualMinutes(String id, int minutes) {
    if (minutes < 0) throw const FormatException('耗时不能为负数');
    final event = _event(id);
    event.actualMinutes = minutes;
    _recalculateActualMinutes(event.taskId);
    changed();
  }

  void deleteProject(String id) {
    final value = project(id);
    if (value == null) throw const FormatException('项目不存在');
    value.deletedAt = DateTime.now();
    changed();
  }

  void restoreProject(String id) {
    final value = project(id);
    if (value == null) throw const FormatException('项目不存在');
    value.deletedAt = null;
    if (project(value.parentId)?.deletedAt != null) value.parentId = null;
    changed();
  }

  void purgeTrash({DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).subtract(const Duration(days: 30));
    bool expired(DateTime? date) => date != null && !date.isAfter(cutoff);
    final projects = data.projects
        .where((x) => expired(x.deletedAt))
        .map((x) => x.id)
        .toSet();
    final tasks = data.tasks
        .where((x) => expired(x.deletedAt))
        .map((x) => x.id)
        .toSet();
    data.projects.removeWhere((x) => projects.contains(x.id));
    data.tasks.removeWhere((x) => tasks.contains(x.id));
    data.events.removeWhere((x) => expired(x.deletedAt));
    for (final project in data.projects) {
      if (projects.contains(project.parentId)) project.parentId = null;
    }
    for (final task in data.tasks) {
      if (projects.contains(task.projectId)) task.projectId = null;
      if (tasks.contains(task.parentId)) task.parentId = null;
    }
    for (final event in data.events) {
      if (projects.contains(event.projectId)) event.projectId = null;
      if (tasks.contains(event.taskId)) event.taskId = null;
    }
    final removedNodes = data.nodes
        .where((x) => projects.contains(x.projectId))
        .map((x) => x.id)
        .toSet();
    data.nodes.removeWhere((x) => removedNodes.contains(x.id));
    data.edges.removeWhere(
      (x) =>
          projects.contains(x.projectId) ||
          removedNodes.contains(x.sourceId) ||
          removedNodes.contains(x.targetId),
    );
    for (final node in data.nodes) {
      if (tasks.contains(node.taskId)) node.taskId = null;
      if (projects.contains(node.targetProjectId)) node.targetProjectId = null;
      if (removedNodes.contains(node.groupId)) node.groupId = null;
    }
    for (final notice in data.notices) {
      if (tasks.contains(notice.taskId)) notice.taskId = null;
    }
    changed();
  }

  void selectBranch(String nodeId, String edgeId) {
    final node = _node(nodeId);
    if (node.kind != NodeKind.condition ||
        !data.edges.any((x) => x.id == edgeId && x.sourceId == nodeId)) {
      throw const FormatException('条件出口无效');
    }
    node.selectedBranchEdgeId = edgeId;
    node.status = NodeStatus.done;
    node.completedAt = DateTime.now();
    _refreshDependencies();
    changed();
  }

  void refreshWorkflow({DateTime? now}) {
    final before = data.nodes.map((x) => (x.status, x.delayWaiting)).toList();
    _refreshDependencies(now: now);
    if (data.nodes.indexed.any(
      (x) => before[x.$1] != (x.$2.status, x.$2.delayWaiting),
    )) {
      changed();
    }
  }

  void moveGroup(String groupId, double dx, double dy) {
    final group = _node(groupId);
    if (group.kind != NodeKind.group || !dx.isFinite || !dy.isFinite) {
      throw const FormatException('分组移动无效');
    }
    final ids = <String>{groupId};
    bool added;
    do {
      added = false;
      for (final node in data.nodes) {
        if (ids.contains(node.groupId) && ids.add(node.id)) added = true;
      }
    } while (added);
    for (final node in data.nodes.where((x) => ids.contains(x.id))) {
      node.x += dx;
      node.y += dy;
    }
    changed();
  }
}
