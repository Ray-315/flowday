import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/workflow_page.dart';
import 'package:flowday/ui/workflow_history.dart';

FlowStore graph() => FlowStore(
  FlowData(
    projects: [
      Project(id: 'p', title: '流程'),
      Project(id: 'q', title: '其他'),
    ],
    tasks: [
      Task(id: 't', title: '任务', projectId: 'p'),
      Task(id: 'u', title: '其他任务', projectId: 'q'),
    ],
    nodes: [
      FlowNode(
        id: 'a',
        projectId: 'p',
        title: '节点甲',
        taskId: 't',
        x: 40,
        y: 80,
      ),
      FlowNode(id: 'b', projectId: 'p', title: '节点乙', x: 340, y: 80),
    ],
    edges: [FlowEdge(id: 'e', projectId: 'p', sourceId: 'a', targetId: 'b')],
  ),
);

void main() {
  testWidgets('multiple selection copies internal edges with remapped ids', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = graph();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkflowPage(store: store)),
      ),
    );
    await tester.tap(find.text('节点甲'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('节点乙').first);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.paste));
    await tester.pump();
    expect(store.data.nodes.length, 4);
    expect(store.data.edges.length, 2);
    final edge = store.data.edges.last;
    expect(edge.sourceId, isNot('a'));
    expect(edge.targetId, isNot('b'));
    expect(store.data.nodes.any((n) => n.id == edge.sourceId), isTrue);
    expect(store.data.nodes.any((n) => n.id == edge.targetId), isTrue);
    store.data.validate();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
  test(
    'history restores graph edits and linked task status without replacing other project tasks',
    () {
      final store = graph();
      final history = WorkflowHistory();
      history.checkpoint(store, 'p');
      store.setNodeStatus('a', NodeStatus.done);
      store.data.nodes.first.title = '修改';
      store.data.nodes.add(FlowNode(id: 'c', projectId: 'p', title: '新增'));
      store.data.edges.clear();
      store.data.tasks.last.title = '其他修改';
      history.restore(store, 'p');
      expect(store.data.nodes.map((n) => n.id), ['a', 'b']);
      expect(store.data.nodes.first.title, '节点甲');
      expect(
        store.data.tasks.firstWhere((t) => t.id == 't').status,
        TaskStatus.todo,
      );
      expect(store.data.tasks.firstWhere((t) => t.id == 'u').title, '其他修改');
      expect(store.data.edges.single.id, 'e');
      history.restore(store, 'p', redo: true);
      expect(store.data.nodes.length, 3);
      expect(store.data.nodes.first.title, '修改');
      expect(
        store.data.tasks.firstWhere((t) => t.id == 't').status,
        TaskStatus.done,
      );
      expect(store.data.edges, isEmpty);
      store.dispose();
    },
  );
  testWidgets('copy paste clones linked tasks and delete is reversible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = graph();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkflowPage(store: store)),
      ),
    );
    await tester.tap(find.text('节点甲'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.paste));
    await tester.pump();
    expect(store.data.nodes.length, 3);
    final pasted = store.data.nodes.last;
    expect(pasted.id, isNot('a'));
    expect(pasted.taskId, isNot('t'));
    expect(pasted.taskId, isNotNull);
    expect(store.data.tasks.length, 3);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    expect(store.data.nodes.length, 2);
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(store.data.nodes.length, 3);
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    expect(store.data.nodes.length, 2);
    expect(store.data.tasks.length, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
  testWidgets('collapsed groups hide members and jump opens selected project', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = graph();
    store.data.nodes.add(
      FlowNode(
        id: 'g',
        projectId: 'p',
        title: '阶段',
        kind: NodeKind.group,
        x: 40,
        y: 240,
      ),
    );
    store.data.nodes.first.groupId = 'g';
    store.data.nodes.add(
      FlowNode(
        id: 'j',
        projectId: 'p',
        title: '跳转',
        kind: NodeKind.link,
        targetProjectId: 'q',
        x: 340,
        y: 240,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkflowPage(store: store)),
      ),
    );
    await tester.tap(find.text('阶段'));
    await tester.pump();
    await tester.tap(find.text('折叠分组'));
    await tester.pump();
    expect(find.text('节点甲'), findsNothing);
    await tester.tap(find.text('展开分组'));
    await tester.pump();
    expect(find.text('节点甲'), findsOneWidget);
    await tester.tap(find.text('跳转'));
    await tester.pump();
    await tester.tap(find.text('打开工作流'));
    await tester.pump();
    expect(find.text('节点甲'), findsNothing);
    expect(find.text('其他'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
