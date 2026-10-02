import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/api_client.dart';
import 'package:flowday/data/sync_controller.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/global_search_panel.dart';

FlowStore fixture() => FlowStore(
  FlowData(
    projects: [Project(id: 'p', title: 'Project')],
    tasks: [
      Task(
        id: 't',
        title: 'match task',
        projectId: 'p',
        attachments: [
          Attachment(
            id: 'local',
            title: 'Local note',
            kind: AttachmentKind.markdown,
            content: 'needle local',
          ),
        ],
      ),
    ],
    nodes: [
      FlowNode(
        id: 'n',
        projectId: 'p',
        title: 'Workflow',
        description: 'needle node',
      ),
    ],
  ),
);

GlobalSearchPanel panel(
  FlowStore store, {
  SyncController? sync,
  ValueChanged<Task>? onTask,
  ValueChanged<FlowNode>? onNode,
  ValueChanged<String>? onCreateTask,
  ValueChanged<String>? onNaturalLanguage,
}) => GlobalSearchPanel(
  store: store,
  sync: sync,
  closeOnActivate: false,
  onTask: onTask ?? (_) {},
  onEvent: (_) {},
  onProject: (_) {},
  onNode: onNode ?? (_) {},
  onAttachment: (_) {},
  onCreateTask: onCreateTask,
  onNaturalLanguage: onNaturalLanguage,
);

void main() {
  test(
    'matches node descriptions and local/cloud Markdown; filters deleted and unrelated owners',
    () {
      final store = fixture();
      final results = globalSearchResults(
        store,
        'NEEDLE',
        cloudAttachments: [
          {
            'id': 'remote',
            'ownerType': 'task',
            'ownerId': 't',
            'name': 'Cloud',
            'markdown': 'needle cloud',
          },
          {
            'id': 'deleted',
            'ownerType': 'task',
            'ownerId': 't',
            'name': 'Deleted',
            'markdown': 'needle',
            'deletedAt': '2026-01-01',
          },
          {
            'id': 'unknown',
            'ownerType': 'task',
            'ownerId': 'other',
            'name': 'Unknown',
            'markdown': 'needle',
          },
        ],
      );
      expect(results.map((r) => r.title), ['Workflow', 'Local note', 'Cloud']);
      expect(globalSearchResults(store, ' '), isEmpty);
      store.project('p')!.deletedAt = DateTime.now();
      expect(globalSearchResults(store, 'needle'), isEmpty);
      store.dispose();
    },
  );

  testWidgets(
    'keyboard opens selected node and exposes create/natural language actions',
    (tester) async {
      final store = fixture();
      String? opened, created, natural;
      await tester.pumpWidget(
        MaterialApp(
          home: panel(
            store,
            onNode: (n) => opened = n.id,
            onCreateTask: (s) => created = s,
            onNaturalLanguage: (s) => natural = s,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'needle node');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, 'n');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(created, 'needle node');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(natural, 'needle node');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets('completion updates store without activating result', (
    tester,
  ) async {
    final store = fixture();
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(home: panel(store, onTask: (_) => opened = true)),
    );
    await tester.enterText(find.byType(TextField), 'match task');
    await tester.pump();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(store.tasks.single.status, TaskStatus.done);
    expect(opened, false);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('account switch discards late previous-account attachments', (
    tester,
  ) async {
    final store = fixture();
    final first = Completer<ApiResponse>();
    final tokens = <String?>[];
    final api = FlowApi(
      Uri.parse('https://example.com'),
      transport: (method, url, headers, body) async {
        expect(method, 'GET');
        expect(url.path, endsWith('/attachments'));
        tokens.add(headers['Authorization']);
        if (tokens.length == 1) return first.future;
        return ApiResponse(
          200,
          jsonEncode({
            'attachments': [
              {
                'id': 'new',
                'ownerType': 'task',
                'ownerId': 't',
                'name': 'Account B',
                'markdown': 'cloud needle',
              },
            ],
          }),
        );
      },
    );
    SyncController sync(String account) => SyncController(
      api: api,
      store: store,
      session: AuthSession(
        token: 'fixture-$account',
        user: AccountUser(
          id: account,
          email: '$account@example.com',
          displayName: account,
        ),
      ),
    );
    final a = sync('a'), b = sync('b');
    await tester.pumpWidget(MaterialApp(home: panel(store, sync: a)));
    await tester.enterText(find.byType(TextField), 'cloud needle');
    await tester.pumpWidget(MaterialApp(home: panel(store, sync: b)));
    await tester.pumpAndSettle();
    expect(find.text('Account B'), findsOneWidget);
    first.complete(
      ApiResponse(
        200,
        jsonEncode({
          'attachments': [
            {
              'id': 'old',
              'ownerType': 'task',
              'ownerId': 't',
              'name': 'Account A',
              'markdown': 'cloud needle',
            },
          ],
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Account A'), findsNothing);
    expect(find.text('Account B'), findsOneWidget);
    expect(tokens, ['Bearer fixture-a', 'Bearer fixture-b']);
    await tester.pumpWidget(const SizedBox());
    a.dispose();
    b.dispose();
    store.dispose();
  });
}
