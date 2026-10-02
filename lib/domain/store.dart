import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models.dart';

part 'v1_store.dart';

class FlowStore extends ChangeNotifier {
  FlowData data;
  final Future<void> Function(FlowData)? _save;
  Future<void> _pending = Future<void>.value();
  String? error;
  int _counter = 0;
  int _revision = 0;
  int _importGeneration = 0;
  bool _disposed = false;
  FlowStore(this.data, {Future<void> Function(FlowData)? save}) : _save = save;
  bool preferenceFlag(String key, [bool fallback = true]) =>
      data.preferences[key] is bool ? data.preferences[key] as bool : fallback;
  int preferenceMinutes(String key, [int fallback = 60]) {
    final value = data.preferences[key];
    return value is int && value > 0 && value <= 1440 ? value : fallback;
  }

  Priority preferencePriority(String key) =>
      Priority.values
          .where((value) => value.name == data.preferences[key])
          .firstOrNull ??
      Priority.normal;

  int weekOffset(DateTime date) =>
      preferenceFlag('weekStartsMonday') ? date.weekday - 1 : date.weekday % 7;
  String newId() => '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
  List<Project> get projects =>
      data.projects.where((x) => x.deletedAt == null).toList();
  bool _hiddenProject(String? id) {
    final seen = <String>{};
    while (id != null && seen.add(id)) {
      final p = project(id);
      if (p == null || p.archived || p.deletedAt != null) return true;
      id = p.parentId;
    }
    return false;
  }

  List<Task> get tasks => data.tasks
      .where(
        (x) =>
            x.deletedAt == null && !x.archived && !_hiddenProject(x.projectId),
      )
      .toList();
  List<CalendarEvent> get events => data.events
      .where((x) => x.deletedAt == null && !_deletedProject(x.projectId))
      .toList();
  bool _deletedProject(String? id) {
    final seen = <String>{};
    while (id != null && seen.add(id)) {
      final value = project(id);
      if (value == null || value.deletedAt != null) return true;
      id = value.parentId;
    }
    return false;
  }

