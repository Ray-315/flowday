import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/api_client.dart';
import 'package:flowday/data/sync_controller.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/ai_panel.dart';
import 'package:flowday/ui/theme.dart';

const testSession = AuthSession(
  token: 'fixture-session',
  user: AccountUser(
    id: 'fixture-user',
    email: 'fixture@example.com',
    displayName: '测试用户',
  ),
);
FlowData workspace(String title) => FlowData(
  tasks: [Task(id: 'task', title: title)],
);

void main() {
  test(
    'remoteMutation replaces workspace and saves server baseline after successful operation',
    () async {
      final store = FlowStore(workspace('原任务'));
      var remote = workspace('原任务'), version = 1, backups = 0;
      final baselines = <int>[];
      final api = FlowApi(
        Uri.parse('https://example.com'),
        transport: (method, uri, headers, body) async {
          expect(method, 'GET');
          expect(uri.path, endsWith('/workspace'));
          return ApiResponse(
            200,
            jsonEncode({'version': version, 'data': remote.toJson()}),
          );
        },
      );
      final sync = SyncController(
        api: api,
        session: testSession,
        store: store,
        baseVersion: 1,
        lastSyncedJson: jsonEncode(store.data.toJson()),
        beforeReplace: () async {
          backups++;
          expect(store.tasks.single.title, '原任务');
        },
        saveBaseline: (version, json) async => baselines.add(version),
      );
      addTearDown(sync.dispose);
      addTearDown(store.dispose);
      await sync.remoteMutation((baseVersion) async {
        expect(baseVersion, 1);
        remote = workspace('服务器修改');
        version = 2;
      });
      expect(store.tasks.single.title, '服务器修改');
      expect(sync.baseVersion, 2);
      expect(sync.localDirty, isFalse);
      expect(sync.conflict, isFalse);
      expect(sync.error, isNull);
      expect(backups, 1);
      expect(baselines.last, 2);
    },
  );

  test(
    'remoteMutation preserves edits made while request is in flight and reports conflict',
    () async {
      final store = FlowStore(workspace('原任务'));
      var remote = workspace('原任务'), version = 1;
      final started = Completer<void>(), release = Completer<void>();
      final api = FlowApi(
        Uri.parse('https://example.com'),
        transport: (_, _, _, _) async => ApiResponse(
          200,
          jsonEncode({'version': version, 'data': remote.toJson()}),
        ),
      );
      final sync = SyncController(
        api: api,
        session: testSession,
        store: store,
        baseVersion: 1,
        lastSyncedJson: jsonEncode(store.data.toJson()),
      );
      addTearDown(sync.dispose);
      addTearDown(store.dispose);
      final pending = sync.remoteMutation((baseVersion) async {
        expect(baseVersion, 1);
        started.complete();
        await release.future;
        remote = workspace('服务器修改');
        version = 2;
      });
      final rejected = expectLater(pending, throwsStateError);
      await started.future;
      store.updateTask(
        Task.fromJson(store.tasks.single.toJson())..title = '请求期间的本地编辑',
      );
      release.complete();
      await rejected;
      expect(store.tasks.single.title, '请求期间的本地编辑');
      expect(sync.conflict, isTrue);
      expect(sync.localDirty, isTrue);
      expect(sync.baseVersion, 1);
    },
  );

  testWidgets('AI preview and cancelled approval never write workspace', (
    tester,
  ) async {
    final store = FlowStore(workspace('原任务'));
    final before = jsonEncode(store.data.toJson());
    var writes = 0;
    final api = FlowApi(
      Uri.parse('https://example.com'),
      transport: (method, uri, headers, body) async {
        if (uri.path.endsWith('/workspace')) {
          if (method != 'GET') writes++;
          return ApiResponse(
            200,
            jsonEncode({'version': 1, 'data': store.data.toJson()}),
          );
        }
        if (uri.path.endsWith('/ai/apply')) writes++;
        expect(uri.path, endsWith('/ai/preview'));
        return ApiResponse(
          200,
          jsonEncode({
            'previewId': 'preview',
            'intent': {
              'actions': [
                {'type': 'todo', 'title': '拟创建任务'},
              ],
            },
          }),
        );
      },
    );
    final sync = SyncController(
      api: api,
      session: testSession,
      store: store,
      baseVersion: 1,
      lastSyncedJson: before,
    );
    addTearDown(sync.dispose);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: flowTheme(),
        home: Scaffold(
          body: AiPanel(sync: sync, text: '创建任务'),
        ),
      ),
    );
    await tester.tap(find.text('解析预览'));
    await tester.pumpAndSettle();
    expect(find.text('拟创建任务'), findsOneWidget);
    expect(writes, 0);
    expect(jsonEncode(store.data.toJson()), before);
    await tester.scrollUntilVisible(
      find.text('确认应用'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('确认应用'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(writes, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(jsonEncode(store.data.toJson()), before);
    expect(find.text('拟创建任务'), findsOneWidget);
  });

  testWidgets(
    'AI candidate choice and partial selection reach approved apply request',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = FlowStore(workspace('原任务'));
      var remote = workspace('原任务'), version = 1;
      Map<String, dynamic>? submitted;
      final api = FlowApi(
        Uri.parse('https://example.com'),
        transport: (method, uri, headers, body) async {
          if (uri.path.endsWith('/workspace')) {
            return ApiResponse(
              200,
              jsonEncode({'version': version, 'data': remote.toJson()}),
            );
          }
          if (uri.path.endsWith('/ai/schedule')) {
            expect(jsonDecode(body!)['taskIds'], ['task']);
            return ApiResponse(
              200,
              jsonEncode({
                'previewId': 'preview',
                'candidates': [
                  {
                    'id': 'a',
                    'label': '方案一',
                    'intent': {
                      'actions': [
                        {'type': 'event', 'title': '方案一时间块'},
                      ],
                    },
                  },
                  {
                    'id': 'b',
                    'label': '方案二',
                    'intent': {
                      'actions': [
                        {'type': 'event', 'title': '方案二时间块'},
                        {'type': 'todo', 'title': '未选任务'},
                      ],
                    },
                  },
                ],
              }),
            );
          }
          expect(uri.path, endsWith('/ai/apply'));
          submitted = Map<String, dynamic>.from(jsonDecode(body!) as Map);
          remote = workspace('原任务')
            ..tasks.add(Task(id: 'created', title: '已批准变更'));
          version = 2;
          return const ApiResponse(200, '{"version":2}');
        },
      );
      final sync = SyncController(
        api: api,
        session: testSession,
        store: store,
        baseVersion: 1,
        lastSyncedJson: jsonEncode(store.data.toJson()),
      );
      addTearDown(sync.dispose);
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: flowTheme(),
          home: Scaffold(
            body: AiPanel(sync: sync, taskIds: const ['task']),
          ),
        ),
      );
      await tester.tap(find.text('安排本周'));
      await tester.pumpAndSettle();
      expect(find.text('方案一时间块'), findsOneWidget);
      await tester.tap(find.text('方案二'));
      await tester.pumpAndSettle();
      expect(find.text('方案二时间块'), findsOneWidget);
      expect(find.text('方案一时间块'), findsNothing);
      await tester.tap(find.text('未选任务'));
      await tester.pump();
      expect(submitted, isNull);
      expect(store.tasks.length, 1);
      await tester.tap(find.text('确认应用'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(submitted, isNull);
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(submitted!['previewId'], 'preview');
      expect(submitted!['candidateId'], 'b');
      expect(submitted!['actionIndexes'], [0]);
      expect(submitted!['baseVersion'], 1);
      expect(store.tasks.map((t) => t.title), ['原任务', '已批准变更']);
      expect(sync.baseVersion, 2);
      expect(sync.localDirty, isFalse);
      expect(find.text('确认应用'), findsNothing);
    },
  );
}
