import 'dart:io';
import 'package:flowday/data/api_client.dart';
import 'package:flowday/domain/models.dart';

Future<void> main() async {
  final api = FlowApi(Uri.parse('http://127.0.0.1:3110'));
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
    '设置联调',
    verificationCode: code,
  );
  final other = await api.login(email, 'Temporary-test-927!');
  await api.updateProfile(session.token, '修改后的昵称');
  if ((await api.me(session.token)).displayName != '修改后的昵称') {
    throw StateError('Profile');
  }
  final before = await api.getWorkspace(session.token);
  final data = FlowData.fromJson(before.data!);
  data.preferences.addAll({
    'themeMode': 'dark',
    'brandColor': 0xff237bff,
    'fontScale': 1.15,
    'strongReminder': true,
    'reminderInterval': 10,
    'maxReminders': 5,
  });
  final now = DateTime.now();
  data.events.add(
    CalendarEvent(
      id: 'settings-event',
      title: '设置提醒联调',
      start: now.add(const Duration(hours: 1)),
      end: now.add(const Duration(hours: 2)),
    ),
  );
  await api.putWorkspace(session.token, before.version, data.toJson());
  final reminders = await api.listReminders(session.token);
  if (reminders.single['maxReminders'] != 5 ||
      reminders.single['intervalMinutes'] != 10) {
    throw StateError('Reminder defaults');
  }
  await api.ackReminder(session.token, reminders.single['id'] as String);
  await api.changePassword(
    session.token,
    'Temporary-test-927!',
    'Temporary-new-928!',
  );
  try {
    await api.me(other.token);
    throw StateError('Other session remains');
  } on ApiException catch (e) {
    if (e.status != 401) rethrow;
  }
  await api.deleteAccount(session.token, 'Temporary-new-928!');
  try {
    await api.me(session.token);
    throw StateError('Deleted account remains');
  } on ApiException catch (e) {
    if (e.status != 401) rethrow;
  }
  stdout.writeln(
    'PASS: profile, preferences, event reminder defaults/ACK, password, session revocation, account deletion',
  );
}
