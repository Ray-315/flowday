import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../domain/models.dart' show TaskStatus;
import '../domain/store.dart';
import 'api_client.dart';

class NotificationPlan {
  const NotificationPlan({
    required this.key,
    required this.title,
    required this.due,
    this.body = '',
  });
  final String key, title, body;
  final DateTime due;
  int get id => stableNotificationId(key);
  String get signature => jsonEncode([title, body, due.toIso8601String()]);
}

int stableNotificationId(String value) {
  var hash = 2166136261;
  for (final unit in value.codeUnits) {
    hash = ((hash ^ unit) * 16777619) & 0x7fffffff;
  }
  return hash;
}

abstract interface class NotificationAdapter {
  bool get supportsScheduling;
  Future<bool> initialize();
  Future<bool?> permission();
  Future<bool?> requestPermission();
  Future<List<int>> pendingIds();
  Future<void> show(NotificationPlan plan);
  Future<void> schedule(NotificationPlan plan);
  Future<void> cancel(int id);
}

class PlatformNotificationAdapter implements NotificationAdapter {
  PlatformNotificationAdapter({FlutterLocalNotificationsPlugin? plugin})
    : plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin plugin;
  @override
  bool get supportsScheduling => !Platform.isLinux;
  static const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'flowday_reminders',
      '日程与任务',
      channelDescription: 'FlowDay 日程与任务提醒',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );
  @override
  Future<bool> initialize() async =>
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          linux: LinuxInitializationSettings(defaultActionName: '打开'),
          windows: WindowsInitializationSettings(
            appName: 'FlowDay',
            appUserModelId: 'pro.flowday.flowday',
            guid: 'e0d9199e-55c6-4079-bb51-b7beb7451bcb',
          ),
        ),
      ) ??
      false;
  @override
  Future<bool?> permission() async {
    if (Platform.isAndroid) {
      return plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
    }
    if (Platform.isIOS) {
      return (await plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.checkPermissions())
          ?.isEnabled;
    }
    if (Platform.isMacOS) {
      return (await plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.checkPermissions())
          ?.isEnabled;
    }
    return null;
  }

  @override
  Future<bool?> requestPermission() async {
    if (Platform.isAndroid) {
      return plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    if (Platform.isIOS) {
      return plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    if (Platform.isMacOS) {
      return plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    return permission();
  }

  @override
  Future<List<int>> pendingIds() async =>
      (await plugin.pendingNotificationRequests()).map((r) => r.id).toList();
  @override
  Future<void> show(NotificationPlan plan) => plugin.show(
    id: plan.id,
    title: plan.title,
    body: plan.body.isEmpty ? null : plan.body,
    notificationDetails: details,
    payload: plan.key,
  );
  @override
  Future<void> schedule(NotificationPlan plan) => plugin.zonedSchedule(
    id: plan.id,
    title: plan.title,
    body: plan.body.isEmpty ? null : plan.body,
    scheduledDate: tz.TZDateTime.from(plan.due, tz.UTC),
    notificationDetails: details,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    payload: plan.key,
  );
  @override
  Future<void> cancel(int id) => plugin.cancel(id: id);
}

/// Native schedules run through the OS. Server reminders are polled while open.
class NativeNotifications extends ChangeNotifier {
  NativeNotifications({
    NotificationAdapter? adapter,
    DateTime Function()? clock,
  }) : adapter = adapter ?? PlatformNotificationAdapter(),
       clock = clock ?? DateTime.now;
  static final instance = NativeNotifications();
  final NotificationAdapter adapter;
  final DateTime Function() clock;
  bool ready = false;
  bool? permissionGranted;
  String? error;
  bool get supportsScheduling => adapter.supportsScheduling;
  FlowStore? _store;
  FlowApi? _api;
  String? _token;
  Directory? _directory;
  Timer? _timer, _debounce;
  bool _busy = false, _disposed = false;
  int _generation = 0;
  final _scheduled = <int, String>{}, _delivered = <String>{};
  List<NotificationPlan> _plans = [];
  File? get _receipts => _directory == null
      ? null
      : File('${_directory!.path}/native-notification-receipts.json');
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (ready || _disposed) return;
    try {
      ready = await adapter.initialize();
      if (!ready) {
        error = '系统通知初始化失败';
      } else {
        permissionGranted = await adapter.permission();
        error = null;
      }
    } catch (_) {
      ready = false;
      error = '系统通知暂不可用，请检查系统通知服务';
    }
    _notify();
  }

  Future<bool?> requestPermission() async {
    await initialize();
    if (!ready) return false;
    try {
      permissionGranted = await adapter.requestPermission();
      error = permissionGranted == false ? '系统通知权限未开启' : null;
      if (permissionGranted != false) await refresh();
    } catch (_) {
      error = '无法申请系统通知权限';
    }
    _notify();
    return permissionGranted;
  }

  Future<void> attach(
    FlowStore store, {
    FlowApi? api,
    String? token,
    Directory? directory,
  }) async {
    await detach();
    if (_disposed) return;
    _store = store;
    _api = api;
    _token = token;
    _directory = directory;
    final generation = ++_generation;
    try {
      final file = _receipts;
      if (file != null && await file.exists()) {
        final values = jsonDecode(await file.readAsString());
        if (generation == _generation && values is List) {
          _delivered.addAll(values.whereType<String>());
        }
      }
    } catch (_) {
      /* A missing delivery receipt never changes workspace data. */
    }
    if (generation != _generation) return;
    store.addListener(_changed);
    await initialize();
    await refresh();
    if (generation != _generation) return;
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh()),
    );
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(refresh()),
    );
  }

  static List<NotificationPlan> plan(
    FlowStore store,
    DateTime now, {
    bool includePast = false,
  }) {
    final setting = store.data.preferences['reminderMinutes'];
    final minutes = setting is int && setting >= 0 && setting <= 10080
        ? setting
        : 15;
    final result = <NotificationPlan>[];
    void add(
      NotificationPlan first,
      bool? strong,
      int? interval,
      int? maximum,
    ) {
      final repeat =
          strong ?? (store.data.preferences['strongReminder'] == true);
      final globalInterval = store.data.preferences['reminderInterval'];
      final globalMaximum = store.data.preferences['maxReminders'];
      final gap = (interval ?? (globalInterval is int ? globalInterval : 5))
          .clamp(1, 10080);
      final count = repeat
          ? (maximum ?? (globalMaximum is int ? globalMaximum : 3)).clamp(1, 50)
          : 1;
      for (var index = 0; index < count; index++) {
        result.add(
          NotificationPlan(
            key: index == 0 ? first.key : '${first.key}:repeat:$index',
            title: first.title,
            body: first.body,
            due: first.due.add(Duration(minutes: gap * index)),
          ),
        );
      }
    }

    for (final event in store.events.where((e) => !e.completed)) {
      final starts = <NotificationPlan>[
        if (event.reminderRules == null)
          NotificationPlan(
            key: 'event:${event.id}',
            title: event.title,
            body: event.location,
            due: event.start.subtract(
              Duration(minutes: event.reminderLeadMinutes ?? minutes),
            ),
          )
        else
          for (var index = 0; index < event.reminderRules!.length; index++)
            NotificationPlan(
              key: 'event:${event.id}:rule:$index',
              title: event.title,
              body: event.location,
              due: event.reminderRules![index]['dueAt'] != null
                  ? DateTime.parse(
                      event.reminderRules![index]['dueAt'] as String,
                    )
                  : event.start.subtract(
                      Duration(
                        minutes:
                            event.reminderRules![index]['leadMinutes'] as int,
                      ),
                    ),
            ),
      ];
      for (final first in starts) {
        add(
          first,
          event.strongReminder,
          event.reminderInterval,
          event.maxReminders,
        );
      }
    }
    for (final task in store.tasks.where(
      (t) =>
          t.deadline != null &&
          t.status != TaskStatus.done &&
          t.status != TaskStatus.cancelled,
    )) {
      add(
        NotificationPlan(
          key: 'task:${task.id}',
          title: task.title,
          due: task.deadline!.subtract(Duration(minutes: minutes)),
        ),
        task.strongReminder,
        task.reminderInterval,
        task.maxReminders,
      );
    }
    if (!includePast) result.removeWhere((r) => !r.due.isAfter(now));
    result.sort((a, b) => a.due.compareTo(b.due));
    return includePast ? result : result.take(60).toList();
  }

  Future<void> refresh() async {
    if (_busy ||
        !ready ||
        _store == null ||
        _disposed ||
        permissionGranted == false) {
      return;
    }
    _busy = true;
    final generation = _generation, now = clock();
    final store = _store!, api = _api, token = _token;
    try {
      // Linux lacks native scheduling, so due reminders require the running app.
      if (!supportsScheduling) {
        final current = {
          for (final plan in plan(store, now, includePast: true))
            plan.key: plan.signature,
        };
        for (final item in _plans.where((p) => !p.due.isAfter(now))) {
          if (current[item.key] != item.signature) continue;
          final receipt = '${item.key}:${item.due.toIso8601String()}';
          if (_delivered.contains(receipt)) continue;
          await adapter.show(item);
          if (generation != _generation) return;
          _delivered.add(receipt);
        }
      }
      final plans = plan(store, now);
      if (supportsScheduling) {
        final wanted = plans.map((p) => p.id).toSet();
        final pending = await adapter.pendingIds();
        if (generation != _generation) return;
        for (final id in pending.where((id) => !wanted.contains(id))) {
          await adapter.cancel(id);
          if (generation != _generation) return;
          _scheduled.remove(id);
        }
        for (final item in plans) {
          if (_scheduled[item.id] == item.signature &&
              pending.contains(item.id)) {
            continue;
          }
          await adapter.schedule(item);
          if (generation != _generation) return;
          _scheduled[item.id] = item.signature;
        }
      }
      _plans = plans;
      if (api != null && token != null) {
        final reminders = await api.listReminders(token);
        if (generation != _generation) return;
        for (final item in reminders) {
          final due = DateTime.tryParse(item['dueAt'] as String? ?? '');
          final sent = item['sentCount'] as int? ?? 0;
          if (item['acknowledged'] == true ||
              item['channel'] == 'feishu' ||
              due == null ||
              due.isAfter(now) ||
              sent == 0) {
            continue;
          }
          final key = 'server:${item['id']}:$sent';
          if (_delivered.contains(key)) continue;
          await adapter.show(
            NotificationPlan(
              key: key,
              title: item['title'] as String? ?? '日程提醒',
              due: due,
            ),
          );
          if (generation != _generation) return;
          _delivered.add(key);
        }
      }
      if (_delivered.length > 2000) {
        final keep = _delivered
            .toList()
            .skip(_delivered.length - 2000)
            .toList();
        _delivered
          ..clear()
          ..addAll(keep);
      }
      final file = _receipts;
      if (file != null) {
        await file.parent.create(recursive: true);
        if (generation != _generation) return;
        await file.writeAsString(jsonEncode(_delivered.toList()), flush: true);
      }
      error = null;
    } catch (_) {
      error = '提醒刷新失败，日程与任务数据已保留';
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> detach() async {
    _generation++;
    _timer?.cancel();
    _debounce?.cancel();
    _store?.removeListener(_changed);
    _store = null;
    _api = null;
    _token = null;
    _plans = [];
    _delivered.clear();
    _scheduled.clear();
    _directory = null;
    if (ready && supportsScheduling) {
      try {
        for (final id in await adapter.pendingIds()) {
          await adapter.cancel(id);
        }
      } catch (_) {
        error = '无法取消系统中已安排的通知';
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _debounce?.cancel();
    _store?.removeListener(_changed);
    super.dispose();
  }
}
