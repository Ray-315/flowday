import 'dart:async';
import 'package:flutter/material.dart';
import 'theme.dart';

class ProfileMenu extends StatefulWidget {
  const ProfileMenu({
    super.key,
    required this.name,
    required this.email,
    required this.onProfile,
    required this.onSettings,
    required this.onSwitch,
    this.onLogout,
  });
  final String name, email;
  final VoidCallback onProfile, onSettings, onSwitch;
  final Future<void> Function()? onLogout;
  @override
  State<ProfileMenu> createState() => _ProfileMenuState();
}

class _ProfileMenuState extends State<ProfileMenu> {
  final controller = MenuController();
  Timer? closing;
  void enter() {
    closing?.cancel();
    controller.open();
  }

  void leave() {
    closing?.cancel();
    closing = Timer(const Duration(milliseconds: 250), () {
      if (mounted) controller.close();
    });
  }

  void choose(VoidCallback callback) {
    controller.close();
    callback();
  }

  @override
  void dispose() {
    closing?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: controller,
    alignmentOffset: const Offset(-220, 8),
    style: const MenuStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
    menuChildren: [
      MouseRegion(
        onEnter: (_) => closing?.cancel(),
        onExit: (_) => leave(),
        child: SizedBox(
          width: 270,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    avatar(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.name.isEmpty ? '本地账号' : widget.name,
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (widget.email.isNotEmpty)
                            Text(
                              widget.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
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
              const Divider(height: 1),
              MenuItemButton(
                leadingIcon: const Icon(Icons.person_outline),
                onPressed: () => choose(widget.onProfile),
                child: const Text('个人资料'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.settings_outlined),
                onPressed: () => choose(widget.onSettings),
                child: const Text('设置'),
              ),
              const Divider(height: 1),
              MenuItemButton(
                leadingIcon: const Icon(Icons.swap_horiz),
                onPressed: () => choose(widget.onSwitch),
                child: Text(widget.onLogout == null ? '登录账号' : '切换账号'),
              ),
              if (widget.onLogout != null)
                MenuItemButton(
                  leadingIcon: const Icon(
                    Icons.logout,
                    color: Colors.redAccent,
                  ),
                  onPressed: () async {
                    controller.close();
                    try {
                      await widget.onLogout!();
                    } catch (e) {
                      if (context.mounted) await showFailure(context, e);
                    }
                  },
                  child: const Text(
                    '退出登录',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    ],
    builder: (context, controller, child) => MouseRegion(
      onEnter: (_) => enter(),
      onExit: (_) => leave(),
      child: InkWell(
        key: const Key('profile-menu'),
        onTap: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
        customBorder: const CircleBorder(),
        child: avatar(),
      ),
    ),
  );
  Widget avatar() => CircleAvatar(
    radius: 18,
    backgroundColor: palette[2].withValues(alpha: .18),
    child: widget.name.isEmpty
        ? Icon(Icons.person_outline, color: palette[2], size: 22)
        : Text(
            widget.name.characters.first,
            style: TextStyle(color: palette[2], fontWeight: FontWeight.w700),
          ),
  );
}
