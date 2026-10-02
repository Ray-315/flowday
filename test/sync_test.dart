import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/api_client.dart';
import 'package:flowday/data/sync_controller.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';

const session = AuthSession(
  token: 'test-only',
  user: AccountUser(id: '1', email: 'a@example.com', displayName: 'A'),
);
FlowData data(String title) => FlowData(
  tasks: [Task(id: 'task', title: title)],
);
String serialized(FlowStore store) => jsonEncode(store.data.toJson());

void main() {
  test(
    'remote updates download when local is unchanged, with backup first',
    () async {
      final store = FlowStore(data('old'));
      var backedUp = false;
      final api = FlowApi(
        Uri.parse('https://example.com'),
        transport: (_, _, _, _) async => ApiResponse(
          200,
          jsonEncode({'version': 2, 'data': data('remote').toJson()}),
        ),
      );
      final sync = SyncController(
        api: api,
        session: session,
        store: store,
        baseVersion: 1,
        lastSyncedJson: serialized(store),
        beforeReplace: () async {
          expect(store.tasks.single.title, 'old');
          backedUp = true;
        },
      );
      await sync.sync();
      expect(backedUp, isTrue);
      expect(store.tasks.single.title, 'remote');
      expect(sync.localDirty, isFalse);
      sync.dispose();
      store.dispose();
    },
  );
  test('edits during upload remain dirty for next sync', () async {
    final store = FlowStore(data('original'));
    final baseline = serialized(store);
    store.tasks.single.title = 'first edit';
    store.changed();
    final started = Completer<void>(), release = Completer<void>();
    final api = FlowApi(
      Uri.parse('https://example.com'),
      transport: (method, _, _, body) async {
        if (method == 'GET') {
          return ApiResponse(
            200,
            jsonEncode({'version': 1, 'data': data('original').toJson()}),
          );
        }
        expect(jsonDecode(body!)['data']['tasks'][0]['title'], 'first edit');
        started.complete();
        await release.future;
        return const ApiResponse(200, '{"version":2}');
      },
    );
    final sync = SyncController(
      api: api,
      session: session,
      store: store,
      baseVersion: 1,
      lastSyncedJson: baseline,
    );
    final pending = sync.sync();
    await started.future;
    store.tasks.single.title = 'second edit';
    store.changed();
    release.complete();
    await pending;
    expect(sync.baseVersion, 2);
    expect(sync.localDirty, isTrue);
    expect(store.tasks.single.title, 'second edit');
    sync.dispose();
    store.dispose();
  });
  test('remote and local changes preserve local data as conflict', () async {
    final store = FlowStore(data('original'));
    final baseline = serialized(store);
    store.tasks.single.title = 'local';
    store.changed();
    var writes = 0;
    final api = FlowApi(
      Uri.parse('https://example.com'),
      transport: (method, _, _, _) async {
        if (method == 'PUT') writes++;
        return ApiResponse(
          200,
          jsonEncode({'version': 2, 'data': data('remote').toJson()}),
        );
      },
    );
    final sync = SyncController(
      api: api,
      session: session,
      store: store,
      baseVersion: 1,
      lastSyncedJson: baseline,
    );
    await sync.sync();
    expect(sync.conflict, isTrue);
    expect(writes, 0);
    expect(store.tasks.single.title, 'local');
    sync.dispose();
    store.dispose();
  });
  test(
    'first connection does not upload existing data without choice',
    () async {
      final store = FlowStore(data('local'));
      final api = FlowApi(
        Uri.parse('https://example.com'),
        transport: (method, _, _, _) async {
          expect(method, 'GET');
          return const ApiResponse(200, '{"version":0,"data":null}');
        },
      );
      final sync = SyncController(api: api, session: session, store: store);
      await sync.sync();
      expect(sync.conflict, isTrue);
      expect(store.tasks.single.title, 'local');
      sync.dispose();
      store.dispose();
    },
  );
  test('edit while fetching server changes is preserved', () async {
    final store = FlowStore(data('original'));
    final started = Completer<void>(), release = Completer<void>();
    final api = FlowApi(
      Uri.parse('https://example.com'),
      transport: (_, _, _, _) async {
        started.complete();
        await release.future;
        return ApiResponse(
          200,
          jsonEncode({'version': 2, 'data': data('remote').toJson()}),
        );
      },
    );
    final sync = SyncController(
      api: api,
      session: session,
      store: store,
      baseVersion: 1,
      lastSyncedJson: serialized(store),
    );
    final pending = sync.sync();
    await started.future;
    store.tasks.single.title = 'local';
    store.changed();
    release.complete();
    await pending;
    expect(sync.conflict, isTrue);
    expect(store.tasks.single.title, 'local');
    sync.dispose();
    store.dispose();
  });
  test(
    'conflict resolution refreshes version and handles another racing write',
    () async {
      final store = FlowStore(data('local'));
      final api = FlowApi(
        Uri.parse('https://example.com'),
        transport: (method, _, _, body) async {
          if (method == 'GET') {
            return ApiResponse(
              200,
              jsonEncode({'version': 4, 'data': data('remote').toJson()}),
            );
          }
          expect(jsonDecode(body!)['baseVersion'], 4);
          return const ApiResponse(
            409,
            '{"code":"VERSION_CONFLICT","message":"冲突","currentVersion":5}',
          );
        },
      );
      final sync = SyncController(api: api, session: session, store: store)
        ..conflict = true;
      await sync.resolveUploadLocal();
      expect(sync.conflict, isTrue);
      expect(store.tasks.single.title, 'local');
      sync.dispose();
      store.dispose();
    },
  );
}
