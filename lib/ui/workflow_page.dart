import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/services.dart';
import 'workflow_history.dart';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/store.dart';
import 'editors.dart';
import 'theme.dart';

class WorkflowPage extends StatefulWidget {
  const WorkflowPage({super.key, required this.store, this.projectId});
  final FlowStore store;
  final String? projectId;
  @override
  State<WorkflowPage> createState() => _WorkflowPageState();
}

class _WorkflowPageState extends State<WorkflowPage> {
  late String? projectId;
  String? selected, connecting;
  final transform = TransformationController();
  final history = WorkflowHistory();
  final selection = <String>{};
  List<Map<String, dynamic>> copiedNodes = [], copiedEdges = [];
  List<Map<String, dynamic>> copiedTasks = [];
  bool selecting = false;
  Offset? selectionStart, selectionEnd;
  Timer? refreshTimer;
  final canvasKey = GlobalKey();
  Offset? connectionPosition;
  Size viewportSize = const Size(800, 600);
  @override
  void initState() {
    super.initState();
    projectId =
        widget.store.projects.any((project) => project.id == widget.projectId)
        ? widget.projectId
        : widget.store.projects.firstOrNull?.id;
    refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      widget.store.refreshWorkflow();
    });
    final zoom = widget.store.data.preferences['workflowZoom'];
    final scale = zoom is int && zoom >= 25 && zoom <= 250 ? zoom / 100 : 1.0;
    transform.value = Matrix4.identity()..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    transform.dispose();
    super.dispose();
  }

  List<FlowNode> get nodes => widget.store.data.nodes
      .where(
        (n) =>
            n.projectId == projectId &&
            !widget.store.data.nodes.any(
              (group) => group.id == n.groupId && group.collapsed,
            ) &&
            (widget.store.preferenceFlag('workflowShowMilestones') ||
                n.kind != NodeKind.milestone),
      )
      .toList();
  List<FlowEdge> get edges =>
      widget.store.data.edges.where((e) => e.projectId == projectId).toList();
  void checkpoint() {
    if (projectId != null) history.checkpoint(widget.store, projectId!);
  }

  void undo(bool redo) {
    if (projectId == null) return;
    history.restore(widget.store, projectId!, redo: redo);
    setState(() {
      selected = null;
      selection.clear();
    });
  }

  void copySelection() {
    final ids = {...selection, ?selected};
    // A group copy includes its members even when they are collapsed.
    ids.addAll(
      widget.store.data.nodes
          .where((n) => ids.contains(n.groupId))
          .map((n) => n.id)
          .toList(),
    );
    copiedNodes = widget.store.data.nodes
        .where((n) => ids.contains(n.id))
        .map((n) => Map<String, dynamic>.from(n.toJson()))
        .toList();
    copiedEdges = edges
        .where((e) => ids.contains(e.sourceId) && ids.contains(e.targetId))
        .map((e) => Map<String, dynamic>.from(e.toJson()))
        .toList();
    final taskIds = copiedNodes
        .map((n) => n['taskId'])
        .whereType<String>()
        .toSet();
    copiedTasks = widget.store.data.tasks
        .where((t) => taskIds.contains(t.id))
        .map((t) => Map<String, dynamic>.from(t.toJson()))
        .toList();
    setState(() {});
  }

  void pasteSelection() {
    if (projectId == null || copiedNodes.isEmpty) return;
    checkpoint();
    final ids = {
      for (final n in copiedNodes) n['id'] as String: widget.store.newId(),
    };
    final edgeIds = {
      for (final e in copiedEdges) e['id'] as String: widget.store.newId(),
    };
    final taskIds = {
      for (final t in copiedTasks) t['id'] as String: widget.store.newId(),
    };
    for (final original in copiedTasks) {
      final value = Map<String, dynamic>.from(original);
      value['id'] = taskIds[original['id']];
      value['projectId'] = projectId;
      value['parentId'] = taskIds[original['parentId']];
      widget.store.data.tasks.add(Task.fromJson(value));
    }
    for (final original in copiedNodes) {
      final value = Map<String, dynamic>.from(original);
      value['id'] = ids[original['id']];
      value['projectId'] = projectId;
      value['taskId'] = taskIds[original['taskId']];
      value['groupId'] = ids[original['groupId']];
      value['selectedBranchEdgeId'] = edgeIds[original['selectedBranchEdgeId']];
      value['x'] = (value['x'] as num) + 40;
      value['y'] = (value['y'] as num) + 40;
      widget.store.data.nodes.add(FlowNode.fromJson(value));
    }
    for (final original in copiedEdges) {
      final value = Map<String, dynamic>.from(original);
      value['id'] = edgeIds[original['id']];
      value['projectId'] = projectId;
      value['sourceId'] = ids[original['sourceId']];
      value['targetId'] = ids[original['targetId']];
      widget.store.data.edges.add(FlowEdge.fromJson(value));
    }
    widget.store.refreshWorkflow();
    widget.store.changed();
    setState(() {
      selection
        ..clear()
        ..addAll(ids.values);
      selected = ids.values.first;
    });
  }

  void deleteSelection() {
    final ids = {...selection, ?selected};
    if (ids.isEmpty) return;
    checkpoint();
    widget.store.data.nodes.removeWhere((n) => ids.contains(n.id));
    widget.store.data.edges.removeWhere(
      (e) => ids.contains(e.sourceId) || ids.contains(e.targetId),
    );
    for (final n in widget.store.data.nodes) {
      if (ids.contains(n.groupId)) n.groupId = null;
      if (n.selectedBranchEdgeId != null &&
          !widget.store.data.edges.any((e) => e.id == n.selectedBranchEdgeId)) {
        n.selectedBranchEdgeId = null;
      }
    }
    widget.store.refreshWorkflow();
    widget.store.changed();
    setState(() {
      selected = null;
      selection.clear();
    });
  }

  Future<void> createNode() async {
    if (projectId == null) {
      await editProject(context, widget.store);
      if (mounted) {
        setState(() => projectId = widget.store.projects.firstOrNull?.id);
      }
      return;
    }
    var title = '';
    NodeKind kind =
        NodeKind.values
            .where(
              (kind) =>
                  kind.name ==
                  widget.store.data.preferences['workflowDefaultKind'],
            )
            .firstOrNull ??
        NodeKind.task;
    final form = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('添加节点'),
          content: SizedBox(
            width: 350,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    onChanged: (value) => title = value,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '节点名称'),
                    validator: requiredTitle,
                  ),
                  const SizedBox(height: 18),
                  FlowSelect<NodeKind>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: '类型'),
                    items: NodeKind.values
                        .map(
                          (k) => DropdownMenuItem(
                            value: k,
                            child: Text(kindLabels[k.index]),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => kind = v!),
                  ),
                ],
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
                if (!form.currentState!.validate()) return;
                checkpoint();
                String? taskId;
                if (kind == NodeKind.task &&
                    widget.store.preferenceFlag('workflowAutoTodo')) {
                  taskId = widget.store.newId();
                  widget.store.addTask(
                    Task(
                      id: taskId,
                      title: title.trim(),
                      projectId: projectId,
                      priority: widget.store.preferencePriority(
                        'workflowDefaultPriority',
                      ),
                      estimateMinutes: widget.store.preferenceMinutes(
                        'workflowEstimateMinutes',
                      ),
                    ),
                  );
                }
                widget.store.addNode(
                  FlowNode(
                    id: widget.store.newId(),
                    projectId: projectId!,
                    title: title.trim(),
                    kind: kind,
                    taskId: taskId,
                    x: 70 + nodes.length % 4 * 250,
                    y: 80 + (nodes.length ~/ 4) * 160,
                  ),
                );
                Navigator.pop(context);
              },
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  void connectTo(String target) {
    if (connecting == null || connecting == target) return;
    try {
      checkpoint();
      widget.store.addEdge(
        FlowEdge(
          id: widget.store.newId(),
          projectId: projectId!,
          sourceId: connecting!,
          targetId: target,
        ),
      );
    } catch (e) {
      showFailure(context, e);
    }
    setState(() => connecting = null);
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyC, control: true):
          copySelection,
      const SingleActivator(LogicalKeyboardKey.keyV, control: true):
          pasteSelection,
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
          undo(false),
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): () =>
          undo(true),
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
          undo(true),
    },
    child: Focus(
      autofocus: true,
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => buildCanvas(context),
      ),
    ),
  );

  Widget buildCanvas(BuildContext context) {
    if (!widget.store.projects.any((project) => project.id == projectId)) {
      projectId = widget.store.projects.firstOrNull?.id;
      selected = null;
      connecting = null;
      history.clear();
      selection.clear();
    }
    final node = nodes.where((n) => n.id == selected).firstOrNull;
    final desktop = MediaQuery.sizeOf(context).width >= 1150;
    return Column(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 230,
              child: FlowSelect<String>(
                key: ValueKey(projectId),
                initialValue: projectId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '项目'),
                items: widget.store.projects
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.title, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() {
                  projectId = v;
                  selected = null;
                  connecting = null;
                  history.clear();
                  selection.clear();
                }),
              ),
            ),
            FilledButton.icon(
              onPressed: createNode,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加节点'),
            ),
            OutlinedButton.icon(
              onPressed: projectId == null
                  ? null
                  : () {
                      checkpoint();
                      widget.store.autoLayout(projectId!);
                    },
              icon: const Icon(Icons.auto_awesome_mosaic_outlined, size: 17),
              label: const Text('自动布局'),
            ),
            IconButton(
              onPressed: !history.canUndo ? null : () => undo(false),
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              onPressed: !history.canRedo ? null : () => undo(true),
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              onPressed: () => setState(() => selecting = !selecting),
              isSelected: selecting,
              icon: const Icon(Icons.select_all),
            ),
            IconButton(
              onPressed: selection.isEmpty && selected == null
                  ? null
                  : copySelection,
              icon: const Icon(Icons.copy),
            ),
            IconButton(
              onPressed: copiedNodes.isEmpty ? null : pasteSelection,
              icon: const Icon(Icons.paste),
            ),
            IconButton(
              onPressed: selection.isEmpty && selected == null
                  ? null
                  : deleteSelection,
              icon: const Icon(Icons.delete_outline),
            ),
            if (connecting != null)
              TextButton(
                onPressed: () => setState(() => connecting = null),
                child: const Text('取消连线'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Panel(
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              viewportSize = constraints.biggest;
                              return InteractiveViewer(
                                key: canvasKey,
                                transformationController: transform,
                                constrained: false,
                                panEnabled: !selecting,
                                minScale: .25,
                                maxScale: 2.5,
                                boundaryMargin: const EdgeInsets.all(600),
                                child: SizedBox(
                                  width: math.max(
                                    2200,
                                    nodes.fold<double>(
                                      0,
                                      (v, n) => math.max(v, n.x + 350),
                                    ),
                                  ),
                                  height: math.max(
                                    1600,
                                    nodes.fold<double>(
                                      0,
                                      (v, n) => math.max(v, n.y + 250),
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: CustomPaint(
                                          painter: GraphPainter(
                                            nodes,
                                            edges,
                                            showLabels: widget.store
                                                .preferenceFlag(
                                                  'workflowShowEdgeLabels',
                                                ),
                                            dotColor:
                                                Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? Theme.of(context).dividerColor
                                                : const Color(0xffdee7f5),
                                            edgeColor: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      if (selecting)
                                        Positioned.fill(
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onPanStart: (d) => setState(() {
                                              selectionStart = d.localPosition;
                                              selectionEnd = d.localPosition;
                                            }),
                                            onPanUpdate: (d) => setState(
                                              () => selectionEnd =
                                                  d.localPosition,
                                            ),
                                            onPanEnd: (_) => setState(() {
                                              final rect = Rect.fromPoints(
                                                selectionStart!,
                                                selectionEnd!,
                                              );
                                              selection
                                                ..clear()
                                                ..addAll(
                                                  nodes
                                                      .where(
                                                        (n) => rect.overlaps(
                                                          Rect.fromLTWH(
                                                            n.x,
                                                            n.y,
                                                            210,
                                                            nodeHeight(n),
                                                          ),
                                                        ),
                                                      )
                                                      .map((n) => n.id),
                                                );
                                              selected = selection.firstOrNull;
                                              selectionStart = null;
                                              selectionEnd = null;
                                            }),
                                          ),
                                        ),
                                      if (selectionStart != null &&
                                          selectionEnd != null)
                                        Positioned.fromRect(
                                          rect: Rect.fromPoints(
                                            selectionStart!,
                                            selectionEnd!,
                                          ),
                                          child: IgnorePointer(
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withValues(alpha: .1),
                                                border: Border.all(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ...nodes.map(
                                        (n) => Positioned(
                                          left: n.x,
                                          top: n.y,
                                          width: 210,
                                          height: nodeHeight(n),
                                          child: GestureDetector(
                                            onPanStart: (_) => checkpoint(),
                                            onPanUpdate: (d) => setState(() {
                                              final ids =
                                                  selection.contains(n.id)
                                                  ? selection
                                                  : {n.id};
                                              final moving = widget
                                                  .store
                                                  .data
                                                  .nodes
                                                  .where(
                                                    (item) =>
                                                        ids.contains(item.id) ||
                                                        ids.contains(
                                                          item.groupId,
                                                        ),
                                                  );
                                              final dx = math.max(
                                                -moving
                                                    .map((item) => item.x)
                                                    .reduce(math.min),
                                                d.delta.dx,
                                              );
                                              final dy = math.max(
                                                -moving
                                                    .map((item) => item.y)
                                                    .reduce(math.min),
                                                d.delta.dy,
                                              );
                                              for (final item in moving) {
                                                item.x += dx;
                                                item.y += dy;
                                              }
                                            }),
                                            onPanEnd: (_) =>
                                                widget.store.changed(),
                                            onTap: () {
                                              if (connecting != null) {
                                                connectTo(n.id);
                                                return;
                                              }
                                              setState(() {
                                                final multiple =
                                                    HardwareKeyboard
                                                        .instance
                                                        .isControlPressed ||
                                                    HardwareKeyboard
                                                        .instance
                                                        .isShiftPressed;
                                                if (!multiple) {
                                                  selection.clear();
                                                }
                                                if (multiple &&
                                                    selection.contains(n.id)) {
                                                  selection.remove(n.id);
                                                } else {
                                                  selection.add(n.id);
                                                }
                                                selected = n.id;
                                              });
                                              if (!desktop) {
                                                openEditor(
                                                  context,
                                                  nodeDetail(n),
                                                );
                                              }
                                            },
                                            child: draggableNode(
                                              n,
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: nodeColor(
                                                    n,
                                                  ).withValues(alpha: .09),
                                                  borderRadius:
                                                      BorderRadius.circular(9),
                                                  border: Border.all(
                                                    color:
                                                        selection.contains(
                                                              n.id,
                                                            ) ||
                                                            selected == n.id
                                                        ? Theme.of(
                                                            context,
                                                          ).colorScheme.primary
                                                        : nodeColor(
                                                            n,
                                                          ).withValues(
                                                            alpha: .5,
                                                          ),
                                                    width:
                                                        selection.contains(
                                                              n.id,
                                                            ) ||
                                                            selected == n.id
                                                        ? 2
                                                        : 1,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      switch (n.kind) {
                                                        NodeKind.condition =>
                                                          Icons.call_split,
                                                        NodeKind.delay =>
                                                          Icons.hourglass_empty,
                                                        NodeKind.group =>
                                                          Icons.folder_outlined,
                                                        NodeKind.link =>
                                                          Icons.open_in_new,
                                                        NodeKind.milestone =>
                                                          Icons.flag_outlined,
                                                        NodeKind.note =>
                                                          Icons.notes,
                                                        _ => Icons.task_alt,
                                                      },
                                                      color: nodeColor(n),
                                                      size: 23,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          Text(
                                                            n.title,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            height: 8,
                                                          ),
                                                          Text(
                                                            nodeLabels[n
                                                                .status
                                                                .index],
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: nodeColor(
                                                                n,
                                                              ),
                                                            ),
                                                          ),
                                                          if (widget.store
                                                                  .preferenceFlag(
                                                                    'workflowShowDescription',
                                                                  ) &&
                                                              n
                                                                  .description
                                                                  .isNotEmpty)
                                                            Text(
                                                              n.description,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: Theme.of(context)
                                                                    .colorScheme
                                                                    .onSurfaceVariant,
                                                              ),
                                                            ),
                                                          if (widget.store
                                                                  .preferenceFlag(
                                                                    'workflowShowEstimate',
                                                                  ) &&
                                                              linkedTask(n) !=
                                                                  null)
                                                            Text(
                                                              '${linkedTask(n)!.estimateMinutes} 分钟',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: Theme.of(context)
                                                                    .colorScheme
                                                                    .onSurfaceVariant,
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                    GestureDetector(
                                                      onPanStart: (d) =>
                                                          setState(() {
                                                            connecting = n.id;
                                                            connectionPosition =
                                                                d.globalPosition;
                                                          }),
                                                      onPanUpdate: (d) =>
                                                          connectionPosition =
                                                              d.globalPosition,
                                                      onPanEnd: (_) {
                                                        final box =
                                                            canvasKey
                                                                    .currentContext
                                                                    ?.findRenderObject()
                                                                as RenderBox?;
                                                        if (box != null &&
                                                            connectionPosition !=
                                                                null) {
                                                          final point =
                                                              transform.toScene(
                                                                box.globalToLocal(
                                                                  connectionPosition!,
                                                                ),
                                                              );
                                                          final target = nodes
                                                              .where(
                                                                (node) =>
                                                                    node.id !=
                                                                        n.id &&
                                                                    Rect.fromLTWH(
                                                                      node.x,
                                                                      node.y,
                                                                      210,
                                                                      nodeHeight(
                                                                        node,
                                                                      ),
                                                                    ).contains(
                                                                      point,
                                                                    ),
                                                              )
                                                              .firstOrNull;
                                                          if (target != null) {
                                                            connectTo(
                                                              target.id,
                                                            );
                                                          } else {
                                                            setState(
                                                              () => connecting =
                                                                  null,
                                                            );
                                                          }
                                                        }
                                                        connectionPosition =
                                                            null;
                                                      },
                                                      onTap: () {
                                                        if (connecting !=
                                                            null) {
                                                          connectTo(n.id);
                                                        } else {
                                                          setState(
                                                            () => connecting =
                                                                n.id,
                                                          );
                                                        }
                                                      },
                                                      child: Container(
                                                        width: 18,
                                                        height: 24,
                                                        alignment:
                                                            Alignment.center,
                                                        child: Icon(
                                                          Icons.circle_outlined,
                                                          size: 13,
                                                          color:
                                                              connecting == n.id
                                                              ? Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary
                                                              : Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
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
                            },
                          ),
                        ),
                        Positioned(
                          right: 14,
                          bottom: 14,
                          child: SizedBox(
                            width: 160,
                            height: 110,
                            child: GestureDetector(
                              onTapDown: (d) {
                                final width = math.max(
                                  2200.0,
                                  nodes.fold<double>(
                                    0,
                                    (v, n) => math.max(v, n.x + 350),
                                  ),
                                );
                                final height = math.max(
                                  1600.0,
                                  nodes.fold<double>(
                                    0,
                                    (v, n) => math.max(v, n.y + 250),
                                  ),
                                );
                                final scale = transform.value
                                    .getMaxScaleOnAxis();
                                transform.value = Matrix4.identity()
                                  ..translateByDouble(
                                    -d.localPosition.dx / 160 * width * scale +
                                        viewportSize.width / 2,
                                    -d.localPosition.dy / 110 * height * scale +
                                        viewportSize.height / 2,
                                    0,
                                    1,
                                  )
                                  ..scaleByDouble(scale, scale, scale, 1);
                              },
                              child: AnimatedBuilder(
                                animation: transform,
                                builder: (context, _) => CustomPaint(
                                  painter: WorkflowMinimap(
                                    nodes,
                                    edges,
                                    Theme.of(context).colorScheme,
                                    viewport: Rect.fromPoints(
                                      transform.toScene(Offset.zero),
                                      transform.toScene(
                                        viewportSize.bottomRight(Offset.zero),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 14,
                          top: 14,
                          child: Card(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () =>
                                      transform.value = transform.value.clone()
                                        ..scaleByDouble(.8, .8, .8, 1),
                                  icon: const Icon(Icons.remove, size: 18),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      transform.value = Matrix4.identity(),
                                  child: const Text('100%'),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      transform.value = transform.value.clone()
                                        ..scaleByDouble(1.25, 1.25, 1.25, 1),
                                  icon: const Icon(Icons.add, size: 18),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (desktop && node != null) ...[
                const SizedBox(width: 18),
                SizedBox(
                  width: 300,
                  child: Panel(
                    padding: EdgeInsets.zero,
                    child: nodeDetail(node),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Color nodeColor(FlowNode n) => switch (n.status) {
    NodeStatus.done || NodeStatus.skipped => palette[2],
    NodeStatus.doing => blue,
    NodeStatus.locked => muted,
    _ => palette[1],
  };
  Widget draggableNode(FlowNode node, Widget child) {
    final task = linkedTask(node);
    if (task == null) return child;
    return LongPressDraggable<Task>(
      data: task,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 210, child: Panel(child: Text(node.title))),
      ),
      childWhenDragging: Opacity(opacity: .4, child: child),
      child: child,
    );
  }

  Task? linkedTask(FlowNode node) => widget.store.data.tasks
      .where((task) => task.id == node.taskId)
      .firstOrNull;
  double nodeHeight(FlowNode node) =>
      92 +
      (widget.store.preferenceFlag('workflowShowDescription') &&
              node.description.isNotEmpty
          ? 16
          : 0) +
      (widget.store.preferenceFlag('workflowShowEstimate') &&
              linkedTask(node) != null
          ? 16
          : 0);
  Widget nodeDetail(FlowNode n) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(22),
      children: [
        SectionTitle(n.title),
        Tag(kindLabels[n.kind.index], color: nodeColor(n)),
        const SizedBox(height: 24),
        TextFormField(
          key: ValueKey('title-${n.id}'),
          initialValue: n.title,
          decoration: const InputDecoration(labelText: '节点名称'),
          onFieldSubmitted: (value) {
            if (value.trim().isEmpty) return;
            checkpoint();
            n.title = value.trim();
            final task = linkedTask(n);
            if (task != null) task.title = n.title;
            widget.store.changed();
          },
        ),
        const SizedBox(height: 20),
        FlowSelect<NodeKind>(
          key: ValueKey('kind-${n.id}-${n.kind}'),
          initialValue: n.kind,
          decoration: const InputDecoration(labelText: '类型'),
          items: NodeKind.values
              .map(
                (kind) => DropdownMenuItem(
                  value: kind,
                  child: Text(kindLabels[kind.index]),
                ),
              )
              .toList(),
          onChanged: (kind) {
            if (n.kind == NodeKind.group &&
                kind != NodeKind.group &&
                widget.store.data.nodes.any(
                  (member) => member.groupId == n.id,
                )) {
              showFailure(context, const FormatException('请先移出分组中的节点'));
              return;
            }
            checkpoint();
            n.kind = kind!;
            if (n.kind == NodeKind.task &&
                n.taskId == null &&
                widget.store.preferenceFlag('workflowAutoTodo')) {
              final task = Task(
                id: widget.store.newId(),
                title: n.title,
                projectId: n.projectId,
                priority: widget.store.preferencePriority(
                  'workflowDefaultPriority',
                ),
                estimateMinutes: widget.store.preferenceMinutes(
                  'workflowEstimateMinutes',
                ),
              );
              widget.store.addTask(task);
              n.taskId = task.id;
            }
            widget.store.changed();
          },
        ),
        const SizedBox(height: 20),
        if (n.kind == NodeKind.condition) ...[
          FlowSelect<String>(
            key: ValueKey('branch-${n.id}-${n.selectedBranchEdgeId}'),
            initialValue: n.selectedBranchEdgeId,
            decoration: const InputDecoration(labelText: '选择分支'),
            items: edges
                .where((e) => e.sourceId == n.id)
                .map(
                  (e) => DropdownMenuItem(
                    value: e.id,
                    child: Text(
                      e.label.isEmpty
                          ? widget.store.data.nodes
                                .firstWhere((node) => node.id == e.targetId)
                                .title
                          : e.label,
                    ),
                  ),
                )
                .toList(),
            onChanged: (id) {
              if (id == null) return;
              checkpoint();
              widget.store.selectBranch(n.id, id);
            },
          ),
          const SizedBox(height: 20),
        ],
        if (n.kind == NodeKind.group) ...[
          OutlinedButton.icon(
            onPressed: () {
              checkpoint();
              n.collapsed = !n.collapsed;
              widget.store.changed();
              setState(() {});
            },
            icon: Icon(n.collapsed ? Icons.unfold_more : Icons.unfold_less),
            label: Text(n.collapsed ? '展开分组' : '折叠分组'),
          ),
          const SizedBox(height: 20),
        ] else ...[
          FlowSelect<String>(
            key: ValueKey('group-${n.id}-${n.groupId}'),
            initialValue: n.groupId ?? '',
            decoration: const InputDecoration(labelText: '分组'),
            items: [
              const DropdownMenuItem(value: '', child: Text('无')),
              ...widget.store.data.nodes
                  .where(
                    (group) =>
                        group.projectId == projectId &&
                        group.kind == NodeKind.group &&
                        group.id != n.id,
                  )
                  .map(
                    (group) => DropdownMenuItem(
                      value: group.id,
                      child: Text(group.title),
                    ),
                  ),
            ],
            onChanged: (id) {
              checkpoint();
              n.groupId = id == '' ? null : id;
              widget.store.changed();
              setState(() {});
            },
          ),
          const SizedBox(height: 20),
        ],
        if (n.kind == NodeKind.link) ...[
          FlowSelect<String>(
            key: ValueKey('target-${n.id}-${n.targetProjectId}'),
            initialValue: n.targetProjectId,
            decoration: const InputDecoration(labelText: '目标项目'),
            items: widget.store.projects
                .map((p) => DropdownMenuItem(value: p.id, child: Text(p.title)))
                .toList(),
            onChanged: (id) {
              checkpoint();
              n.targetProjectId = id;
              widget.store.changed();
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: n.targetProjectId == null
                ? null
                : () {
                    setState(() {
                      projectId = n.targetProjectId;
                      selected = null;
                      selection.clear();
                      history.clear();
                      transform.value = Matrix4.identity();
                    });
                  },
            child: const Text('打开工作流'),
          ),
          const SizedBox(height: 20),
        ],
        FlowSelect<NodeStatus>(
          key: ValueKey('${n.id}-${n.status}'),
          initialValue: n.status,
          decoration: const InputDecoration(labelText: '节点状态'),
          items: NodeStatus.values
              .map(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(nodeLabels[s.index]),
                ),
              )
              .toList(),
          onChanged: (s) {
            try {
              checkpoint();
              widget.store.setNodeStatus(n.id, s!);
            } catch (error) {
              showFailure(context, error);
            }
          },
        ),
        const SizedBox(height: 20),
        FlowSelect<bool>(
          key: ValueKey('${n.id}-${n.anyPredecessor}'),
          initialValue: n.anyPredecessor,
          decoration: const InputDecoration(labelText: '前置汇合逻辑'),
          items: const [
            DropdownMenuItem(value: false, child: Text('AND · 全部满足')),
            DropdownMenuItem(value: true, child: Text('OR · 任一满足')),
          ],
          onChanged: (v) {
            checkpoint();
            n.anyPredecessor = v!;
            widget.store.setNodeStatus(n.id, n.status);
          },
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => setState(() => connecting = n.id),
          icon: const Icon(Icons.add_link),
          label: const Text('连接到节点'),
        ),
        if (n.taskId != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              final task = widget.store.data.tasks
                  .where((t) => t.id == n.taskId)
                  .firstOrNull;
              if (task != null) {
                checkpoint();
                openEditor(
                  context,
                  TaskEditor(store: widget.store, task: task),
                );
              }
            },
            child: const Text('编辑关联任务'),
          ),
        ],
        const SizedBox(height: 24),
        const SectionTitle('连接'),
        ...edges
            .where((e) => e.sourceId == n.id)
            .map(
              (e) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  nodes.where((x) => x.id == e.targetId).firstOrNull?.title ??
                      '',
                ),
                subtitle: widget.store.preferenceFlag('workflowShowEdgeLabels')
                    ? Text(e.label)
                    : null,
                trailing: IconButton(
                  onPressed: () {
                    checkpoint();
                    widget.store.data.edges.remove(e);
                    if (n.selectedBranchEdgeId == e.id) {
                      n.selectedBranchEdgeId = null;
                    }
                    widget.store.setNodeStatus(n.id, n.status);
                  },
                  icon: const Icon(Icons.link_off, size: 18),
                ),
                onTap: () async {
                  final text = TextEditingController(text: e.label);
                  final delay = TextEditingController(
                    text: '${e.delayMinutes}',
                  );
                  final targetTime = TextEditingController(
                    text: e.availableAt?.toIso8601String() ?? '',
                  );
                  final form = GlobalKey<FormState>();
                  await showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('连线'),
                      content: Form(
                        key: form,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextFormField(
                              controller: text,
                              decoration: const InputDecoration(
                                labelText: '连线名称',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: delay,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '延迟（分钟）',
                              ),
                              validator: (value) =>
                                  int.tryParse(value ?? '') == null ||
                                      int.parse(value!) < 0
                                  ? '请输入非负整数'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: targetTime,
                              decoration: const InputDecoration(
                                labelText: '目标时间',
                              ),
                              validator: (value) =>
                                  value != null &&
                                      value.isNotEmpty &&
                                      DateTime.tryParse(value) == null
                                  ? '请输入有效日期时间'
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () {
                            if (!form.currentState!.validate()) return;
                            checkpoint();
                            e.label = text.text;
                            e.delayMinutes = int.parse(delay.text);
                            e.availableAt = DateTime.tryParse(targetTime.text);
                            widget.store.refreshWorkflow();
                            widget.store.changed();
                            Navigator.pop(context);
                          },
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  );
                  text.dispose();
                  delay.dispose();
                  targetTime.dispose();
                },
              ),
            ),
      ],
    ),
  );
}

class GraphPainter extends CustomPainter {
  GraphPainter(
    this.nodes,
    this.edges, {
    this.showLabels = true,
    this.dotColor = const Color(0xffdee7f5),
    this.edgeColor = muted,
  });
  final bool showLabels;
  final Color dotColor, edgeColor;
  final List<FlowNode> nodes;
  final List<FlowEdge> edges;
  @override
  void paint(Canvas canvas, Size size) {
    final dots = Paint()..color = dotColor;
    for (double x = 10; x < size.width; x += 20) {
      for (double y = 10; y < size.height; y += 20) {
        canvas.drawCircle(Offset(x, y), .7, dots);
      }
    }
    for (final e in edges) {
      final a = nodes.where((n) => n.id == e.sourceId).firstOrNull;
      final b = nodes.where((n) => n.id == e.targetId).firstOrNull;
      if (a == null || b == null) continue;
      final start = Offset(a.x + 210, a.y + 46), end = Offset(b.x, b.y + 46);
      final bend = math.max(70, (end.dx - start.dx).abs() * .5);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + bend,
          start.dy,
          end.dx - bend,
          end.dy,
          end.dx,
          end.dy,
        );
      canvas.drawPath(
        path,
        Paint()
          ..color = edgeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      canvas.drawPath(
        Path()
          ..moveTo(end.dx, end.dy)
          ..lineTo(end.dx - 7, end.dy - 4)
          ..lineTo(end.dx - 7, end.dy + 4)
          ..close(),
        Paint()..color = edgeColor,
      );
      if (showLabels && e.label.isNotEmpty) {
        final painter = TextPainter(
          text: TextSpan(
            text: e.label,
            style: TextStyle(fontSize: 11, color: edgeColor),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 120);
        painter.paint(
          canvas,
          Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2 - 18),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) => true;
}

class WorkflowMinimap extends CustomPainter {
  WorkflowMinimap(this.nodes, this.edges, this.colors, {this.viewport});
  final List<FlowNode> nodes;
  final List<FlowEdge> edges;
  final ColorScheme colors;
  final Rect? viewport;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      Paint()..color = colors.surface,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      Paint()
        ..color = colors.outlineVariant
        ..style = PaintingStyle.stroke,
    );
    final width = math.max(
      2200.0,
      nodes.fold<double>(0, (v, n) => math.max(v, n.x + 350)),
    );
    final height = math.max(
      1600.0,
      nodes.fold<double>(0, (v, n) => math.max(v, n.y + 250)),
    );
    Offset point(FlowNode n) => Offset(
      (n.x + 105) / width * size.width,
      (n.y + 46) / height * size.height,
    );
    for (final edge in edges) {
      final a = nodes.where((n) => n.id == edge.sourceId).firstOrNull;
      final b = nodes.where((n) => n.id == edge.targetId).firstOrNull;
      if (a != null && b != null) {
        canvas.drawLine(point(a), point(b), Paint()..color = colors.outline);
      }
    }
    for (final n in nodes) {
      canvas.drawRect(
        Rect.fromLTWH(
          n.x / width * size.width,
          n.y / height * size.height,
          210 / width * size.width,
          92 / height * size.height,
        ),
        Paint()..color = colors.primary,
      );
    }
    final view = viewport;
    if (view != null) {
      canvas.save();
      canvas.clipRect(Offset.zero & size);
      canvas.drawRect(
        Rect.fromLTWH(
          view.left / width * size.width,
          view.top / height * size.height,
          view.width / width * size.width,
          view.height / height * size.height,
        ),
        Paint()
          ..color = colors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant WorkflowMinimap oldDelegate) => true;
}
