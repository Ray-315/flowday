import 'package:flutter/material.dart';
import '../data/sync_controller.dart';
import 'theme.dart';

class IntegrationsPanel extends StatefulWidget {
  const IntegrationsPanel({super.key, required this.sync});
  final SyncController sync;
  @override
  State<IntegrationsPanel> createState() => _IntegrationsPanelState();
}

class _IntegrationsPanelState extends State<IntegrationsPanel> {
  final webhook = TextEditingController(),
      secret = TextEditingController(),
      username = TextEditingController(),
      password = TextEditingController();
  List<Map> calendars = [], backups = [];
  Map apple = {}, feishu = {};
  String? calendar, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    for (final c in [webhook, secret, username, password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> api(
    String method,
    String path, {
    Map<String, dynamic>? data,
  }) => widget.sync.api.feature(
    widget.sync.session.token,
    method,
    path,
    data: data,
  );
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

  Future<void> load() async {
    final f = await api('GET', '/integrations/feishu');
    final a = await api('GET', '/integrations/apple');
    final b = await api('GET', '/backups');
    if (mounted) {
      setState(() {
        feishu = f;
        apple = a;
        backups = (b['backups'] as List).cast<Map>();
      });
    }
  }

  Future<void> refresh() => run(load);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              '飞书通知',
              action: IconButton(
                onPressed: busy ? null : refresh,
                icon: const Icon(Icons.refresh),
              ),
            ),
            Text(feishu['configured'] == true ? '已连接' : '未连接'),
            const SizedBox(height: 16),
            TextField(
              controller: webhook,
              decoration: const InputDecoration(labelText: '机器人 Webhook'),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: secret,
              decoration: const InputDecoration(labelText: '签名密钥'),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          await api(
                            'PUT',
                            '/integrations/feishu',
                            data: {
                              'webhookUrl': webhook.text.trim(),
                              if (secret.text.isNotEmpty) 'secret': secret.text,
                            },
                          );
                          webhook.clear();
                          secret.clear();
                          await load();
                        }),
                  child: const Text('保存'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          await api('POST', '/integrations/feishu/test');
                        }),
                  child: const Text('发送测试'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          if (await confirm(context, '断开飞书', '停止向此机器人发送提醒？')) {
                            await api(
                              'POST',
                              '/integrations/feishu/disconnect',
                            );
                            await load();
                          }
                        }),
                  child: const Text('断开'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle('Apple 日历'),
            Text(apple['configured'] == true ? '已连接' : '未连接'),
            const SizedBox(height: 16),
            TextField(
              controller: username,
              decoration: const InputDecoration(labelText: 'Apple 账号'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              decoration: const InputDecoration(labelText: 'App 专用密码'),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            if (calendars.isNotEmpty) ...[
              FlowSelect<String>(
                initialValue: calendar,
                items: calendars
                    .map(
                      (c) => DropdownMenuItem(
                        value: c['url'] as String,
                        child: Text('${c['displayName'] ?? c['url']}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => calendar = v),
                decoration: const InputDecoration(labelText: '日历'),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          final r = await api(
                            'POST',
                            '/integrations/apple/discover',
                            data: {
                              'username': username.text.trim(),
                              'password': password.text,
                            },
                          );
                          if (mounted) {
                            setState(() {
                              calendars = (r['calendars'] as List).cast<Map>();
                              calendar =
                                  calendars.firstOrNull?['url'] as String?;
                            });
                          }
                        }),
                  child: const Text('读取日历'),
                ),
                FilledButton(
                  onPressed: busy || calendar == null
                      ? null
                      : () => run(() async {
                          await api(
                            'PUT',
                            '/integrations/apple',
                            data: {
                              'username': username.text.trim(),
                              'password': password.text,
                              'calendarUrl': calendar,
                            },
                          );
                          password.clear();
                          await load();
                        }),
                  child: const Text('连接'),
                ),
                OutlinedButton(
                  onPressed: busy || apple['configured'] != true
                      ? null
                      : () => run(() async {
                          await widget.sync.remoteMutation((_) async {
                            await api(
                              'POST',
                              '/integrations/apple/sync',
                              data: {},
                            );
                          });
                          await load();
                        }),
                  child: const Text('立即同步'),
                ),
                TextButton(
                  onPressed: busy || apple['configured'] != true
                      ? null
                      : () => run(() async {
                          if (await confirm(context, '断开日历', '停止同步并保留本地日程？')) {
                            await api(
                              'POST',
                              '/integrations/apple/disconnect',
                              data: {'keepLocal': true},
                            );
                            await load();
                          }
                        }),
                  child: const Text('断开'),
                ),
              ],
            ),
            for (final conflict
                in (apple['conflicts'] as List? ?? []).cast<Map>())
              ListTile(
                title: Text(
                  '${(conflict['local'] as Map?)?['title'] ?? (conflict['remote'] as Map?)?['title'] ?? '日历冲突'}',
                ),
                subtitle: Text(
                  '本地：${(conflict['local'] as Map?)?['start'] ?? '已删除'}\nApple：${conflict['remoteDeleted'] == true ? '已删除' : (conflict['remote'] as Map?)?['start']}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (choice) => run(() async {
                    await widget.sync.remoteMutation((version) async {
                      await api(
                        'POST',
                        '/integrations/apple/conflicts/${conflict['id']}/resolve',
                        data: {'choice': choice, 'baseVersion': version},
                      );
                    });
                    await load();
                  }),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'local', child: Text('保留本地')),
                    const PopupMenuItem(
                      value: 'remote',
                      child: Text('保留 Apple'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle(
              '服务器备份',
              action: TextButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        await widget.sync.sync();
                        await api('POST', '/backups');
                        await load();
                      }),
                child: const Text('立即备份'),
              ),
            ),
            for (final backup in backups)
              ListTile(
                title: Text('${backup['createdAt']}'),
                subtitle: Text('版本 ${backup['version']}'),
                trailing: TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          final preview = await api(
                            'POST',
                            '/backups/restore-preview',
                            data: {'at': backup['createdAt']},
                          );
                          if (!context.mounted) return;
                          final changes = (preview['changes'] as List)
                              .cast<Map>()
                              .map(
                                (c) =>
                                    '${c['collection']}: ${c['currentCount']} → ${c['restoredCount']}',
                              )
                              .join('\n');
                          if (!await confirm(context, '恢复备份', changes)) return;
                          await widget.sync.remoteMutation((version) async {
                            await api(
                              'POST',
                              '/backups/${preview['backupId']}/restore',
                              data: {'baseVersion': version},
                            );
                          });
                          await load();
                        }),
                  child: const Text('恢复'),
                ),
              ),
          ],
        ),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}
