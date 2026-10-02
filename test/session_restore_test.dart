import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/api_client.dart';
import 'package:flowday/data/native_notifications.dart';
import 'package:flowday/data/secure_session.dart';
import 'package:flowday/data/server_config.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/app.dart';
import 'package:flowday/ui/bootstrap.dart';
import 'native_notifications_test.dart' show FakeNotifications;
import 'secure_session_test.dart' show MemoryCredentials;

void main() {
  Future<void> restored(
    WidgetTester tester, {
    required bool expired,
    bool offline = false,
    bool otherServer = false,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = Directory.systemTemp.createTempSync(
      'flowday-restoration-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final local = FlowStore(
      FlowData(
        tasks: otherServer ? [Task(id: 'local', title: '本地任务')] : [],
      ),
    );
    final backend = MemoryCredentials(),
        credentials = SecureSession(storage: backend);
    const session = AuthSession(
      token: 'synthetic-session',
      user: AccountUser(
        id: 'fixture-user',
        email: 'fixture@example.test',
        displayName: '恢复用户',
      ),
    );
    await credentials.save(
      FlowApi(
        Uri.parse(otherServer ? 'https://example.test' : flowdayServerUrl),
      ),
      session,
    );
    var apiCalls = 0;
    FlowApi api(Uri url) => FlowApi(
      url,
      transport: (method, url, headers, body) async {
        apiCalls++;
        if (offline) throw const SocketException('fixture offline');
        if (url.path.endsWith('/auth/me')) {
          if (expired) {
            return const ApiResponse(
              401,
              '{"error":{"code":"UNAUTHORIZED","message":"会话已过期"}}',
            );
          }
          return ApiResponse(
            200,
            jsonEncode({
              'user': {
                'id': session.user.id,
                'email': session.user.email,
                'displayName': session.user.displayName,
              },
            }),
          );
        }
        if (url.path.endsWith('/reminders')) {
          return const ApiResponse(200, '{"reminders":[]}');
        }
        return ApiResponse(
          200,
          jsonEncode({'version': 0, 'data': FlowData().toJson()}),
        );
      },
    );
    final notifications = NativeNotifications(adapter: FakeNotifications());
    await tester.pumpWidget(
      FlowBootstrap(
        directory: directory,
        localStore: local,
        secureSession: credentials,
        notifications: notifications,
        apiFactory: api,
      ),
    );
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(FlowDayApp).evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();
    final app = tester.widget<FlowDayApp>(find.byType(FlowDayApp));
    if (expired || otherServer) {
      expect(app.sync, isNull);
      expect(await credentials.load(), isNull);
      if (otherServer) {
        expect(apiCalls, 0);
        expect(local.tasks.single.title, '本地任务');
      }
    } else {
      expect(app.sync?.session.user.id, session.user.id);
      expect(await credentials.load(), isNotNull);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    local.dispose();
  }

  testWidgets(
    'startup restores encrypted session into account workspace',
    (tester) => restored(tester, expired: false),
  );
  testWidgets(
    'expired server session is cleared and local workspace remains available',
    (tester) => restored(tester, expired: true),
  );
  testWidgets(
    'offline startup retains encrypted session and opens account cache',
    (tester) => restored(tester, expired: false, offline: true),
  );
  testWidgets(
    'old server session is cleared without contacting it or deleting local data',
    (tester) => restored(tester, expired: false, otherServer: true),
  );
}
