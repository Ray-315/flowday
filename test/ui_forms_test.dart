import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/auth_page.dart';
import 'package:flowday/ui/editors.dart';
import 'package:flowday/ui/theme.dart';
import 'package:flowday/ui/workflow_page.dart';

void main() {
  testWidgets('dark task editor selects a project and clears it', (
    tester,
  ) async {
    final store = FlowStore(
      FlowData(
        projects: [Project(id: 'p', title: '项目甲')],
      ),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: flowTheme(brightness: Brightness.dark),
        home: Scaffold(body: TaskEditor(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('无项目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('项目甲').last);
    await tester.pumpAndSettle();
    expect(find.text('项目甲'), findsOneWidget);
    await tester.tap(find.text('项目甲'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('无项目').last);
    await tester.pumpAndSettle();
    expect(find.text('无项目'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark workflow text and project selection follow theme', (
    tester,
  ) async {
    final theme = flowTheme(brightness: Brightness.dark);
    final store = FlowStore(
      FlowData(
        projects: [
          Project(id: 'a', title: '项目甲'),
          Project(id: 'b', title: '项目乙'),
        ],
        nodes: [
          FlowNode(
            id: 'a-node',
            projectId: 'a',
            title: '节点甲',
            description: '节点说明',
          ),
          FlowNode(id: 'b-node', projectId: 'b', title: '节点乙'),
        ],
      ),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: WorkflowPage(store: store)),
      ),
    );
    expect(
      tester.widget<Text>(find.text('节点说明')).style!.color,
      theme.colorScheme.onSurfaceVariant,
    );
    await tester.tap(find.text('项目甲'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('项目乙').last);
    await tester.pumpAndSettle();
    expect(find.text('节点乙'), findsOneWidget);
    expect(find.text('节点甲'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark login form uses theme surface and title colors', (
    tester,
  ) async {
    final theme = flowTheme(brightness: Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: AuthPage(onAuthenticated: (_, _) async {}),
      ),
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      theme.colorScheme.surface,
    );
    expect(
      tester.widget<Text>(find.text('欢迎回来')).style!.color,
      theme.colorScheme.onSurface,
    );
    expect(tester.takeException(), isNull);
  });
}
