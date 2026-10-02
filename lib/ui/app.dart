import 'dart:ui' show AppExitResponse;
import 'dart:io';
import '../domain/models.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'profile_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../domain/store.dart';
import 'calendar_page.dart';
import 'editors.dart';
import 'overview_pages.dart';
import 'settings_page.dart';
import 'task_pages.dart';
import 'theme.dart';
import 'workflow_page.dart';
import 'today_page.dart';
import 'ai_panel.dart';
import 'global_search_panel.dart';
import 'sync_scope.dart';
import 'attachments_panel.dart';
import '../data/sync_controller.dart';

final _timezonesInitialized = (() {
  tzdata.initializeTimeZones();
  return true;
})();

class FlowDayApp extends StatelessWidget {
  const FlowDayApp({
    super.key,
    required this.store,
    this.sync,
    this.onLogin,
    this.onLogout,
    this.directory,
  });
  final FlowStore store;
  final SyncController? sync;
  final VoidCallback? onLogin;
  final Future<void> Function()? onLogout;
  final Directory? directory;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final p = store.data.preferences;
      if (!_timezonesInitialized) throw StateError('时区初始化失败');
      DisplayPreferences.timezone = p['timezone'] as String? ?? 'system';
      final seed = Color(p['brandColor'] as int? ?? blue.toARGB32());
      final density = p['density'] as String? ?? 'comfortable';
      DisplayPreferences.dateFormat = p['dateFormat'] as String? ?? 'chinese';
      DisplayPreferences.timeFormat = p['timeFormat'] as String? ?? '24';
      return MaterialApp(
        title: 'FlowDay',
        debugShowCheckedModeBanner: false,
        theme: flowTheme(seed: seed, density: density),
        darkTheme: flowTheme(
          brightness: Brightness.dark,
          seed: seed,
          density: density,
        ),
        themeMode: switch (p['themeMode']) {
          'dark' => ThemeMode.dark,
          'system' => ThemeMode.system,
          _ => ThemeMode.light,
        },
        themeAnimationDuration: p['reduceMotion'] == true
            ? Duration.zero
            : const Duration(milliseconds: 200),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              (p['fontScale'] as num? ?? 1).toDouble(),
            ),
            disableAnimations: p['reduceMotion'] == true,
          ),
          child: SyncScope(sync: sync, child: child!),
        ),
        home: FlowShell(
          store: store,
          sync: sync,
          onLogin: onLogin,
          onLogout: onLogout,
          directory: directory,
        ),
      );
    },
  );
}

const destinations = [
  ('today', '今天', Icons.home_outlined),
  ('calendar', '日历', Icons.calendar_month_outlined),
  ('projects', '项目', Icons.folder_outlined),
  ('todo', '任务', Icons.check_box_outlined),
  ('workflow', '工作流', Icons.account_tree_outlined),
  ('reports', '统计分析', Icons.bar_chart_outlined),
  ('notices', '通知', Icons.notifications_none),
  ('trash', '回收站', Icons.delete_outline),
];

class FlowShell extends StatefulWidget {
  const FlowShell({
    super.key,
    required this.store,
    this.sync,
    this.onLogin,
    this.onLogout,
    this.directory,
  });
  final FlowStore store;
  final SyncController? sync;
  final VoidCallback? onLogin;
  final Future<void> Function()? onLogout;
  final Directory? directory;
  @override
  State<FlowShell> createState() => _FlowShellState();
}

