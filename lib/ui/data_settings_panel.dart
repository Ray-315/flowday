import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../data/backup_service.dart';
import '../domain/store.dart';
import '../data/sync_controller.dart';
import 'integrations_panel.dart';
import 'theme.dart';

class DataSettingsPanel extends StatefulWidget {
  const DataSettingsPanel({
    super.key,
    required this.store,
    required this.directory,
    this.compact = false,
    this.sync,
  });
  final FlowStore store;
  final Directory directory;
  final bool compact;
  final SyncController? sync;
  @override
  State<DataSettingsPanel> createState() => _DataSettingsPanelState();
}

class _DataSettingsPanelState extends State<DataSettingsPanel> {
  bool busy = false;
  BackupService get service => BackupService(widget.directory);
  static const types = [
    XTypeGroup(
      label: 'JSON',
      extensions: ['json'],
      uniformTypeIdentifiers: ['public.json'],
    ),
  ];

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) await showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> exportData() async {
    final name = 'FlowDay-${DateTime.now().millisecondsSinceEpoch}.json';
    String? path;
    if (Platform.isAndroid || Platform.isIOS) {
      final exports = Directory('${widget.directory.path}/exports');
      await exports.create(recursive: true);
      path = '${exports.path}/$name';
    } else {
      path = (await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: types,
      ))?.path;
    }
    if (path == null) return;
    await File(path).writeAsString(widget.store.exportJson(), flush: true);
    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导出完成'),
          content: SelectableText(path!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> cloudExport(String format, {String collection='tasks'}) async {
    final c = widget.sync!;
    await c.sync();
    if (c.error != null || c.conflict) throw StateError(c.error ?? '请先解决同步冲突');
    final bytes = format == 'json'
        ? utf8.encode(
            jsonEncode(
              await c.api.feature(c.session.token, 'GET', '/export/archive'),
            ),
          )
        : await c.api.download(c.session.token, '/export/csv?collection=$collection');
    final name = 'FlowDay-${DateTime.now().millisecondsSinceEpoch}.$format';
    String? path;
    if (Platform.isAndroid || Platform.isIOS) {
      final exports = Directory('${widget.directory.path}/exports');
      await exports.create(recursive: true);
      path = '${exports.path}/$name';
    } else {
      path = (await getSaveLocation(suggestedName: name))?.path;
    }
    if (path != null) await File(path).writeAsBytes(bytes, flush: true);
  }

  Future<void> restore(String source) async {
    final preview = BackupService.decode(source);
    if (!mounted) return;
    if (!await confirm(
      context,
      '恢复数据',
      '将替换当前数据：${preview.projects.length} 个项目、${preview.tasks.length} 个任务、${preview.events.length} 个日程。恢复前会备份当前数据。',
    )) {
      return;
    }
    await service.restore(widget.store, source);
  }

  Future<void> importData() async {
    final file = await openFile(acceptedTypeGroups: types);
    if (file == null) return;
    final source = await file.readAsString();
    final decoded = jsonDecode(source);
    if (decoded is Map &&
        decoded['workspace'] is Map &&
        decoded['attachments'] is List) {
      final sync = widget.sync;
      if (sync == null) throw StateError('请先登录再恢复含附件的云端备份');
      final workspace = BackupService.decode(jsonEncode(decoded['workspace']));
      if (!mounted ||
          !await confirm(
            context,
            '恢复云端数据',
            '将替换 ${workspace.tasks.length} 个任务、${workspace.events.length} 个日程、${workspace.projects.length} 个项目和 ${(decoded['attachments'] as List).length} 个附件。恢复前会备份当前云端数据。',
          )) {
        return;
      }
      await sync.remoteMutation((version) async {
        await sync.api.feature(
          sync.session.token,
          'POST',
          '/import/archive',
          data: {'baseVersion': version, 'archive': decoded},
        );
      });
    } else {
      await restore(source);
    }
  }

  Future<void> backups() async {
    final files = await service.list();
    final dates = await Future.wait(files.map((file) => file.lastModified()));
    if (!mounted) return;
    final selected = await showDialog<File>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('备份与恢复'),
        content: SizedBox(
          width: 480,
          height: 320,
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, index) => ListTile(
              leading: const Icon(Icons.history),
              title: Text(
                '${dateText(dates[index])} ${clockText(dates[index])}',
              ),
              subtitle: Text(
                files[index].uri.pathSegments.last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.restore),
              onTap: () => Navigator.pop(context, files[index]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, File('')),
            child: const Text('立即备份'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    if (selected.path.isEmpty) {
      await service.create(widget.store.data);
    } else {
      await restore(await selected.readAsString());
    }
  }

  Future<void> cleanup() async {
    var tasks = true;
    var events = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('清除指定数据'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('已完成任务'),
                value: tasks,
                onChanged: (value) => update(() => tasks = value!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('已结束日程'),
                value: events,
                onChanged: (value) => update(() => events = value!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: tasks || events
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('移入回收站'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      await service.cleanup(
        widget.store,
        completedTasks: tasks,
        pastEvents: events,
      );
    }
  }

  Future<void> clear() async {
    var typed = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('删除全部数据'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('将删除当前账号的全部业务数据，保留设置，并在删除前创建本地备份。'),
              const SizedBox(height: 16),
              TextField(
                autofocus: true,
                decoration: const InputDecoration(labelText: '输入“删除全部数据”确认'),
                onChanged: (value) => update(() => typed = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: typed == '删除全部数据'
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) await service.clear(widget.store);
  }

  Widget action(
    IconData icon,
    String title,
    Future<void> Function() callback, {
    Color? color,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: color ?? Theme.of(context).colorScheme.primary),
    title: Text(title, style: TextStyle(color: color)),
    trailing: const Icon(Icons.chevron_right),
    onTap: busy ? null : () => run(callback),
  );

  Widget section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [SectionTitle(title), ...children],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final data = widget.store.data;
      final bytes = utf8.encode(widget.store.exportJson()).length;
      final size = bytes < 1024
          ? '$bytes B'
          : bytes < 1024 * 1024
          ? '${(bytes / 1024).toStringAsFixed(1)} KB'
          : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      final counts = [
        (
          Icons.event_note,
          '日程数据',
          '${data.events.where((e) => e.deletedAt == null).length} 条',
        ),
        (
          Icons.task_alt,
          '任务数据',
          '${data.tasks.where((t) => t.deletedAt == null).length} 条',
        ),
        (
          Icons.folder_outlined,
          '项目数据',
          '${data.projects.where((p) => p.deletedAt == null).length} 个',
        ),
        (Icons.storage_outlined, '数据大小', size),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.compact)
            section('数据概览', [
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 700
                      ? 4
                      : constraints.maxWidth >= 280
                      ? 2
                      : 1;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: counts
                        .map(
                          (item) => Container(
                            width:
                                (constraints.maxWidth - (columns - 1) * 12) /
                                columns,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  item.$1,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 24,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.$2),
                                      Text(
                                        item.$3,
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ]),
          section('数据管理', [
            action(Icons.upload_file, '导出全部数据', exportData),
            if (widget.sync != null) ...[
              action(
                Icons.file_download_outlined,
                '导出云端数据与附件',
                () => cloudExport('json'),
              ),
              action(
                Icons.table_chart_outlined,
                '导出任务 CSV',
                () => cloudExport('csv'),
              ),
              action(Icons.calendar_month_outlined,'导出日程 CSV',()=>cloudExport('csv',collection:'events')),
              action(Icons.bar_chart,'导出统计 CSV',()=>cloudExport('csv',collection:'statistics')),
              action(
                Icons.cloud_outlined,
                '云端备份与恢复',
                () => openEditor(
                  context,
                  Scaffold(
                    appBar: AppBar(title: const Text('云端备份与恢复')),
                    body: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [IntegrationsPanel(sync: widget.sync!)],
                    ),
                  ),
                ),
              ),
            ],
            const Divider(height: 1),
            action(Icons.download_outlined, '导入数据', importData),
            if (!widget.compact) ...[
              const Divider(height: 1),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(
                  Icons.backup_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('每日自动备份'),
                value: data.preferences['automaticBackup'] != false,
                onChanged: busy
                    ? null
                    : (value) => run(() async {
                        final next = BackupService.decode(
                          widget.store.exportJson(),
                        );
                        next.preferences['automaticBackup'] = value;
                        await widget.store.importJson(
                          jsonEncode(next.toJson()),
                        );
                      }),
              ),
              const Divider(height: 1),
              action(Icons.history, '备份与恢复', backups),
              const Divider(height: 1),
              action(Icons.delete_outline, '清除指定数据', cleanup),
            ],
          ]),
          if (!widget.compact)
            section('危险区域', [
              action(
                Icons.delete_forever_outlined,
                '删除全部数据',
                clear,
                color: Theme.of(context).colorScheme.error,
              ),
            ]),
        ],
      );
    },
  );
}
