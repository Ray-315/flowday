import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';

abstract interface class CredentialStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformCredentialStorage implements CredentialStorage {
  PlatformCredentialStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class SecureSessionException implements Exception {
  const SecureSessionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class StoredAuth {
  const StoredAuth(this.server, this.session);
  final Uri server;
  final AuthSession session;
}

class SecureSession {
  SecureSession({CredentialStorage? storage})
    : storage = storage ?? PlatformCredentialStorage();
  final CredentialStorage storage;
  static const key = 'flowday.auth.session.v1';
  Future<void> save(FlowApi api, AuthSession session) async {
    try {
      await storage.write(
        key,
        jsonEncode({
          'server': api.baseUrl.toString(),
          'token': session.token,
          'user': {
            'id': session.user.id,
            'email': session.user.email,
            'displayName': session.user.displayName,
          },
        }),
      );
    } catch (_) {
      throw const SecureSessionException('无法访问系统安全存储，请检查系统钥匙串或凭据服务');
    }
  }

  Future<StoredAuth?> load() async {
    String? value;
    try {
      value = await storage.read(key);
    } catch (_) {
      throw const SecureSessionException('无法读取系统安全存储');
    }
    if (value == null) return null;
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final server = FlowApi(Uri.parse(json['server'] as String)).baseUrl;
      final token = json['token'] as String;
      final user = AccountUser.fromJson(json['user'] as Map<String, dynamic>);
      if (token.isEmpty || user.id.isEmpty || user.email.isEmpty) {
        throw const FormatException();
      }
      return StoredAuth(server, AuthSession(token: token, user: user));
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> clear() async {
    try {
      await storage.delete(key);
    } catch (_) {
      throw const SecureSessionException('无法清除系统安全存储中的会话');
    }
  }
}
