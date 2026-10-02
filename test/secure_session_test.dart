import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/api_client.dart';
import 'package:flowday/data/secure_session.dart';

class MemoryCredentials implements CredentialStorage {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async {
    if (fail) throw StateError('unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (fail) throw StateError('unavailable');
    values.remove(key);
  }
}

void main() {
  const user = AccountUser(
    id: 'fixture-user',
    email: 'fixture@example.test',
    displayName: '用户',
  );
  const auth = AuthSession(token: 'synthetic-session', user: user);
  final api = FlowApi(Uri.parse('https://example.test'));
  test(
    'session survives recreated storage service without saving password',
    () async {
      final backend = MemoryCredentials();
      await SecureSession(storage: backend).save(api, auth);
      final restarted = SecureSession(storage: backend);
      final restored = await restarted.load();
      expect(restored!.server, api.baseUrl);
      expect(restored.session.user.id, user.id);
      expect(restored.session.token, auth.token);
      final value = jsonDecode(backend.values[SecureSession.key]!) as Map;
      expect(value.keys.toSet(), {'server', 'token', 'user'});
      expect(value.containsKey('password'), isFalse);
      await restarted.clear();
      expect(await restarted.load(), isNull);
    },
  );
  test(
    'corrupt or insecure stored server is removed before restoration',
    () async {
      final backend = MemoryCredentials()
        ..values[SecureSession.key] = 'malformed';
      final service = SecureSession(storage: backend);
      expect(await service.load(), isNull);
      expect(backend.values, isEmpty);
      backend.values[SecureSession.key] = jsonEncode({
        'server': 'http://example.test',
        'token': auth.token,
        'user': {
          'id': user.id,
          'email': user.email,
          'displayName': user.displayName,
        },
      });
      expect(await service.load(), isNull);
      expect(backend.values, isEmpty);
    },
  );
  test(
    'secure storage errors are explicit and contain no credential content',
    () async {
      final backend = MemoryCredentials()..fail = true;
      final service = SecureSession(storage: backend);
      await expectLater(
        service.save(api, auth),
        throwsA(isA<SecureSessionException>()),
      );
      await expectLater(service.load(), throwsA(isA<SecureSessionException>()));
      await expectLater(
        service.clear(),
        throwsA(isA<SecureSessionException>()),
      );
      expect(backend.values, isEmpty);
    },
  );
}