class _FlowShellState extends State<FlowShell> {
  final scaffold = GlobalKey<ScaffoldState>();
  String page = 'today';
  String settingsSection = 'general';
  String? workflowProject;
  String? shownError;
  late final AppLifecycleListener lifecycle;
  @override
  void initState() {
    super.initState();
    widget.store.addListener(onStoreChange);
    lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.store.persist();
        return widget.store.error == null
            ? AppExitResponse.exit
            : AppExitResponse.cancel;
      },
    );
  }

  @override
  void dispose() {
    widget.store.removeListener(onStoreChange);
    lifecycle.dispose();
    super.dispose();
  }

  void onStoreChange() {
    if (!mounted) return;
    if (widget.store.error != null && shownError != widget.store.error) {
      final message = widget.store.error!;
      shownError = message;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.store.error == message && shownError == message) {
          showFailure(context, message);
        }
      });
    }
    if (widget.store.error == null) shownError = null;
    setState(() {});
  }

  void navigate(String value) {
    setState(() => page = value);
    scaffold.currentState?.closeDrawer();
  }

  String get heading => switch (page) {
    'today' => '今天',
    'calendar' => '日历',
    'reports' => '统计分析',
    'notices' => '通知中心',
    'trash' => '回收站',
    'settings' => '设置',
    _ => destinations.firstWhere((d) => d.$1 == page).$2,
  };
  Future<void> search() async {
    if (page == 'settings') {
      String query = '';
      final chosen = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, change) => Dialog(
            child: SizedBox(
              width: 520,
              height: 470,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '搜索设置项…',
                      ),
                      onChanged: (v) => change(() => query = v.trim()),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        children: settingsSections
                            .where(
                              (s) =>
                                  '${s.$2} ${switch (s.$1) {
                                        'appearance' => '主题 深色 浅色 字体 字号 品牌色 侧栏 动画',
                                        'schedule' => '默认视图 周起始日 时长 重叠 提醒',
                                        'data' => '导出 导入 备份 恢复 清除',
                                        'account' => '登录 资料 密码 设备 同步',
                                        'workflow' => '节点 依赖 自动布局 连线',
                                        'general' => '语言 时间 日期 时区',
                                        _ => '',
                                      }}'
                                      .contains(query),
                            )
                            .map(
                              (s) => ListTile(
                                leading: Icon(s.$3),
                                title: Text(s.$2),
                                onTap: () => Navigator.pop(context, s.$1),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      if (chosen != null && mounted) setState(() => settingsSection = chosen);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => GlobalSearchPanel(
        store: widget.store,
        sync: widget.sync,
        onTask: (task) =>
            openEditor(context, TaskEditor(store: widget.store, task: task)),
        onEvent: (event) =>
            openEditor(context, EventEditor(store: widget.store, event: event)),
        onProject: (project) =>
            editProject(context, widget.store, project: project),
        onNode: (node) {
          workflowProject = node.projectId;
          navigate('workflow');
        },
        onAttachment: (attachment) {
          final sync = widget.sync;
          if (sync != null) {
            openEditor(
              context,
              Scaffold(
                appBar: AppBar(title: Text('${attachment['name']}')),
                body: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    AttachmentsPanel(
                      sync: sync,
                      ownerType: '${attachment['ownerType']}',
                      ownerId: '${attachment['ownerId']}',
                    ),
                  ],
                ),
              ),
            );
          }
        },
        onCreateTask: (text) => openEditor(
          context,
          TaskEditor(store: widget.store, initialTitle: text),
        ),
        onNaturalLanguage: widget.sync == null
            ? null
            : (text) => showAiPanel(context, widget.sync!, text: text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 850;
    final prefs = widget.store.data.preferences;
    final collapsed =
        prefs['sidebarCollapsed'] == true ||
        prefs['showNavigationLabels'] == false;
    final rightSidebar = prefs['sidebarPosition'] == 'right';
    final name =
        widget.store.data.preferences['displayName'] as String? ??
        widget.sync?.session.user.displayName ??
        '';
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? '早上好'
        : hour < 18
        ? '下午好'
        : '晚上好';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): search,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): search,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: scaffold,
          drawer: desktop
              ? null
              : Drawer(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  child: sidebar(),
                ),
          body: SafeArea(
            child: Row(
              textDirection: rightSidebar
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              children: [
                if (desktop)
                  Container(
                    width: collapsed ? 76 : 208,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: sidebar(),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      desktop ? 26 : 16,
                      desktop ? 24 : 12,
                      desktop ? 26 : 16,
                      20,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            if (!desktop)
                              IconButton(
                                key: const Key('open-navigation'),
                                onPressed: () =>
                                    scaffold.currentState!.openDrawer(),
                                icon: Icon(Icons.menu),
                              ),
                            if (desktop && page == 'today') ...[
                              Icon(
                                Icons.wb_sunny_rounded,
                                color: Color(0xffffbc60),
                                size: 42,
                              ),
                              const SizedBox(width: 14),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    page == 'today'
                                        ? (name.isEmpty
                                              ? greeting
                                              : '$greeting，$name！')
                                        : heading,
                                    style: TextStyle(
                                      fontSize: desktop ? 27 : 23,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -.4,
                                    ),
                                  ),
                                  if (page == 'today')
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        '${dateText(DateTime.now())}  星期${['一', '二', '三', '四', '五', '六', '日'][DateTime.now().weekday - 1]}',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  if (page == 'settings' && desktop)
                                    Padding(
                                      padding: EdgeInsets.only(top: 6),
                                      child: Text(
                                        '个性化你的 FlowDay，让它更符合你的使用习惯。',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (desktop && prefs['showSearch'] != false)
                              SizedBox(
                                width: 280,
                                child: OutlinedButton.icon(
                                  onPressed: search,
                                  icon: Icon(
                                    Icons.search,
                                    size: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  label: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          page == 'settings'
                                              ? '搜索设置项…'
                                              : '搜索日程、任务、项目…',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      if (prefs['showShortcutHints'] != false)
                                        Text(
                                          '⌘ K',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            if (!desktop && prefs['showSearch'] != false)
                              IconButton(
                                onPressed: search,
                                icon: Icon(Icons.search),
                              ),
                            const SizedBox(width: 8),
                            if (widget.sync != null)
                              IconButton(
                                onPressed: () =>
                                    showAiPanel(context, widget.sync!),
                                icon: const Icon(Icons.auto_awesome_outlined),
                              ),
                            IconButton(
                              onPressed: () => navigate('notices'),
                              icon: Icon(Icons.notifications_none),
                            ),
                            if (desktop) ...[
                              const SizedBox(width: 12),
                              ProfileMenu(
                                name: name,
                                email: widget.sync?.session.user.email ?? '',
                                onProfile: () {
                                  settingsSection = 'account';
                                  navigate('settings');
                                },
                                onSettings: () {
                                  settingsSection = 'general';
                                  navigate('settings');
                                },
                                onSwitch: () async {
                                  try {
                                    if (widget.sync != null) {
                                      await widget.onLogout?.call();
                                    } else {
                                      widget.onLogin?.call();
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      showFailure(context, e);
                                    }
                                  }
                                },
                                onLogout: widget.sync == null
                                    ? null
                                    : widget.onLogout,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 24),
                        Expanded(
                          child: KeyedSubtree(
                            key: ValueKey(
                              '$page-${page == 'workflow' ? workflowProject : ''}',
                            ),
                            child: body(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget sidebar() =>
      (MediaQuery.sizeOf(context).width >= 850 &&
          (widget.store.data.preferences['sidebarCollapsed'] == true ||
              widget.store.data.preferences['showNavigationLabels'] == false))
      ? Column(
          children: [
            const SizedBox(height: 24),
            Icon(Icons.spa_rounded, color: palette[2], size: 32),
            const SizedBox(height: 24),
            Expanded(
              child: ListView(
                children: destinations
                    .map(
                      (d) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: IconButton(
                          key: Key('nav-${d.$1}'),
                          onPressed: () => navigate(d.$1),
                          icon: Icon(
                            d.$3,
                            color: page == d.$1
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            IconButton(
              key: const Key('nav-settings'),
              onPressed: () => navigate('settings'),
              icon: Icon(Icons.settings_outlined),
            ),
            const SizedBox(height: 20),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 18, 32),
              child: Row(
                children: [
                  Icon(Icons.spa_rounded, color: palette[2], size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'FlowDay',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  ...destinations.map((d) => navItem(d.$1, d.$2, d.$3)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                    child: Divider(),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '项目',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => editProject(context, widget.store),
                          icon: Icon(
                            Icons.add,
                            size: 17,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...widget.store.projects
                      .where((p) => p.parentId == null && !p.archived)
                      .take(8)
                      .map(
                        (p) => ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          leading: Icon(
                            Icons.circle,
                            size: 10,
                            color: Color(p.color),
                          ),
                          title: Text(
                            p.title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12),
                          ),
                          onTap: () => navigate('projects'),
                        ),
                      ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              child: navItem('settings', '设置', Icons.settings_outlined),
            ),
          ],
        );
  Widget navItem(String id, String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: DragTarget<Task>(
      onWillAcceptWithDetails: (details) => id == 'calendar',
      onAcceptWithDetails: (details) {
        navigate('calendar');
        openEditor(
          context,
          EventEditor(store: widget.store, task: details.data),
        );
      },
      builder: (context, candidates, rejected) => Material(
        color: page == id
            ? Theme.of(context).colorScheme.primary.withValues(alpha: .06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: ListTile(
          key: Key('nav-$id'),
          dense: true,
          minTileHeight: 44,
          horizontalTitleGap: 14,
          minLeadingWidth: 20,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Icon(
            icon,
            size: 20,
            color: page == id
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
          ),
          title: Text(
            title,
            style: TextStyle(
              color: page == id
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              fontWeight: page == id ? FontWeight.w500 : FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
          onTap: () => navigate(id),
        ),
      ),
    ),
  );
  Widget body() => switch (page) {
    'today' => TodayPage(
      store: widget.store,
      navigate: navigate,
      onOpenWorkflow: (id) {
        workflowProject = id;
        navigate('workflow');
      },
      onParse: widget.sync == null
          ? null
          : (text) => showAiPanel(context, widget.sync!, text: text),
    ),
    'todo' => TodoPage(
      store: widget.store,
      onSchedule: widget.sync == null
          ? null
          : (ids) => showAiPanel(context, widget.sync!, taskIds: ids),
      attachmentBuilder: widget.sync == null
          ? null
          : (task) => AttachmentsPanel(
              sync: widget.sync!,
              ownerType: 'task',
              ownerId: task.id,
            ),
    ),
    'calendar' => CalendarPage(store: widget.store),
    'projects' => ProjectsPage(
      store: widget.store,
      attachmentBuilder: widget.sync == null
          ? null
          : (project) => AttachmentsPanel(
              sync: widget.sync!,
              ownerType: 'project',
              ownerId: project.id,
            ),
      openWorkflow: (id) {
        workflowProject = id;
        navigate('workflow');
      },
    ),
    'workflow' => WorkflowPage(store: widget.store, projectId: workflowProject),
    'reports' => ReportsPage(store: widget.store),
    'notices' => NoticesPage(
      store: widget.store,
      onOpenProject: (id) {
        final project = widget.store.project(id);
        if (project != null) {
          editProject(context, widget.store, project: project);
        }
      },
      onOpenNode: (node) {
        workflowProject = node.projectId;
        navigate('workflow');
      },
    ),
    'trash' => TrashPage(store: widget.store),
    'settings' => SettingsPage(
      store: widget.store,
      sync: widget.sync,
      onLogin: widget.onLogin,
      onLogout: widget.onLogout,
      directory: widget.directory,
      initialSection: settingsSection,
    ),
    _ => const SizedBox.shrink(),
  };
}
