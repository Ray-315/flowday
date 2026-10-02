import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../data/sync_controller.dart';
import 'theme.dart';

class AttachmentsPanel extends StatefulWidget {
  const AttachmentsPanel({
    super.key,
    required this.sync,
    required this.ownerType,
    required this.ownerId,
  });
  final SyncController sync;
  final String ownerType, ownerId;
  @override
  State<AttachmentsPanel> createState() => _AttachmentsPanelState();
}

class _AttachmentsPanelState extends State<AttachmentsPanel> {
  List<Map> items = [];
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    run(load);
  }

  Future<void> load() async {
    final result = await widget.sync.api.feature(
      widget.sync.session.token,
      'GET',
      '/attachments',
    );
    if (mounted) {
      setState(
        () => items = (result['attachments'] as List)
            .cast<Map>()
            .where(
              (a) =>
                  a['ownerId'] == widget.ownerId &&
                  a['ownerType'] == widget.ownerType,
            )
            .toList(),
      );
    }
  }

  Future<void> run(Future<void> Function() fn) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> add(String kind) async {
    Map<String, dynamic> data = {
      'ownerType': widget.ownerType,
      'ownerId': widget.ownerId,
      'kind': kind,
    };
    if (kind == 'file') {
      final file = await openFile();
      if (file == null) return;
      if (await file.length() > 1024 * 1024) throw StateError('附件不能超过 1 MiB');
      data.addAll({
        'name': file.name,
        'mediaType': file.mimeType ?? 'application/octet-stream',
        'contentBase64': base64Encode(await file.readAsBytes()),
      });
    } else {
      final name = TextEditingController(), content = TextEditingController();
      final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(kind == 'url' ? '添加链接' : '添加笔记'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: content,
                  minLines: kind == 'url' ? 1 : 4,
                  maxLines: kind == 'url' ? 1 : 8,
                  decoration: InputDecoration(
                    labelText: kind == 'url' ? 'URL' : 'Markdown',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (accepted == true) {
        data.addAll({
          'name': name.text.trim(),
          kind == 'url' ? 'url' : 'markdown': content.text,
        });
      }
      name.dispose();
      content.dispose();
      if (accepted != true) return;
    }
    await widget.sync.sync();
    if (widget.sync.error != null ||
        widget.sync.conflict ||
        widget.sync.localDirty) {
      throw StateError(widget.sync.error ?? '请先同步');
    }
    await widget.sync.api.feature(
      widget.sync.session.token,
      'POST',
      '/attachments',
      data: data,
    );
    await load();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionTitle(
        '附件与资料',
        action: PopupMenuButton<String>(
          enabled: !busy,
          onSelected: (v) => run(() => add(v)),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'file', child: Text('文件')),
            const PopupMenuItem(value: 'url', child: Text('链接')),
            const PopupMenuItem(value: 'markdown', child: Text('笔记')),
          ],
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.add, size: 18),
          ),
        ),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      for (final item in items)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${item['name']}'),
          leading: Icon(
            item['kind'] == 'file'
                ? Icons.attach_file
                : item['kind'] == 'url'
                ? Icons.link
                : Icons.notes,
          ),
          onTap: busy
              ? null
              : () => run(() async {
                  if (item['kind'] == 'file') {
                    String? destination;
                    if (Platform.isAndroid || Platform.isIOS) {
                      final directory =
                          await getApplicationDocumentsDirectory();
                      destination =
                          '${directory.path}/${item['id']}-${Uri.encodeComponent('${item['name']}')}';
                    } else {
                      destination = (await getSaveLocation(
                        suggestedName: '${item['name']}',
                      ))?.path;
                    }
                    if (destination == null) return;
                    final bytes = await widget.sync.api.download(
                      widget.sync.session.token,
                      '/attachments/${item['id']}/download',
                    );
                    await File(destination).writeAsBytes(bytes, flush: true);
                  } else {
                    await showDialog<void>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text('${item['name']}'),
                        content: SizedBox(
                          width: 480,
                          child: SingleChildScrollView(
                            child: SelectableText(
                              '${item['url'] ?? item['markdown'] ?? ''}',
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    );
                  }
                }),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: busy
                ? null
                : () => run(() async {
                    if (!await confirm(
                      context,
                      '移除附件',
                      '移除 ${item['name']}？',
                    )) {
                      return;
                    }
                    await widget.sync.api.feature(
                      widget.sync.session.token,
                      'POST',
                      '/attachments/${item['id']}/delete',
                    );
                    await load();
                  }),
          ),
        ),
    ],
  );
}
