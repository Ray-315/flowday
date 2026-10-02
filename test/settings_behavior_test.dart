import 'package:flowday/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/editors.dart';
import 'package:flowday/ui/calendar_page.dart';
import 'package:flowday/ui/mini_calendar.dart';
import 'package:flowday/ui/workflow_page.dart';

FlowStore dependencyStore(Map<String, dynamic> preferences) => FlowStore(
  FlowData(
    preferences: preferences,
    projects: [Project(id: 'p', title: 'Project')],
    nodes: [
      FlowNode(id: 'a', projectId: 'p', title: 'First'),
      FlowNode(
        id: 'b',
        projectId: 'p',
        title: 'Second',
        status: NodeStatus.locked,
      ),
    ],
    edges: [FlowEdge(id: 'edge', projectId: 'p', sourceId: 'a', targetId: 'b')],
  ),
);

void main() {
  testWidgets('dark calendar, editors and workflow use themed surfaces', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = ThemeData.dark().copyWith(
      dividerColor: const Color(0xff334155),
    );
    final store = dependencyStore({});
    Future<void> show(Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: child),
      ),
    );
    await show(CalendarPage(store: store));
    final boxes = tester
        .widgetList<Container>(find.byType(Container))
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>();
    expect(
      boxes.where((box) => box.color == theme.colorScheme.surface),
      isNotEmpty,
    );
    expect(boxes.where((box) => box.color == Colors.white), isEmpty);
    expect(tester.takeException(), isNull);
    await show(
      MiniCalendar(selected: DateTime(2026, 9, 15), onSelected: (_) {}),
    );
    final date = tester.widget<Text>(find.text('16'));
    expect(date.style!.color, theme.colorScheme.onSurface);
    await show(TaskEditor(store: store));
    final header = tester.widget<Container>(
      find
          .ancestor(of: find.text('新建任务'), matching: find.byType(Container))
          .first,
    );
    expect(
      (header.decoration! as BoxDecoration).border!.bottom.color,
      theme.dividerColor,
    );
    await show(WorkflowPage(store: store));
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<GraphPainter>()
        .single;
    expect(painter.dotColor, theme.dividerColor);
    expect(painter.edgeColor, theme.colorScheme.onSurfaceVariant);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'workflow creates tasks using preferences and can disable linked Todo',
    (tester) async {
      final store = FlowStore(
        FlowData(
          projects: [Project(id: 'p', title: 'Project')],
          preferences: {
            'workflowDefaultPriority': 'urgent',
            'workflowEstimateMinutes': 120,
            'workflowAutoLayout': true,
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WorkflowPage(store: store)),
        ),
      );
      Future<void> add(String name) async {
        await tester.tap(find.text('添加节点'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).last, name);
        await tester.tap(find.text('添加'));
        await tester.pumpAndSettle();
      }

      await add('First');
      expect(store.tasks.single.priority, Priority.urgent);
      expect(store.tasks.single.estimateMinutes, 120);
      expect(store.data.nodes.single.x, 40);
      store.data.preferences['workflowAutoTodo'] = false;
      await add('Second');
      expect(store.tasks, hasLength(1));
      expect(store.data.nodes.last.taskId, isNull);
      store.data.preferences['workflowDefaultKind'] = 'note';
      await add('Third');
      expect(store.data.nodes.last.kind, NodeKind.note);
    },
  );

  test('skip completion and auto unlock preferences control successors', () {
    final store = dependencyStore({'workflowSkipCompletes': false});
    store.setNodeStatus('a', NodeStatus.skipped);
    expect(store.data.nodes.last.status, NodeStatus.locked);
    store.data.preferences['workflowSkipCompletes'] = true;
    store.setNodeStatus('a', NodeStatus.skipped);
    expect(store.data.nodes.last.status, NodeStatus.ready);
    final manual = dependencyStore({'workflowAutoUnlock': false});
    manual.setNodeStatus('a', NodeStatus.done);
    expect(manual.data.nodes.last.status, NodeStatus.locked);
    manual.setNodeStatus('b', NodeStatus.ready);
    expect(manual.data.nodes.last.status, NodeStatus.ready);
  });

  test('manual unlocking does not bypass enabled start dependency checks', () {
    final store = dependencyStore({'workflowAllowManualUnlock': false});
    expect(
      () => store.setNodeStatus('b', NodeStatus.ready),
      throwsFormatException,
    );
    expect(store.data.nodes.last.status, NodeStatus.locked);
    store.data.preferences['workflowAllowManualUnlock'] = true;
    store.setNodeStatus('b', NodeStatus.ready);
    expect(
      () => store.setNodeStatus('b', NodeStatus.doing),
      throwsFormatException,
    );
    store.data.preferences['workflowCheckDependencies'] = false;
    store.setNodeStatus('b', NodeStatus.doing);
    expect(store.data.nodes.last.status, NodeStatus.doing);
  });

  test('week start and invalid preference fallbacks are stable', () {
    final store = FlowStore(
      FlowData(
        preferences: {
          'weekStartsMonday': false,
          'defaultEventMinutes': -10,
          'defaultTaskPriority': 'invalid',
        },
      ),
    );
    expect(store.weekOffset(DateTime(2026, 9, 27)), 0);
    expect(store.preferenceMinutes('defaultEventMinutes'), 60);
    expect(store.preferencePriority('defaultTaskPriority'), Priority.normal);
    store.data.preferences['weekStartsMonday'] = true;
    expect(store.weekOffset(DateTime(2026, 9, 27)), 6);
  });

  testWidgets('new task editor consumes saved defaults', (tester) async {
    final store = FlowStore(
      FlowData(
        preferences: {
          'defaultEstimateMinutes': 90,
          'defaultTaskPriority': 'high',
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TaskEditor(store: store)),
      ),
    );
    final priority = tester.widget<FlowSelect<Priority>>(
      find.byType(FlowSelect<Priority>),
    );
    expect(priority.initialValue, Priority.high);
    final estimate = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '预计耗时（分钟）',
    );
    await tester.scrollUntilVisible(
      estimate,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<TextField>(estimate).controller!.text, '90');
  });

  testWidgets('new event uses duration preference and keeps explicit dates', (
    tester,
  ) async {
    final store = FlowStore(FlowData(preferences: {'defaultEventMinutes': 90}));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventEditor(
            store: store,
            initialDate: DateTime(2026, 9, 30, 9),
          ),
        ),
      ),
    );
    expect(find.textContaining('10:30'), findsOneWidget);
  });

  testWidgets('Sunday mini calendar begins with Sunday', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiniCalendar(
            selected: DateTime(2026, 9),
            weekStartsMonday: false,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.text('日')).dx,
      lessThan(tester.getTopLeft(find.text('一')).dx),
    );
  });

  testWidgets('workflow respects hidden milestones, labels and initial zoom', (
    tester,
  ) async {
    final store = dependencyStore({
      'workflowShowMilestones': false,
      'workflowShowEdgeLabels': false,
      'workflowZoom': 75,
    });
    store.data.nodes.add(
      FlowNode(
        id: 'm',
        projectId: 'p',
        title: 'Hidden milestone',
        kind: NodeKind.milestone,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorkflowPage(store: store)),
      ),
    );
    expect(find.text('Hidden milestone'), findsNothing);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), .75);
    final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    expect(
      paints.where((p) => p.painter is GraphPainter).single.painter,
      isA<GraphPainter>().having((p) => p.showLabels, 'labels', false),
    );
  });
}
