import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/api_client.dart';
import 'package:flowday/data/sync_controller.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';
import 'package:flowday/ui/account_panel.dart';
import 'package:flowday/ui/security_panel.dart';

void main() {
  testWidgets('profile edit saves on server before updating local name', (
    tester,
  ) async {
    final calls = <String>[];
    final api = FlowApi(
      Uri.parse('http://localhost'),
      transport: (method, uri, headers, body) async {
        calls.add('$method ${uri.path}');
        expect(jsonDecode(body!)['displayName'], 'Updated');
        return const ApiResponse(
          200,
          '{"user":{"id":"u","email":"user@example.com","displayName":"Updated"}}',
        );
      },
    );
    final store = FlowStore(FlowData());
    final controller = SyncController(
      api: api,
      session: const AuthSession(
        token: 'token',
        user: AccountUser(
          id: 'u',
          email: 'user@example.com',
          displayName: 'Before',
        ),
      ),
      store: store,
    );
    addTearDown(controller.dispose);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountPanel(controller: controller, onLogout: () async {}),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑资料'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Updated');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(calls, ['PUT /api/v1/auth/profile']);
    expect(store.data.preferences['displayName'], 'Updated');
    expect(find.text('Updated'), findsOneWidget);
  });
  testWidgets('account deletion cancellation makes no request', (tester) async {
    var requests = 0;
    final api = FlowApi(
      Uri.parse('http://localhost'),
      transport: (method, uri, headers, body) async {
        requests++;
        return const ApiResponse(204, '');
      },
    );
    final store = FlowStore(FlowData());
    final controller = SyncController(
      api: api,
      session: const AuthSession(
        token: 'token',
        user: AccountUser(id: 'u', email: 'a@example.com', displayName: 'A'),
      ),
      store: store,
    );
    addTearDown(controller.dispose);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SecurityPanel(controller: controller, onLogout: () async {}),
        ),
      ),
    );
    await tester.tap(find.text('注销账号'));
    await tester.pumpAndSettle();
    expect(find.text('永久注销账号'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(requests, 0);
  });
}
