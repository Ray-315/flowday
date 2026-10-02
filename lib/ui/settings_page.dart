import 'dart:io';
import 'package:flutter/material.dart';
import 'licenses_panel.dart';
import '../domain/store.dart';
import '../data/sync_controller.dart';
import 'account_panel.dart';
import 'security_panel.dart';
import 'data_settings_panel.dart';
import 'theme.dart';
import 'reminder_queue.dart';
import 'integrations_panel.dart';
import 'course_import_panel.dart';
import '../data/native_notifications.dart';
import 'today_customization.dart';

const settingsSections = <(String, String, IconData)>[
  ('general', '基础设置', Icons.settings_outlined),
  ('account', '账号与同步', Icons.person_outline),
  ('schedule', '日程与提醒', Icons.calendar_month_outlined),
  ('tasks', '任务与项目', Icons.check_box_outlined),
  ('workflow', '工作流', Icons.account_tree_outlined),
  ('appearance', '界面与外观', Icons.palette_outlined),
  ('notifications', '通知', Icons.notifications_none),
  ('data', '数据与隐私', Icons.verified_user_outlined),
  ('shortcuts', '快捷操作', Icons.keyboard_outlined),
  ('about', '关于', Icons.info_outline),
];

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.store,
    this.sync,
    this.onLogin,
    this.onLogout,
    this.directory,
    this.initialSection = 'general',
  });
  final FlowStore store;
  final SyncController? sync;
  final VoidCallback? onLogin;
  final Future<void> Function()? onLogout;
  final Directory? directory;
  final String initialSection;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String section = widget.initialSection;
  final scroll = ScrollController();
  Map<String, dynamic> get prefs => widget.store.data.preferences;
  T value<T>(String key, T fallback) =>
      prefs[key] is T ? prefs[key] as T : fallback;
  void update(String key, Object next) {
    setState(() => prefs[key] = next);
    widget.store.changed();
  }

  void select(String next) {
    setState(() => section = next);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      select(widget.initialSection);
    }
  }

  Color get accent => Theme.of(context).colorScheme.primary;
  Color get border => Theme.of(context).dividerColor;
  Widget note(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 850;
        final contents = ListView(
          controller: scroll,
          padding: const EdgeInsets.only(bottom: 18),
          children: [
            if (section != 'general' && section != 'account')
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 0, 16),
                child: Text(
                  settingsSections.firstWhere((s) => s.$1 == section).$2,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ...content(),
          ],
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (desktop) ...[
              SizedBox(
                width: 236,
                child: Panel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 18,
                  ),
                  child: ListView(
                    key: const Key('settings-navigation'),
                    children: settingsSections
                        .map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              key: Key('settings-${s.$1}'),
                              selected: section == s.$1,
                              selectedColor: accent,
                              selectedTileColor: accent.withValues(alpha: .08),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                              leading: Icon(s.$3, size: 23),
                              title: Text(
                                s.$2,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              onTap: () => select(s.$1),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                children: [
                  if (!desktop) ...[
                    FlowSelect<String>(
                      key: const Key('settings-navigation'),
                      initialValue: section,
                      items: settingsSections
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.$1,
                              child: Text(s.$2),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => select(v!),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Expanded(
                    child:
                        section == 'about' &&
                            constraints.maxWidth >= 1150 &&
                            widget.directory != null
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ListView(
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 16),
                                      child: Text(
                                        '数据与隐私',
                                        style: TextStyle(
                                          fontSize: 25,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    DataSettingsPanel(
                                      store: widget.store,
                                      directory: widget.directory!,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),
                              SizedBox(width: 340, child: contents),
                            ],
                          )
                        : contents,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget card(
    String title,
    IconData icon,
    List<Widget> children, {
    String? subtitle,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Panel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      note(subtitle),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );
  Widget pair(Widget left, Widget right) => LayoutBuilder(
    builder: (context, c) => c.maxWidth >= 730
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 14),
              Expanded(child: right),
            ],
          )
        : Column(children: [left, right]),
  );
  Widget row(
    String label,
    Widget control, {
    IconData? icon,
    String? subtitle,
  }) => Container(
    padding: EdgeInsets.symmetric(
      vertical: value('density', 'comfortable') == 'compact'
          ? 5
          : value('density', 'comfortable') == 'spacious'
          ? 12
          : 8,
    ),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: border.withValues(alpha: .7))),
    ),
    child: LayoutBuilder(
      builder: (context, c) {
        final text = Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 21),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    note(subtitle),
                  ],
                ],
              ),
            ),
          ],
        );
        if (c.maxWidth < 340) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text,
              const SizedBox(height: 9),
              Align(alignment: Alignment.centerRight, child: control),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: text),
            const SizedBox(width: 16),
            control,
          ],
        );
      },
    ),
  );
  Widget choice<T>(
    String label,
    String key,
    T fallback,
    Map<T, String> options, {
    IconData? icon,
    String? subtitle,
  }) => row(
    label,
    SizedBox(
      width: 180,

      child: FlowSelect<T>(
        key: ValueKey('$key-${value(key, fallback)}'),
        initialValue: options.containsKey(value(key, fallback))
            ? value(key, fallback)
            : fallback,
        isExpanded: true,
        isDense: true,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        items: options.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, style: const TextStyle(fontSize: 13)),
              ),
            )
            .toList(),
        onChanged: (v) => update(key, v as Object),
      ),
    ),
    icon: icon,
    subtitle: subtitle,
  );
  Widget toggle(
    String label,
    String key,
    bool fallback, {
    IconData? icon,
    String? subtitle,
  }) => row(
    label,
    SizedBox(
      width: 46,
      height: 34,
      child: FittedBox(
        child: Switch(
          key: Key('setting-$key'),
          value: value(key, fallback),
          onChanged: (v) => update(key, v),
        ),
      ),
    ),
    icon: icon,
    subtitle: subtitle,
  );
  Widget unavailable(String label, String status, {IconData? icon}) =>
      row(label, note(status), icon: icon);
  Widget action(
    String label,
    IconData icon,
    VoidCallback? onTap, {
    String? trailing,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: accent),
    title: Text(label),
    trailing: trailing == null
        ? const Icon(Icons.chevron_right, size: 20)
        : note(trailing),
    onTap: onTap,
  );
  Widget weekStart() => choice('一周起始日', 'weekStartsMonday', true, const {
    true: '周一',
    false: '周日',
  }, icon: Icons.calendar_view_week_outlined);
  Widget fontSize() => choice('字体大小', 'fontScale', 1.0, {
    0.9: '小',
    1.0: '标准',
    1.15: '大',
  }, icon: Icons.text_fields);
  Widget density() => choice('显示密度', 'density', 'comfortable', const {
    'comfortable': '舒适',
    'compact': '紧凑',
    'spacious': '宽松',
  }, icon: Icons.view_agenda_outlined);
  Widget duration(String label, String key) => choice(label, key, 60, const {
    15: '15 分钟',
    30: '30 分钟',
    60: '1 小时',
    90: '1.5 小时',
    120: '2 小时',
  }, icon: Icons.schedule);
  Widget priority(String key) => choice('默认任务优先级', key, 'normal', const {
    'low': '低',
    'normal': '普通',
    'high': '高',
    'urgent': '紧急',
  }, icon: Icons.flag_outlined);
  Widget themeSelector() => Row(
    children: [('light', '浅色'), ('dark', '深色'), ('system', '跟随系统')]
        .map(
          (e) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                key: Key('theme-${e.$1}'),
                onTap: () => update('themeMode', e.$1),
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  children: [
                    Container(
                      height: 80,
                      decoration: BoxDecoration(
                        color: e.$1 == 'dark'
                            ? const Color(0xff202734)
                            : const Color(0xfff3f7fd),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: value('themeMode', 'light') == e.$1
                              ? accent
                              : border,
                          width: 2,
                        ),
                      ),
                      padding: const EdgeInsets.all(9),
                      child: Row(
                        children: [
                          Container(
                            width: 18,
                            decoration: BoxDecoration(
                              color: e.$1 == 'dark'
                                  ? Colors.white12
                                  : accent.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              children: List.generate(
                                3,
                                (i) => Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 5),
                                    color: e.$1 == 'dark'
                                        ? Colors.white10
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          value('themeMode', 'light') == e.$1
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 17,
                          color: accent,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            e.$2,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
        .toList(),
  );

  List<Widget> content() => switch (section) {
    'general' => [
      card('基础设置', Icons.settings_outlined, [
        unavailable('语言', '简体中文', icon: Icons.language),
        choice('时区', 'timezone', 'system', const {
          'system': '跟随设备',
          'Asia/Shanghai': '北京 / 上海',
          'Asia/Tokyo': '东京',
          'Europe/London': '伦敦',
          'America/New_York': '纽约',
          'America/Los_Angeles': '洛杉矶',
          'UTC': 'UTC',
        }, icon: Icons.public),
        choice('日期格式', 'dateFormat', 'chinese', const {
          'chinese': '2026年9月30日',
          'YYYY-MM-DD': '2026-09-30',
          'YYYY/MM/DD': '2026/09/30',
        }, icon: Icons.calendar_today),
        choice('时间格式', 'timeFormat', '24', const {
          '24': '24 小时制',
          '12': '12 小时制',
        }, icon: Icons.schedule),
        weekStart(),
      ], subtitle: '设置语言、时区、时间格式等基础选项。'),
      card('外观设置', Icons.wb_sunny_outlined, [
        choice('主题模式', 'themeMode', 'light', const {
          'light': '浅色',
          'dark': '深色',
          'system': '跟随系统',
        }, icon: Icons.wb_sunny_outlined),
        fontSize(),
        density(),
        action(
          '首页模块',
          Icons.dashboard_outlined,
          () => showTodayCustomization(context, widget.store),
        ),
      ], subtitle: '自定义界面主题、字体大小和显示密度。'),
      card('数据管理', Icons.storage_outlined, [
        action('导出数据、备份与恢复', Icons.backup_outlined, () => select('data')),
      ]),
    ],
    'account' => [
      if (widget.sync != null && widget.onLogout != null)
        AccountPanel(controller: widget.sync!, onLogout: widget.onLogout!)
      else
        card('账号信息', Icons.person_outline, [
          action('登录账号', Icons.login, widget.onLogin),
        ]),
      const SizedBox(height: 14),
      card('第三方日历同步', Icons.sync, [
        action(
          'Apple Calendar',
          Icons.calendar_month,
          widget.sync == null
              ? null
              : () => openEditor(
                  context,
                  Scaffold(
                    body: SafeArea(
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.all(20),
                              children: [IntegrationsPanel(sync: widget.sync!)],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        unavailable('Google Calendar', '未接入'),
        unavailable('Outlook Calendar', '未接入'),
      ]),
    ],
    'schedule' => [
      pair(
        card('日程设置', Icons.calendar_month_outlined, [
          choice('默认视图', 'calendarView', '月', const {
            '月': '月视图',
            '周': '周视图',
            '日': '日视图',
            '时间轴': '时间轴',
            '列表': '列表',
          }, icon: Icons.grid_view),
          weekStart(),
          duration('默认日程时长', 'defaultEventMinutes'),
          choice('时间粒度', 'timeStepMinutes', 15, const {
            5: '5 分钟',
            15: '15 分钟',
            30: '30 分钟',
            60: '1 小时',
          }, icon: Icons.tune),
          choice('重叠日程显示', 'overlapStyle', '并排', const {
            '并排': '并排显示',
            '层叠': '层叠显示',
            '聚合': '聚合显示',
          }, icon: Icons.layers_outlined),
        ]),
        card('提醒设置', Icons.notifications_none, [
          choice('默认提前提醒', 'reminderMinutes', 15, const {
            0: '准时',
            5: '5 分钟',
            15: '15 分钟',
            30: '30 分钟',
            60: '1 小时',
          }, icon: Icons.schedule),
          toggle('强提醒（默认）', 'strongReminder', false, icon: Icons.bolt),
          choice('强提醒间隔', 'reminderInterval', 5, const {
            5: '5 分钟',
            10: '10 分钟',
            15: '15 分钟',
            30: '30 分钟',
          }, icon: Icons.sync),
          choice('最大提醒次数', 'maxReminders', 3, const {
            1: '1 次',
            3: '3 次',
            5: '5 次',
            10: '10 次',
          }, icon: Icons.tag),
        ]),
      ),
      card('重复与行为', Icons.repeat, [
        choice('重复日程默认规则', 'defaultRepeat', 'none', const {
          'none': '不重复',
          'daily': '每天',
          'weekly': '每周',
          'monthly': '每月',
          'yearly': '每年',
        }),
        action(
          '导入课程文件',
          Icons.upload_file,
          () => showCourseImport(context, widget.store),
        ),
      ]),
      if (widget.sync != null)
        card('日程提醒', Icons.notifications_active_outlined, [
          action(
            '管理与确认提醒',
            Icons.notifications_none,
            () => showDialog<void>(
              context: context,
              builder: (_) => ReminderQueue(controller: widget.sync!),
            ),
          ),
        ]),
    ],
    'tasks' => [
      pair(
        card('任务默认设置', Icons.check_box_outlined, [
          priority('defaultTaskPriority'),
          choice('默认任务难度', 'defaultDifficulty', 'normal', const {
            'low': '简单',
            'normal': '中等',
            'high': '困难',
          }),
          duration('默认预计时长', 'defaultEstimateMinutes'),
          choice('课程提前提醒', 'courseReminderLeadMinutes', 15, const {
            0: '开始时',
            5: '5 分钟',
            10: '10 分钟',
            15: '15 分钟',
            30: '30 分钟',
            60: '1 小时',
          }),
        ]),
        card('项目管理', Icons.folder_outlined, [
          action(
            '项目数量',
            Icons.folder_open,
            null,
            trailing: '${widget.store.projects.length}',
          ),
          action(
            '任务数量',
            Icons.checklist,
            null,
            trailing: '${widget.store.tasks.length}',
          ),
        ]),
      ),
    ],
    'workflow' => [
      card('节点默认设置', Icons.settings_outlined, [
        pair(
          Column(
            children: [
              choice('默认节点类型', 'workflowDefaultKind', 'task', const {
                'task': '任务节点',
                'milestone': '里程碑',
                'note': '说明节点',
              }, icon: Icons.account_tree_outlined),
              priority('workflowDefaultPriority'),
            ],
          ),
          Column(
            children: [
              duration('默认预计时长', 'workflowEstimateMinutes'),
              toggle(
                '自动创建关联任务',
                'workflowAutoTodo',
                true,
                icon: Icons.check_box_outlined,
              ),
            ],
          ),
        ),
      ], subtitle: '设置新建节点时的默认属性。'),
      card('节点行为设置', Icons.account_tree_outlined, [
        pair(
          Column(
            children: [
              toggle(
                '跳过节点视为完成',
                'workflowSkipCompletes',
                true,
                icon: Icons.skip_next_outlined,
              ),
              toggle(
                '完成节点自动解锁后续',
                'workflowAutoUnlock',
                true,
                icon: Icons.lock_open,
              ),
              toggle(
                '允许手动解锁',
                'workflowAllowManualUnlock',
                true,
                icon: Icons.lock_open_outlined,
              ),
            ],
          ),
          Column(
            children: [
              toggle(
                '节点依赖检查',
                'workflowCheckDependencies',
                true,
                icon: Icons.layers_outlined,
              ),
              toggle(
                '显示连线名称',
                'workflowShowEdgeLabels',
                true,
                icon: Icons.timeline,
              ),
              toggle(
                '显示里程碑节点',
                'workflowShowMilestones',
                true,
                icon: Icons.flag_outlined,
              ),
            ],
          ),
        ),
      ]),
      card('显示设置', Icons.grid_view, [
        pair(
          Column(
            children: [
              choice('视图缩放级别', 'workflowZoom', 100, const {
                50: '50%',
                75: '75%',
                100: '100%',
                125: '125%',
                150: '150%',
              }, icon: Icons.zoom_in),
              toggle(
                '自动布局',
                'workflowAutoLayout',
                false,
                icon: Icons.auto_fix_high,
              ),
            ],
          ),
          Column(
            children: [
              toggle(
                '显示节点说明',
                'workflowShowDescription',
                true,
                icon: Icons.subject,
              ),
              toggle(
                '显示节点预计时间',
                'workflowShowEstimate',
                true,
                icon: Icons.timer_outlined,
              ),
            ],
          ),
        ),
      ]),
      Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            prefs.removeWhere((k, v) => k.startsWith('workflow'));
            widget.store.changed();
            setState(() {});
          },
          child: const Text('恢复默认设置'),
        ),
      ),
    ],
    'appearance' => [
      pair(
        card('主题模式', Icons.wb_sunny_outlined, [
          themeSelector(),
        ], subtitle: '选择你喜欢的主题风格。'),
        card('品牌色', Icons.palette_outlined, [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children:
                [
                      0xff237bff,
                      0xffa469ee,
                      0xffff70a2,
                      0xffff7373,
                      0xffffae4d,
                      0xff28bca3,
                      0xff32bdcf,
                      0xff7761e8,
                    ]
                    .map(
                      (c) => InkWell(
                        onTap: () => update('brandColor', c),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: value('brandColor', 0xff237bff) == c
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: value('brandColor', 0xff237bff) == c
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey(value('brandColor', 0xff237bff)),
            initialValue:
                '#${value('brandColor', 0xff237bff).toRadixString(16).substring(2).toUpperCase()}',
            decoration: const InputDecoration(labelText: '自定义颜色'),
            onFieldSubmitted: (v) {
              if (RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(v)) {
                update(
                  'brandColor',
                  int.parse('ff${v.replaceAll('#', '')}', radix: 16),
                );
              }
            },
          ),
        ], subtitle: '选择界面的主色调。'),
      ),
      pair(
        card('字体与显示', Icons.text_fields, [
          fontSize(),
          density(),
          choice('字体', 'fontFamily', appFontFamily, const {
            appFontFamily: 'HarmonyOS Sans',
          }, icon: Icons.text_format),
        ]),
        card('布局与导航', Icons.grid_view, [
          choice('侧边栏位置', 'sidebarPosition', 'left', const {
            'left': '左侧',
            'right': '右侧',
          }, icon: Icons.view_sidebar_outlined),
          toggle('侧边栏收起', 'sidebarCollapsed', false, icon: Icons.first_page),
          toggle('顶部搜索栏', 'showSearch', true, icon: Icons.search),
          toggle(
            '显示文字标签',
            'showNavigationLabels',
            true,
            icon: Icons.text_fields,
          ),
        ]),
      ),
      pair(
        card('日历与时间显示', Icons.calendar_today, [
          weekStart(),
          choice('时间格式', 'timeFormat', '24', const {
            '24': '24 小时制',
            '12': '12 小时制',
          }, icon: Icons.schedule),
          choice('日期格式', 'dateFormat', 'chinese', const {
            'chinese': '年/月/日',
            'YYYY-MM-DD': 'YYYY-MM-DD',
            'YYYY/MM/DD': 'YYYY/MM/DD',
          }, icon: Icons.calendar_month),
        ]),
        card('动画与动效', Icons.auto_awesome_outlined, [
          toggle(
            '减少动态效果',
            'reduceMotion',
            false,
            icon: Icons.motion_photos_off_outlined,
          ),
          toggle(
            '显示快捷键提示',
            'showShortcutHints',
            true,
            icon: Icons.keyboard_outlined,
          ),
        ]),
      ),
    ],
    'notifications' => [
      card('通知中心', Icons.notifications_none, [
        action(
          '未读通知',
          Icons.mark_email_unread_outlined,
          null,
          trailing: '${widget.store.data.notices.where((n) => !n.read).length}',
        ),
        action('全部标为已读', Icons.done_all, widget.store.markAllRead),
        action('系统通知', Icons.notifications_active_outlined, () async {
          await NativeNotifications.instance.requestPermission();
          if (mounted && NativeNotifications.instance.error != null) {
            await showFailure(context, NativeNotifications.instance.error!);
          }
        }),
        if (widget.sync != null) IntegrationsPanel(sync: widget.sync!),
      ]),
    ],
    'data' => [
      if (widget.directory != null)
        DataSettingsPanel(
          store: widget.store,
          directory: widget.directory!,
          sync: widget.sync,
        )
      else
        card('数据概览', Icons.storage, [
          unavailable('日程', '${widget.store.events.length} 条'),
          unavailable('任务', '${widget.store.tasks.length} 条'),
          unavailable('项目', '${widget.store.projects.length} 个'),
        ]),
      if (widget.sync != null && widget.onLogout != null)
        SecurityPanel(controller: widget.sync!, onLogout: widget.onLogout!),
    ],
    'shortcuts' => [
      card('快捷操作', Icons.keyboard_outlined, [
        unavailable('全局搜索', 'Ctrl / ⌘ + K', icon: Icons.search),
        unavailable('关闭对话框', 'Esc', icon: Icons.close),
        unavailable('切换焦点', 'Tab / Shift + Tab', icon: Icons.keyboard_tab),
        toggle(
          '显示快捷键提示',
          'showShortcutHints',
          true,
          icon: Icons.keyboard_alt_outlined,
        ),
      ]),
    ],
    'about' => [
      card('FlowDay', Icons.spa_outlined, [
        const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.spa_rounded, size: 64, color: Color(0xff20b69c)),
                SizedBox(height: 16),
                Text(
                  'FlowDay',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8),
                Text('专注今日，成就更好的你'),
                SizedBox(height: 16),
                Text('版本 0.1.0'),
              ],
            ),
          ),
        ),
        action(
          '使用帮助',
          Icons.help_outline,
          () => showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('使用帮助'),
              content: const Text(
                '在项目中创建任务，在日历中安排时间块。工作流节点可关联任务。设置中的账号与同步可连接你的 FlowDay 服务器，数据与隐私可备份或恢复当前账号数据。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        ),
        action('开源声明', Icons.code, () => showFlowLicenses(context)),
      ]),
    ],
    _ => [],
  };
}
