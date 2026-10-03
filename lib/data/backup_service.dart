import 'dart:convert';
import 'dart:io';

import '../domain/models.dart';
import '../domain/store.dart';

class BackupService {
  BackupService(this.directory);
  final Directory directory;
  Directory get _backups => Directory('${directory.path}/backups');

  static FlowData decode(String source) {
    try {
      return FlowData.fromJson(jsonDecode(source) as Map<String, dynamic>);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('数据字段格式不正确');
    }
  }

  Future<File> create(FlowData data, {String kind = 'manual'}) async {
    data.validate();
    await _backups.create(recursive: true);
    final file = File(
      '${_backups.path}/$kind-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    return file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data.toJson()),
      flush: true,
    );
  }

  Future<List<File>> list() async {
    if (!await _backups.exists()) return [];
    final files = await _backups
        .list(followLinks: false)
        .where((item) => item is File && item.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> daily(FlowData data, {DateTime? now}) async {
    if (data.preferences['automaticBackup'] == false) return;
    final date = (now ?? DateTime.now()).toLocal();
    final stamp =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final file = File('${_backups.path}/daily-$stamp.json');
    if (await file.exists()) return;
    data.validate();
    await _backups.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(data.toJson()), flush: true);
    await temporary.rename(file.path);
  }

  Future<void> restore(FlowStore store, String source) async {
    decode(source);
    await _replace(store, store.exportJson(), source, 'before-restore');
  }

  Future<void> _replace(
    FlowStore store,
    String expected,
    String source,
    String kind,
  ) async {
    await create(decode(expected), kind: kind);
    if (store.exportJson() != expected) {
      throw StateError('备份期间数据已发生变化，请重新操作。');
    }
    await store.importJson(source);
  }

  Future<void> cleanup(
    FlowStore store, {
    required bool completedTasks,
    required bool pastEvents,
  }) async {
    final expected = store.exportJson();
    final draft = FlowStore(decode(expected));
    final now = DateTime.now();
    try {
      if (completedTasks) {
        final ids = draft.data.tasks
            .where(
              (task) =>
                  task.deletedAt == null && task.status == TaskStatus.done,
            )
            .map((task) => task.id)
            .toList();
        for (final id in ids) {
          if (draft.data.tasks.firstWhere((task) => task.id == id).deletedAt ==
              null) {
            draft.deleteTask(id);
          }
        }
      }
      if (pastEvents) {
        final ids = draft.events
            .where((event) => event.end.isBefore(now))
            .map((event) => event.id)
            .toList();
        for (final id in ids) {
          draft.deleteEvent(id);
        }
      }
      await _replace(store, expected, draft.exportJson(), 'before-cleanup');
    } finally {
      draft.dispose();
    }
  }

  Future<void> clear(FlowStore store) async {
    final expected = store.exportJson();
    final next = FlowData(
      preferences: Map<String, dynamic>.from(store.data.preferences),
    );
    await _replace(store, expected, jsonEncode(next.toJson()), 'before-clear');
  }
}