  Project? project(String? id) {
    for (final p in data.projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  double progress(String projectId) {
    final relevant = data.tasks
        .where(
          (x) =>
              x.projectId == projectId &&
              x.deletedAt == null &&
              x.status != TaskStatus.cancelled,
        )
        .toList();
    return relevant.isEmpty
        ? 0
        : relevant.where((x) => x.status == TaskStatus.done).length /
              relevant.length;
  }

  Task _task(String id) => data.tasks.firstWhere(
    (x) => x.id == id,
    orElse: () => throw const FormatException('任务不存在'),
  );
  FlowNode _node(String id) => data.nodes.firstWhere(
    (x) => x.id == id,
    orElse: () => throw const FormatException('节点不存在'),
  );
  CalendarEvent _event(String id) => data.events.firstWhere(
    (x) => x.id == id,
    orElse: () => throw const FormatException('日程不存在'),
  );
  FlowData _copy() => FlowData.fromJson(
    jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
  );
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void changed() {
    data.validate();
    _revision++;
    _notify();
    persist();
  }

  Future<void> persist() {
    final generation = _importGeneration;
    FlowData snapshot;
    try {
      snapshot = _copy();
    } catch (e) {
      error = '保存失败：$e';
      _notify();
      return Future<void>.value();
    }
    _pending = _pending.then((_) async {
      if (generation != _importGeneration) return;
      try {
        await _save?.call(snapshot);
        if (error != null) {
          error = null;
          _notify();
        }
      } catch (e) {
        error = '保存失败：$e';
        _notify();
      }
    });
    return _pending;
  }

  void addTask(Task task) {
    final next = _copy();
    next.tasks.add(task);
    next.validate();
    task.completedAt = task.status == TaskStatus.done
        ? (task.completedAt ?? DateTime.now())
        : null;
    data.tasks.add(task);
    _expandTask(task);
    changed();
  }

  void updateTask(Task task, {RepeatScope scope = RepeatScope.thisOnly}) {
    final index = data.tasks.indexWhere((x) => x.id == task.id);
    if (index < 0) throw const FormatException('任务不存在');
    task.seriesId ??= data.tasks[index].seriesId;
    task.occurrenceDate ??= data.tasks[index].occurrenceDate;
    final next = _copy();
    next.tasks[index] = task;
    next.validate();
    if (scope == RepeatScope.thisAndFuture) {
      _updateFutureTasks(data.tasks[index], task);
    }
    task.completedAt = task.status == TaskStatus.done
        ? (task.completedAt ?? DateTime.now())
        : null;
    data.tasks[index] = task;
    if (task.repeatRule != null && task.seriesId == null) _expandTask(task);
    _syncTask(task);
    changed();
  }

  void addProject(Project value) {
    final next = _copy();
    next.projects.add(value);
    next.validate();
    data.projects.add(value);
    changed();
  }

  void moveProject(String id, String? parentId) {
    final next = _copy();
    final p = next.projects.firstWhere(
      (x) => x.id == id,
      orElse: () => throw const FormatException('项目不存在'),
    );
    p.parentId = parentId;
    next.validate();
    project(id)!.parentId = parentId;
    changed();
  }

  void addEvent(CalendarEvent value) {
    final next = _copy();
    next.events.add(value);
    next.validate();
    data.events.add(value);
    _expandEvent(value);
    changed();
  }

  void setTaskStatus(String id, TaskStatus status) {
    final t = _task(id);
    t.status = status;
    t.completedAt = status == TaskStatus.done
        ? (t.completedAt ?? DateTime.now())
        : null;
    _syncTask(t);
    changed();
  }

  void _syncTask(Task task) {
    for (final n in data.nodes.where((x) => x.taskId == task.id)) {
      n.status = switch (task.status) {
        TaskStatus.done => NodeStatus.done,
        TaskStatus.doing => NodeStatus.doing,
        TaskStatus.waiting => NodeStatus.waiting,
        TaskStatus.cancelled => NodeStatus.skipped,
        TaskStatus.todo => NodeStatus.ready,
      };
      n.completedAt =
          task.status == TaskStatus.done || task.status == TaskStatus.cancelled
          ? (task.completedAt ?? DateTime.now())
          : null;
    }
    _refreshDependencies();
  }

  void completeEvent(String id) {
    final event = _event(id);
    if (event.completed || event.deletedAt != null) return;
    event.completed = true;
    if (event.actualMinutes == 0) {
      event.actualMinutes = event.end.difference(event.start).inMinutes;
    }
    if (event.taskId != null) {
      final task = _task(event.taskId!);
      final blocks = events.where((x) => x.taskId == task.id).toList();
      _recalculateActualMinutes(task.id);
      if (blocks.length == 1) {
        task.status = TaskStatus.done;
        task.completedAt = DateTime.now();
        _syncTask(task);
      }
    }
    changed();
  }

  void deleteTask(String id, {RepeatScope scope = RepeatScope.thisOnly}) {
    final task = _task(id);
    for (final value in data.tasks.where(
      (x) =>
          x.id == id ||
          (scope == RepeatScope.thisAndFuture &&
              task.seriesId != null &&
              x.seriesId == task.seriesId &&
              !(x.occurrenceDate ?? DateTime(1900)).isBefore(
                task.occurrenceDate ?? DateTime(1900),
              )),
    )) {
      value.deletedAt = DateTime.now();
    }
    changed();
  }

  void restoreTask(String id) {
    final t = _task(id);
    t.deletedAt = null;
    if (t.projectId != null &&
        (project(t.projectId) == null ||
            project(t.projectId)!.deletedAt != null)) {
      t.projectId = null;
    }
    changed();
  }

  void deleteEvent(String id, {RepeatScope scope = RepeatScope.thisOnly}) {
    final event = _event(id);
    event.deletedAt = DateTime.now();
    if (scope == RepeatScope.thisAndFuture && event.seriesId != null) {
      for (final value in data.events.where(
        (x) =>
            x.seriesId == event.seriesId &&
            !(x.occurrenceDate ?? x.start).isBefore(
              event.occurrenceDate ?? event.start,
            ),
      )) {
        value.deletedAt = event.deletedAt;
        _recalculateActualMinutes(value.taskId);
      }
    }
    _recalculateActualMinutes(event.taskId);
    changed();
  }

  void restoreEvent(String id) {
    final e = _event(id);
    e.deletedAt = null;
    if (e.projectId != null &&
        (project(e.projectId) == null ||
            project(e.projectId)!.deletedAt != null)) {
      e.projectId = null;
    }
    _recalculateActualMinutes(e.taskId);
    changed();
  }

  void _recalculateActualMinutes(String? taskId) {
    if (taskId == null) return;
    _task(taskId).actualMinutes = events
        .where((event) => event.taskId == taskId && event.completed)
        .fold(0, (sum, event) => sum + event.actualMinutes);
  }

  void addNode(FlowNode value) {
    final next = _copy();
    next.nodes.add(value);
    next.validate();
    data.nodes.add(value);
    if (value.taskId != null) {
      _syncTask(_task(value.taskId!));
    } else {
      _refreshDependencies();
    }
    if (preferenceFlag('workflowAutoLayout', false)) {
      autoLayout(value.projectId);
      return;
    }
    changed();
  }

  void addEdge(FlowEdge value) {
    final next = _copy();
    next.edges.add(value);
    next.validate();
    data.edges.add(value);
    _refreshDependencies();
    if (preferenceFlag('workflowAutoLayout', false)) {
      autoLayout(value.projectId);
      return;
    }
    changed();
  }

  void setNodeStatus(String id, NodeStatus status) {
    final node = _node(id);
    final manualUnlock =
        node.status == NodeStatus.locked && status == NodeStatus.ready;
    if (manualUnlock && !preferenceFlag('workflowAllowManualUnlock')) {
      throw const FormatException('不允许手动解锁节点');
    }
    if (status == NodeStatus.doing &&
        preferenceFlag('workflowCheckDependencies') &&
        !dependenciesSatisfied(node)) {
      throw const FormatException('前置节点尚未完成');
    }
    node.status = status;
    node.delayWaiting = false;
    node.completedAt = status == NodeStatus.done || status == NodeStatus.skipped
        ? DateTime.now()
        : null;
    if (node.taskId != null) {
      final task = _task(node.taskId!);
      task.status = switch (status) {
        NodeStatus.done => TaskStatus.done,
        NodeStatus.skipped => TaskStatus.cancelled,
        NodeStatus.doing => TaskStatus.doing,
        NodeStatus.waiting => TaskStatus.waiting,
        _ => TaskStatus.todo,
      };
      task.completedAt = task.status == TaskStatus.done
          ? (task.completedAt ?? DateTime.now())
          : null;
      for (final other in data.nodes.where((x) => x.taskId == task.id)) {
        other.status = status;
      }
    }
    _refreshDependencies(manuallyUnlocked: manualUnlock ? node.id : null);
    changed();
  }

  bool dependenciesSatisfied(
    FlowNode node, {
    DateTime? now,
    bool ignoreDelay = false,
  }) {
    final clock = now ?? DateTime.now();
    final incoming = data.edges.where(
      (edge) => edge.active && edge.targetId == node.id,
    );
    bool satisfied(FlowEdge edge) {
      final source = _node(edge.sourceId);
      final status = source.status;
      if (source.kind == NodeKind.condition &&
          source.selectedBranchEdgeId != edge.id) {
        return false;
      }
      if (!ignoreDelay &&
          edge.availableAt != null &&
          clock.isBefore(edge.availableAt!)) {
        return false;
      }
      if (!ignoreDelay &&
          edge.delayMinutes > 0 &&
          (source.completedAt == null ||
              clock.isBefore(
                source.completedAt!.add(Duration(minutes: edge.delayMinutes)),
              ))) {
        return false;
      }
      return status == NodeStatus.done ||
          (status == NodeStatus.skipped &&
              preferenceFlag('workflowSkipCompletes'));
    }

    return incoming.isEmpty ||
        (node.anyPredecessor
            ? incoming.any(satisfied)
            : incoming.every(satisfied));
  }

  void _refreshDependencies({String? manuallyUnlocked, DateTime? now}) {
    // A single pass only changes readiness; it never executes a node or loop.
    for (final node in data.nodes) {
      if (node.id == manuallyUnlocked) continue;
      if (node.status != NodeStatus.locked &&
          node.status != NodeStatus.ready &&
          !node.delayWaiting) {
        continue;
      }
      final ready =
          !preferenceFlag('workflowCheckDependencies') ||
          dependenciesSatisfied(node, now: now);
      if (!ready) {
        node.delayWaiting = dependenciesSatisfied(
          node,
          now: now,
          ignoreDelay: true,
        );
        node.status = node.delayWaiting
            ? NodeStatus.waiting
            : NodeStatus.locked;
      } else if (node.status != NodeStatus.locked ||
          preferenceFlag('workflowAutoUnlock')) {
        node.status = NodeStatus.ready;
        node.delayWaiting = false;
      }
    }
  }

  void autoLayout(String projectId) {
    final nodes = data.nodes.where((x) => x.projectId == projectId).toList();
    final remaining = nodes.map((x) => x.id).toSet();
    final placed = <String>{};
    var column = 0;
    while (remaining.isNotEmpty) {
      var layer = nodes
          .where(
            (n) =>
                remaining.contains(n.id) &&
                data.edges
                    .where((e) => e.active && e.targetId == n.id)
                    .every((e) => placed.contains(e.sourceId)),
          )
          .toList();
      if (layer.isEmpty) {
        layer = [nodes.firstWhere((n) => remaining.contains(n.id))];
      }
      for (var row = 0; row < layer.length; row++) {
        layer[row].x = 40.0 + column * 250;
        layer[row].y = 40.0 + row * 150;
        remaining.remove(layer[row].id);
        placed.add(layer[row].id);
      }
      column++;
    }
    changed();
  }

  void capture(String text) {
    if (text.trim().isEmpty) throw const FormatException('内容不能为空');
    data.captures.add(
      Capture(id: newId(), text: text.trim(), createdAt: DateTime.now()),
    );
    changed();
  }

  void markAllRead() {
    for (final n in data.notices) {
      n.read = true;
    }
    changed();
  }

  String exportJson() =>
      const JsonEncoder.withIndent('  ').convert(data.toJson());
  Future<void> importJson(String source) async {
    FlowData next;
    try {
      next = FlowData.fromJson(jsonDecode(source) as Map<String, dynamic>);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('无效的 JSON 数据');
    }
    final requestedRevision = _revision;
    final operation = _pending.then((_) async {
      if (_revision != requestedRevision) {
        throw StateError('导入期间数据已修改，请重试导入');
      }
      await _save?.call(next);
      if (_revision != requestedRevision) {
        // Keep edits made while the import was writing, including on disk.
        await _save?.call(_copy());
        throw StateError('导入期间数据已修改，请重试导入');
      }
      data = next;
      _revision++;
      _importGeneration++;
      error = null;
      _notify();
    });
    // The caller sees import failures, while the shared save queue stays usable.
    _pending = operation.then<void>(
      (_) {},
      onError: (Object e, StackTrace _) {
        error = '导入失败：$e';
        _notify();
      },
    );
    await operation;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
