# UI 统一检查（2026-09-30）

## 修复内容

- 深色主题独立定义炭灰背景、卡片、菜单、边框和文字颜色，不再继承浅色背景。
- 设置、编辑器和工作流统一使用 FlowSelect；菜单与字段等宽，统一选中标记、圆角、间距、键盘操作和关闭行为。
- 移除设置下拉框固定高度，允许字体放大；修复外部值更新时在构建阶段触发表单通知的异常。
- Today、Todo、日历、项目、统计、工作流、账户、登录表单、数据管理和头像菜单使用主题颜色。
- 修复深色 Todo 表头和深色自定义日程文字对比不足；保留项目和日程的语义颜色。
- 统一按钮、输入框、弹窗、菜单、分割线、开关和滚动条主题，并保留字体设置。

## 修改文件

- 共享组件：`lib/ui/theme.dart`、`lib/ui/select_field.dart`
- 导航与设置：`lib/ui/app.dart`、`lib/ui/settings_page.dart`、`lib/ui/profile_menu.dart`
- 页面：`lib/ui/today_page.dart`、`lib/ui/task_pages.dart`、`lib/ui/overview_pages.dart`、`lib/ui/calendar_page.dart`、`lib/ui/mini_calendar.dart`、`lib/ui/workflow_page.dart`
- 表单与账户：`lib/ui/editors.dart`、`lib/ui/auth_page.dart`、`lib/ui/account_panel.dart`、`lib/ui/security_panel.dart`、`lib/ui/data_settings_panel.dart`
- 测试：`test/select_field_test.dart`、`test/ui_forms_test.dart`、`test/ui_surfaces_test.dart`、`test/editor_regression_test.dart`、`test/settings_behavior_test.dart`
- 截图脚本：`tool/settings_preview_test.dart`、`tool/preview_test.dart`

## 验证

- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub`：96 项通过。
- 两个截图测试通过，生成浅色/深色设置菜单、桌面页面和 390 像素移动端预览。
- 下拉框覆盖键盘打开、Escape 关闭、外部点击关闭、空项目、长文本、外部值更新、表单校验、1.5 倍字体和屏幕边缘场景。
- 检查深色正文、次要文字和强调色对比度，以及日程标题和 Todo 表头对比度。

截图是 Flutter Widget 渲染结果；原生窗口的实际交互仍需在 Windows 客户端中体验。此次未改变后端或接入新的第三方服务。

## 全局字体修正

统一使用内嵌 HarmonyOS Sans SC，包含 400、500、700 三种真实字重。旧设置中的微软雅黑和系统字体仍可导入，但不会覆盖全局字体。图标继续使用 MaterialIcons。

修改文件：`pubspec.yaml`、`assets/fonts/HarmonyOS_Sans_SC_{Regular,Medium,Bold}.ttf`、`lib/ui/theme.dart`、`lib/ui/app.dart`、`lib/ui/settings_page.dart`、`lib/domain/models.dart`、`test/font_theme_test.dart`、`tool/preview_test.dart`、`tool/settings_preview_test.dart`。

字体修正后的验证：99 项测试通过、两项截图测试通过、静态检查无问题。新增测试检查发布资源声明与实际字体文件、浅色/深色及菜单弹窗字体、旧字体设置兼容。

## 侧边栏与中文导航

导航改为今天、日历、项目、任务、工作流；移除 Inbox 入口和页面路由，保留已有数据。首页快捷输入直接打开任务编辑器。侧边栏按钮使用 44 像素最小高度、6 像素圆角和更浅的选中底色，缩小图标与文字间距。相关任务、项目和工作流按钮同步改为中文。

修改文件：`lib/ui/app.dart`、`lib/ui/today_page.dart`、`lib/ui/task_pages.dart`、`lib/ui/overview_pages.dart`、`lib/ui/workflow_page.dart`、`lib/ui/editors.dart`、`lib/ui/settings_page.dart`；相关测试为 `test/navigation_test.dart`、`test/today_layout_test.dart`、`test/app_test.dart`、`test/settings_behavior_test.dart`。

验证：100 项测试通过，静态检查通过，桌面和手机截图生成通过。

## 开源许可面板

用应用主题面板替换 Flutter 默认许可页：桌面组件列表与正文分栏，窄屏支持返回列表，正文支持选择复制。字体、浅深色背景、边框、选中状态与应用保持一致。内容仍来自 Flutter LicenseRegistry，保留每个组件的全部许可段落。

修改文件：`lib/ui/licenses_panel.dart`、`lib/ui/settings_page.dart`、`test/licenses_panel_test.dart`、`tool/settings_preview_test.dart`。完整测试 102 项通过、静态检查通过。截图使用 Flutter SDK 自带许可文本作为测试数据，生产环境读取应用依赖的许可注册表。
