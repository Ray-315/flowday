import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/api_client.dart';

void main() {
  test('requires HTTPS except for loopback', () {
    expect(
      () => FlowApi(Uri.parse('http://example.com')),
      throwsFormatException,
    );
    expect(
      () => FlowApi(Uri.parse('https://user:secret@example.com')),
      throwsFormatException,
    );
    expect(
      FlowApi(Uri.parse('http://127.0.0.1:3108')).baseUrl.toString(),
      'http://127.0.0.1:3108/api/v1',
    );
    expect(
      FlowApi(Uri.parse('https://example.com/api/v1/')).baseUrl.path,
      '/api/v1',
    );
  });
  test('login uses expected endpoint and parses session', () async {
    final api = FlowApi(
      Uri.parse('https://example.com'),
      transport: (method, url, headers, body) async {
        expect(method, 'POST');
        expect(url.path, '/api/v1/auth/login');
        expect(
          body,
          '{"email":"a@example.com","password":"example-test-password"}',
        );
        return const ApiResponse(
          200,
          '{"token":"test-only","user":{"id":"1","email":"a@example.com","displayName":"A"}}',
        );
      },
    );
    expect(
      (await api.login('a@example.com', 'example-test-password')).user.id,
      '1',
    );
  });
  test('401 and version conflict retain useful error fields', () async {
    var status = 401;
    final api = FlowApi(
      Uri.parse('https://example.com'),
      transport: (method, url, headers, body) async {
        expect(headers['Authorization'], 'Bearer test-only');
        return ApiResponse(
          status,
          status == 401
              ? '{"error":{"code":"UNAUTHORIZED","message":"请重新登录"}}'
              : '{"error":{"code":"VERSION_CONFLICT","message":"冲突","currentVersion":4}}',
        );
      },
    );
    await expectLater(
      api.getWorkspace('test-only'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
    );
    status = 409;
    await expectLater(
      api.putWorkspace('test-only', 1, {}),
      throwsA(
        isA<ApiException>().having((e) => e.currentVersion, 'version', 4),
      ),
    );
  });
  test('network failures have a safe actionable message', () async {
    final api = FlowApi(
      Uri.parse('https://example.com'),
      transport: (_, _, _, _) async {
        throw const SocketException('internal socket details');
      },
    );
    await expectLater(
      api.getWorkspace('test-only'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'NETWORK_ERROR'),
      ),
    );
  });
}
