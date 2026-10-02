import 'dart:io';
import 'package:flowday/data/api_client.dart';
import 'package:flowday/domain/models.dart';

Future<void> main() async {
  final api = FlowApi(Uri.parse('http://127.0.0.1:3109'));
  final email = Platform.environment['FLOWDAY_SMOKE_EMAIL'];
  final code = Platform.environment['FLOWDAY_SMOKE_VERIFICATION_CODE'];
  if (email == null || code == null) {
    throw StateError(
      'Set FLOWDAY_SMOKE_EMAIL and FLOWDAY_SMOKE_VERIFICATION_CODE to a recipient and its delivered code',
    );
  }
  final session = await api.register(
    email,
    'Temporary-test-927!',
    '联调测试',
    verificationCode: code,
  );
  final initial = await api.getWorkspace(session.token);
  final data = FlowData.fromJson(initial.data!);
  data.tasks.add(Task(id: 'smoke-task', title: '客户端与服务端联调'));
  final version = await api.putWorkspace(
    session.token,
    initial.version,
    data.toJson(),
  );
  final saved = await api.getWorkspace(session.token);
  if (saved.version != version ||
      FlowData.fromJson(saved.data!).tasks.single.title != '客户端与服务端联调') {
    throw StateError('Workspace round trip failed');
  }
  try {
    await api.putWorkspace(session.token, initial.version, data.toJson());
    throw StateError('Stale write was accepted');
  } on ApiException catch (error) {
    if (error.status != 409) rethrow;
  }
  await api.logout(session.token);
  stdout.writeln(
    'PASS: register, authenticated read/write, Dart JSON compatibility, CAS conflict, logout',
  );
}
