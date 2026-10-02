import 'package:flutter/material.dart';
import '../data/sync_controller.dart';
import 'theme.dart';
import 'security_panel.dart';

class AccountPanel extends StatelessWidget {
  final SyncController controller;
  final Future<void> Function() onLogout;
  const AccountPanel({
    super.key,
    required this.controller,
    required this.onLogout,
  });
  Future<void> _resolve(BuildContext context, bool useServer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(useServer ? '使用服务器数据？' : '上传本地数据？'),
        content: Text(
          useServer ? '当前账号的本地数据将由服务器数据替换。' : '服务器上的数据将由当前账号的本地数据替换。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (useServer) {
        await controller.resolveUseServer();
      } else {
        await controller.resolveUploadLocal();
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final user = controller.session.user;
      final displayName =
          controller.store.data.preferences['displayName'] as String? ??
          user.displayName;
      final status = controller.busy
          ? '正在同步'
          : controller.conflict
          ? '数据冲突'
          : controller.error != null
          ? '同步失败'
          : controller.localDirty
          ? '有待同步的更改'
          : '已同步';
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '账号信息',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: .12),
                  child: Text(
                    displayName.isEmpty ? 'F' : displayName.characters.first,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        user.email,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => showAccountForm(
                    context,
                    title: '编辑资料',
                    labels: ['昵称'],
                    initial: [displayName],
                    submit: (values) async {
                      final updated = await controller.api.updateProfile(
                        controller.session.token,
                        values[0].trim(),
                      );
                      controller.store.data.preferences['displayName'] =
                          updated.displayName;
                      controller.store.changed();
                      await controller.store.persist();
                    },
                  ),
                  child: const Text('编辑资料'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.email_outlined),
              title: const Text('账号邮箱'),
              trailing: Text(
                user.email,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: const Text('密码'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showPasswordForm(context, controller),
            ),
            const Divider(height: 32),
            const Text(
              '跨设备同步',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text(status)),
                OutlinedButton(
                  onPressed: controller.busy || controller.conflict
                      ? null
                      : controller.sync,
                  child: const Text('立即同步'),
                ),
              ],
            ),
            if (controller.lastSync != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '上次同步 ${shortDate(controller.lastSync!)} ${clockText(controller.lastSync!)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自动同步'),
              value: controller.autoSync,
              onChanged: controller.setAutoSync,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: controller.busy ? null : onLogout,
                child: const Text('退出登录'),
              ),
            ),
            if (controller.error != null)
              Text(
                controller.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (controller.conflict)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: controller.busy
                          ? null
                          : () => _resolve(context, true),
                      child: const Text('使用服务器数据'),
                    ),
                    OutlinedButton(
                      onPressed: controller.busy
                          ? null
                          : () => _resolve(context, false),
                      child: const Text('上传本地数据'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
