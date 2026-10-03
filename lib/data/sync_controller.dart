import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../domain/models.dart';
import '../domain/store.dart';
import 'api_client.dart';

class SyncController extends ChangeNotifier {
  final FlowApi api;
  final AuthSession session;
  final FlowStore store;
  final Future<void> Function()? beforeReplace;
  final Future<void> Function(int version, String json)? saveBaseline;
  int? baseVersion;
  String? lastSyncedJson;
  DateTime? lastSync;
  String? error;
  bool busy = false, conflict = false, autoSync = false;
  bool _disposed = false;
  Timer? _timer;
  SyncController({
    required this.api,
    required this.session,
    required this.store,
    this.beforeReplace,
    this.saveBaseline,
    this.baseVersion,
    this.lastSyncedJson,
  }) {
    store.addListener(_changed);
  }
  String get _json => jsonEncode(store.data.toJson());
  bool get localDirty => lastSyncedJson == null || _json != lastSyncedJson;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _changed() {
    _notify();
  }

  void setAutoSync(bool value) {
    autoSync = value;
    _timer?.cancel();
    if (value) {
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!conflict) unawaited(sync());
      });
      unawaited(sync());
    }
    _notify();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    _notify();
    try {
      await operation();
      if (!_disposed &&
          !conflict &&
          baseVersion != null &&
          lastSyncedJson != null) {
        await saveBaseline?.call(baseVersion!, lastSyncedJson!);
      }
    } on ApiException catch (e) {
      if (e.status == 409) conflict = true;
      if (e.status == 401) {
        autoSync = false;
        _timer?.cancel();
      }
      error = e.message;
    } catch (_) {
      error = '同步失败，数据已保留，请重试';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _replace(WorkspaceSnapshot remote, String expected) async {
    final next = remote.data ?? FlowData().toJson();
    final normalized = jsonEncode(FlowData.fromJson(next).toJson());
    if (_json != expected) {
      conflict = true;
      return;
    }
    await beforeReplace?.call();
    if (_disposed) return;
    if (_json != expected) {
      conflict = true;
      return;
    }
    await store.importJson(normalized);
    if (_disposed) return;
    baseVersion = remote.version;
    lastSyncedJson = normalized;
    conflict = false;
    lastSync = DateTime.now();
  }

  Future<void> _upload(int version) async {
    final sent = _json;
    final nextVersion = await api.putWorkspace(
      session.token,
      version,
      jsonDecode(sent) as Map<String, dynamic>,
    );
    if (_disposed) return;
    baseVersion = nextVersion;
    lastSyncedJson = sent;
    conflict = false;
    lastSync = DateTime.now();
  }

  Future<void> sync() => _run(() async {
    if (conflict) return;
    final before = _json;
    final remote = await api.getWorkspace(session.token);
    if (_disposed) return;
    final remoteJson = jsonEncode(
      FlowData.fromJson(remote.data ?? FlowData().toJson()).toJson(),
    );
    if (_json == remoteJson) {
      baseVersion = remote.version;
      lastSyncedJson = remoteJson;
      lastSync = DateTime.now();
      return;
    }
    if (baseVersion == null) {
      if (before == jsonEncode(FlowData().toJson())) {
        await _replace(remote, before);
      } else {
        conflict = true;
      }
      return;
    }
    if (remote.version != baseVersion) {
      if (localDirty) {
        conflict = true;
        return;
      }
      await _replace(remote, before);
    } else if (localDirty) {
      await _upload(remote.version);
    } else {
      lastSync = DateTime.now();
    }
  });
  Future<void> resolveUseServer() => _run(() async {
    final before = _json;
    final remote = await api.getWorkspace(session.token);
    if (!_disposed) await _replace(remote, before);
  });
  Future<void> resolveUploadLocal() => _run(() async {
    final remote = await api.getWorkspace(session.token);
    if (!_disposed) await _upload(remote.version);
  });
  Future<void> logout() async {
    setAutoSync(false);
    await api.logout(session.token);
  }

  Future<void> remoteMutation(
    Future<void> Function(int version) operation,
  ) async {
    if (busy || conflict) throw StateError('请先完成同步或处理版本冲突');
    await sync();
    if (busy ||
        conflict ||
        error != null ||
        baseVersion == null ||
        localDirty) {
      throw StateError(error ?? '请先完成同步或处理版本冲突');
    }
    await _run(() async {
      final before = _json;
      await operation(baseVersion!);
      final remote = await api.getWorkspace(session.token);
      if (!_disposed) await _replace(remote, before);
    });
    if (error != null || conflict) throw StateError(error ?? '操作已提交，请处理同步冲突');
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    store.removeListener(_changed);
    super.dispose();
  }
}
