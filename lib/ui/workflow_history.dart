import 'dart:convert';
import '../domain/models.dart';
import '../domain/store.dart';

/// Captures a graph and its linked tasks without overwriting other projects.
class WorkflowHistory {
  final List<_GraphSnapshot> _undo = [], _redo = [];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void clear() {
    _undo.clear();
    _redo.clear();
  }

  void checkpoint(FlowStore store, String projectId) {
    _undo.add(_GraphSnapshot.capture(store, projectId));
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  void restore(FlowStore store, String projectId, {bool redo = false}) {
    final source = redo ? _redo : _undo, destination = redo ? _undo : _redo;
    if (source.isEmpty) return;
    destination.add(_GraphSnapshot.capture(store, projectId));
    source.removeLast().restore(store, projectId);
  }
}

class _GraphSnapshot {
  _GraphSnapshot(this.nodes, this.edges, this.tasks);
  final List<FlowNode> nodes;
  final List<FlowEdge> edges;
  final List<Task> tasks;
  static Map<String, dynamic> clone(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  factory _GraphSnapshot.capture(FlowStore store, String projectId) {
    final nodes = store.data.nodes
        .where((n) => n.projectId == projectId)
        .toList();
    final ids = nodes.map((n) => n.taskId).whereType<String>().toSet();
    return _GraphSnapshot(
      nodes.map((n) => FlowNode.fromJson(clone(n.toJson()))).toList(),
      store.data.edges
          .where((e) => e.projectId == projectId)
          .map((e) => FlowEdge.fromJson(clone(e.toJson())))
          .toList(),
      store.data.tasks
          .where((t) => ids.contains(t.id))
          .map((t) => Task.fromJson(clone(t.toJson())))
          .toList(),
    );
  }
  void restore(FlowStore store, String projectId) {
    final taskIds = {
      ...store.data.nodes
          .where((n) => n.projectId == projectId)
          .map((n) => n.taskId)
          .whereType<String>(),
      ...tasks.map((t) => t.id),
    };
    store.data.nodes.removeWhere((n) => n.projectId == projectId);
    store.data.edges.removeWhere((e) => e.projectId == projectId);
    store.data.nodes.addAll(
      nodes.map((n) => FlowNode.fromJson(clone(n.toJson()))),
    );
    store.data.edges.addAll(
      edges.map((e) => FlowEdge.fromJson(clone(e.toJson()))),
    );
    for (final task in tasks) {
      store.data.tasks.removeWhere((t) => t.id == task.id);
      store.data.tasks.add(Task.fromJson(clone(task.toJson())));
    }
    final retained = store.data.nodes.map((n) => n.taskId).toSet();
    store.data.tasks.removeWhere(
      (t) =>
          taskIds.contains(t.id) &&
          !tasks.any((old) => old.id == t.id) &&
          !retained.contains(t.id) &&
          !store.data.events.any((event) => event.taskId == t.id),
    );
    store.changed();
  }
}
