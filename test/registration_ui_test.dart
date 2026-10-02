import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/api_client.dart';
import 'package:flowday/ui/auth_page.dart';
import 'package:flowday/ui/theme.dart';

void main() {
  testWidgets('registration sends email code and submits it with the account', (
    tester,
  ) async {
    final calls = <Map<String, dynamic>>[];
    var authenticated = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: flowTheme(),
        home: AuthPage(
          onAuthenticated: (_, _) async {
            authenticated = true;
          },
          apiFactory: (url) => FlowApi(
            url,
            transport: (_, uri, _, body) async {
              calls.add({
                'path': uri.path,
                ...jsonDecode(body!) as Map<String, dynamic>,
              });
              return ApiResponse(
                200,
                jsonEncode(
                  uri.path.endsWith('registration-code')
                      ? {'sent': true, 'retryAfterSeconds': 60}
                      : {
                          'token': 'fixture-token',
                          'user': {
                            'id': 'a',
                            'email': 'a@example.com',
                            'displayName': '测试',
                          },
                        },
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('没有账号？立即注册'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(4));
    await tester.enterText(find.byType(TextFormField).at(0), '测试');
    await tester.enterText(find.byType(TextFormField).at(1), 'a@example.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'password-12345');
    await tester.tap(find.text('发送验证码'));
    await tester.pumpAndSettle();
    expect(calls.single['path'], '/api/v1/auth/registration-code');
    expect(calls.single['email'], 'a@example.com');
    expect(find.text('60 秒后重发'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(3), '123456');
    await tester.ensureVisible(find.text('注册'));
    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();
    expect(calls.last['verificationCode'], '123456');
    expect(authenticated, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'registration cannot submit without code and mail failure is visible',
    (tester) async {
      var requests = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: flowTheme(),
          home: AuthPage(
            onAuthenticated: (_, _) async {},
            apiFactory: (url) => FlowApi(
              url,
              transport: (_, _, _, _) async {
                requests++;
                return const ApiResponse(
                  503,
                  '{"error":{"code":"MAIL_NOT_CONFIGURED","message":"注册邮件服务尚未配置"}}',
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('没有账号？立即注册'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '测试');
      await tester.enterText(find.byType(TextFormField).at(1), 'a@example.com');
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'password-12345',
      );
      await tester.ensureVisible(find.text('注册'));
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();
      expect(requests, 0);
      await tester.ensureVisible(find.text('发送验证码'));
      await tester.tap(find.text('发送验证码'));
      await tester.pumpAndSettle();
      expect(find.text('注册邮件服务尚未配置'), findsOneWidget);
      expect(find.text('发送验证码'), findsOneWidget);
    },
  );
}
