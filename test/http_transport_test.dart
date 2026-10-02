import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/api_client.dart';

void main() {
  test('bodyless logout does not advertise an empty JSON document', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final handled = server.first.then((request) async {
      expect(request.headers.contentType, isNull);
      expect(await utf8.decoder.bind(request).join(), isEmpty);
      request.response.statusCode = 204;
      await request.response.close();
    });
    await FlowApi(Uri.parse('http://127.0.0.1:${server.port}')).logout('token');
    await handled;
  });
  test('HTTP transport encodes Chinese request bodies as UTF-8', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = server.first.then((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'token': 'test',
          'user': {
            'id': 'u',
            'email': 'test@example.test',
            'displayName': body['displayName'],
          },
        }),
      );
      await request.response.close();
      return body;
    });
    final api = FlowApi(Uri.parse('http://127.0.0.1:${server.port}'));
    final session = await api.register(
      'test@example.test',
      'password1234',
      '中文昵称',
      verificationCode: '123456',
    );
    expect(session.user.displayName, '中文昵称');
    expect((await received)['displayName'], '中文昵称');
  });
}
