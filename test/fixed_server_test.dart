import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/api_client.dart';
import 'package:flowday/data/server_config.dart';
import 'package:flowday/ui/auth_page.dart';
import 'package:flowday/ui/theme.dart';

void main() {
  testWidgets(
    'login uses the fixed production endpoint without a server field',
    (tester) async {
      Uri? requested;
      FlowApi? authenticatedApi;
      await tester.pumpWidget(
        MaterialApp(
          theme: flowTheme(),
          home: AuthPage(
            onAuthenticated: (_, api) async {
              authenticatedApi = api;
            },
            apiFactory: (url) => FlowApi(
              url,
              transport: (_, uri, headers, body) async {
                requested = uri;
                return ApiResponse(
                  200,
                  jsonEncode({
                    'token': 'synthetic-test-token',
                    'user': {
                      'id': 'fixture',
                      'email': 'fixture@example.test',
                      'displayName': '测试',
                    },
                  }),
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('服务器设置'), findsNothing);
      expect(find.text('服务器地址'), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(2));
      await tester.enterText(
        find.byType(TextFormField).first,
        'fixture@example.test',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'synthetic-password',
      );
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();
      expect(requested.toString(), '$flowdayServerUrl/api/v1/auth/login');
      expect(authenticatedApi?.baseUrl, flowdayApiBaseUrl);
      expect(tester.takeException(), isNull);
    },
  );
}
