import 'dart:convert';
import 'dart:io';

import '../domain/models.dart';
import 'backup_service.dart';

class JsonRepository {
  final Directory directory;
  JsonRepository(this.directory);
  File get _primary => File('${directory.path}/flowday.json');
  File get _previous => File('${directory.path}/flowday.previous.json');
  Future<FlowData> _read(File file) async {
    try {
      return FlowData.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } on FileSystemException {
      rethrow;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('本地数据格式不正确');
    }
  }

  Future<FlowData> load() async {
    if (!await _primary.exists()) {
      if (await _previous.exists()) return _read(_previous);
      return FlowData();
    }
    try {
      return await _read(_primary);
    } catch (_) {
      if (await _previous.exists()) return _read(_previous);
      rethrow;
    }
  }

  Future<void> save(FlowData data) async {
    data.validate();
    final content = jsonEncode(data.toJson());
    await directory.create(recursive: true);
    final temporary = File('${directory.path}/flowday.tmp');
    await temporary.writeAsString(content, flush: true);
    await _read(temporary);
    await BackupService(directory).daily(data);
    if (await _primary.exists()) {
      // Do not replace the last valid backup with a damaged primary file.
      var valid = true;
      try {
        await _read(_primary);
      } on FormatException {
        valid = false;
      }
      if (valid) await _primary.copy(_previous.path);
    }
    // Rename replaces the destination atomically on supported local filesystems.
    await temporary.rename(_primary.path);
  }

  Future<File> backup(FlowData data) async {
    data.validate();
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}/flowday-backup-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    return file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data.toJson()),
      flush: true,
    );
  }
}
