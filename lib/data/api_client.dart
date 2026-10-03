import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  final int? currentVersion;
  const ApiException(
    this.status,
    this.code,
    this.message, {
    this.currentVersion,
  });
  @override
  String toString() => message;
}

class ApiResponse {
  final int status;
  final String body;
  const ApiResponse(this.status, this.body);
}

typedef ApiTransport =
    Future<ApiResponse> Function(
      String method,
      Uri url,
      Map<String, String> headers,
      String? body,
    );

class AccountUser {
  final String id, email, displayName;
  const AccountUser({
    required this.id,
    required this.email,
    required this.displayName,
  });
  factory AccountUser.fromJson(Map<String, dynamic> json) => AccountUser(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['displayName'] as String,
  );
}

class AuthSession {
  final String token;
  final AccountUser user;
  const AuthSession({required this.token, required this.user});
}

class WorkspaceSnapshot {
  final int version;
  final Map<String, dynamic>? data;
  const WorkspaceSnapshot(this.version, this.data);
}

class FlowApi {
  final Uri baseUrl;
  final ApiTransport _transport;
  FlowApi(Uri baseUrl, {ApiTransport? transport})
    : baseUrl = _validate(baseUrl),
      _transport = transport ?? _http;

  static Uri _validate(Uri uri) {
    final loopback =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
    if (uri.host.isEmpty ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback)) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('服务器地址必须使用 HTTPS（本机地址可使用 HTTP）');
    }
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    return uri.replace(path: path.endsWith('/api/v1') ? path : '$path/api/v1');
  }

  static Future<ApiResponse> _http(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.openUrl(method, url);
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      if (body != null) request.add(utf8.encode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 20));
      return ApiResponse(response.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? data,
  }) async {
    ApiResponse response;
    try {
      response = await _transport(method, Uri.parse('$baseUrl$path'), {
        if (data != null) 'Content-Type': 'application/json; charset=utf-8',
        if (token != null) 'Authorization': 'Bearer $token',
      }, data == null ? null : jsonEncode(data));
    } on SocketException {
      throw const ApiException(0, 'NETWORK_ERROR', '无法连接服务器，请检查网络和服务器地址');
    } on TimeoutException {
      throw const ApiException(0, 'TIMEOUT', '服务器响应超时，请重试');
    } on HttpException {
      throw const ApiException(0, 'NETWORK_ERROR', '网络请求失败，请重试');
    } on HandshakeException {
      throw const ApiException(0, 'TLS_ERROR', '无法验证服务器安全连接');
    }
    Map<String, dynamic> decoded = {};
    try {
      if (response.body.isNotEmpty) {
        decoded = jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {
      throw ApiException(response.status, 'INVALID_RESPONSE', '服务器返回了无效数据');
    }
    if (response.status < 200 || response.status >= 300) {
      final error = decoded['error'] is Map<String, dynamic>
          ? decoded['error'] as Map<String, dynamic>
          : decoded;
      throw ApiException(
        response.status,
        error['code'] as String? ?? 'HTTP_ERROR',
        error['message'] as String? ?? '请求失败（${response.status}）',
        currentVersion:
            (error['currentVersion'] ?? decoded['currentVersion']) as int?,
      );
    }
    return decoded;
  }

  Future<AuthSession> _authenticate(
    String route,
    Map<String, dynamic> data,
  ) async {
    final result = await _request('POST', '/auth/$route', data: data);
    return AuthSession(
      token: result['token'] as String,
      user: AccountUser.fromJson(result['user'] as Map<String, dynamic>),
    );
  }

  Future<AuthSession> login(String email, String password) =>
      _authenticate('login', {'email': email, 'password': password});
  Future<AuthSession> register(
    String email,
    String password,
    String displayName, {
    required String verificationCode,
  }) => _authenticate('register', {
    'email': email,
    'password': password,
    'displayName': displayName,
    'verificationCode': verificationCode,
  });
  Future<void> sendRegistrationCode(String email) async {
    await _request('POST', '/auth/registration-code', data: {'email': email});
  }

  Future<AccountUser> me(String token) async => AccountUser.fromJson(
    (await _request('GET', '/auth/me', token: token))['user']
        as Map<String, dynamic>,
  );
  Future<void> logout(String token) async {
    await _request('POST', '/auth/logout', token: token);
  }

  Future<AccountUser> updateProfile(String token, String displayName) async =>
      AccountUser.fromJson(
        (await _request(
              'PUT',
              '/auth/profile',
              token: token,
              data: {'displayName': displayName},
            ))['user']
            as Map<String, dynamic>,
      );

  Future<void> changePassword(
    String token,
    String currentPassword,
    String newPassword,
  ) async {
    await _request(
      'POST',
      '/auth/password',
      token: token,
      data: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  }

  Future<List<Map<String, dynamic>>> listSessions(String token) async =>
      ((await _request('GET', '/auth/sessions', token: token))['sessions']
              as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();

  Future<void> revokeOtherSessions(String token) async {
    await _request('POST', '/auth/sessions/revoke-others', token: token);
  }

  Future<void> deleteAccount(String token, String password) async {
    await _request(
      'POST',
      '/auth/delete',
      token: token,
      data: {'password': password, 'confirmation': 'DELETE'},
    );
  }

  Future<List<Map<String, dynamic>>> listReminders(String token) async =>
      ((await _request('GET', '/reminders', token: token))['reminders'] as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();

  Future<Map<String, dynamic>> createReminder(
    String token,
    Map<String, dynamic> data,
  ) async =>
      (await _request(
            'POST',
            '/reminders',
            token: token,
            data: data,
          ))['reminder']
          as Map<String, dynamic>;

  Future<void> ackReminder(String token, String id) async {
    await _request(
      'POST',
      '/reminders/${Uri.encodeComponent(id)}/ack',
      token: token,
    );
  }

  Future<WorkspaceSnapshot> getWorkspace(String token) async {
    final result = await _request('GET', '/workspace', token: token);
    return WorkspaceSnapshot(
      result['version'] as int,
      result['data'] as Map<String, dynamic>?,
    );
  }

  Future<int> putWorkspace(
    String token,
    int baseVersion,
    Map<String, dynamic> data,
  ) async =>
      (await _request(
            'PUT',
            '/workspace',
            token: token,
            data: {'baseVersion': baseVersion, 'data': data},
          ))['version']
          as int;

  Future<Map<String, dynamic>> feature(
    String token,
    String method,
    String path, {
    Map<String, dynamic>? data,
  }) => _request(method, path, token: token, data: data);

  Future<Uint8List> download(String token, String path) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl$path'));
      req.followRedirects = false;
      req.headers.set('Authorization', 'Bearer $token');
      final response = await req.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw ApiException(response.statusCode, 'DOWNLOAD_FAILED', '文件下载失败');
      }
      final bytes = BytesBuilder();
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } finally {
      client.close(force: true);
    }
  }
}
