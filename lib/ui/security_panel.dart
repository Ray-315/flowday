import 'package:flutter/material.dart';
import '../data/api_client.dart';
import '../data/sync_controller.dart';
import 'theme.dart';

Future<void> showAccountForm(
  BuildContext context, {
  required String title,
  required List<String> labels,
  required Future<void> Function(List<String>) submit,
  List<String>? initial,
  bool secret = false,
  bool destructive = false,
}) async {
  final fields = List.generate(
    labels.length,
    (i) => TextEditingController(text: initial?[i] ?? ''),
  );
  String? error;
  bool busy = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (destructive)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('账号及服务器上的全部数据将被永久删除，此操作不可恢复。'),
                  ),
                for (var i = 0; i < fields.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: fields[i],
                      enabled: !busy,
                      obscureText: secret,
                      decoration: InputDecoration(labelText: labels[i]),
                    ),
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      update(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await submit(fields.map((f) => f.text).toList());
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        if (dialogContext.mounted) {
                          update(() {
                            busy = false;
                            error = e is ApiException
                                ? e.message
                                : e is FormatException
                                ? e.message
                                : '操作失败，请重试';
                          });
                        }
                      }
                    },
              child: Text(
                busy
                    ? '处理中…'
                    : destructive
                    ? '永久注销账号'
                    : '保存',
              ),
            ),
          ],
        ),
      ),
    ),
  );
  // The dialog route may still be animating out when showDialog completes.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  for (final field in fields) {
    field.dispose();
  }
}

Future<void> showPasswordForm(
  BuildContext context,
  SyncController controller,
) => showAccountForm(
  context,
  title: '修改密码',
  labels: ['当前密码', '新密码（至少 10 位）', '确认新密码'],
  secret: true,
  submit: (values) async {
    if (values[1].length < 10 || values[1].length > 256) {
      throw const FormatException('新密码需为 10 至 256 位');
    }
    if (values[1] != values[2]) throw const FormatException('两次输入的新密码不一致');
    await controller.api.changePassword(
      controller.session.token,
      values[0],
      values[1],
    );
  },
);

class SecurityPanel extends StatelessWidget {
  final SyncController controller;
  final Future<void> Function() onLogout;
  const SecurityPanel({
    super.key,
    required this.controller,
    required this.onLogout,
  });

  Future<void> _sessions(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _SessionsDialog(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '账号与数据安全',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline),
          title: const Text('修改密码'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showPasswordForm(context, controller),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.devices_outlined),
          title: const Text('登录会话管理'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _sessions(context),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.delete_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            '注销账号',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            bool deleted = false;
            await showAccountForm(
              context,
              title: '注销账号',
              labels: ['当前密码'],
              secret: true,
              destructive: true,
              submit: (values) async {
                await controller.api.deleteAccount(
                  controller.session.token,
                  values[0],
                );
                controller.setAutoSync(false);
                deleted = true;
              },
            );
            if (deleted) await onLogout();
          },
        ),
      ],
    ),
  );
}

class _SessionsDialog extends StatefulWidget {
  final SyncController controller;
  const _SessionsDialog({required this.controller});
  @override
  State<_SessionsDialog> createState() => _SessionsDialogState();
}

class _SessionsDialogState extends State<_SessionsDialog> {
  List<Map<String, dynamic>>? sessions;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool revoke = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final c = widget.controller;
      if (revoke) await c.api.revokeOtherSessions(c.session.token);
      final result = await c.api.listSessions(c.session.token);
      if (mounted) setState(() => sessions = result);
    } catch (e) {
      if (mounted) {
        setState(() => error = e is ApiException ? e.message : '无法读取登录会话');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('登录会话管理'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) const LinearProgressIndicator(),
            for (final session in sessions ?? <Map<String, dynamic>>[])
              ListTile(
                leading: Icon(
                  session['current'] == true ? Icons.computer : Icons.devices,
                ),
                title: Text(session['current'] == true ? '当前会话' : '其他登录会话'),
                subtitle: Text(
                  '有效期至 ${DateTime.parse(session['expiresAt'] as String).toLocal().toString().substring(0, 16)}',
                ),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => _load(revoke: true),
        child: const Text('退出其他会话'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
