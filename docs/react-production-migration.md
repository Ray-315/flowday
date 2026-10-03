# React/Tauri 正式客户端迁移计划

**Goal:** 将现有 React 界面迁移到原 Flutter 已实现的业务能力，保持 schemaVersion 1 和服务端协议兼容。

**Architecture:** 复用现有页面、表单和主题；领域逻辑从 Flutter 模型/状态机移植到可测试 TypeScript 模块。桌面工作区采用原子文件保存，账号与访客隔离；网络变更使用版本比较和保护备份。

**Tech Stack:** React / TypeScript / Motion / Tauri 2 / Rust；现有 Fastify API。

## 执行与验收

- [x] 领域模型：任务/日程联动、重复规则、项目层级、工作流依赖和回收恢复。对照 Dart 单测移植，并运行 Vitest。
- [x] 本地数据：原子持久化、迁移试用缓存、每日备份、错误恢复与账号隔离。验证重启、损坏文件和失败写入。
- [x] 任务与项目：完整属性、子任务、附件、归档/批选、项目编辑与嵌套。用真实浏览器验证保存和恢复。
- [x] 日历：月/周/日/列表、时间块联动、重复范围、锁定和拖动。验证重叠、跨日与日期边界。
- [x] 工作流：七类节点、AND/OR、分支、延迟、分组、跨项目、复制、撤销、布局与日历关联。
- [x] 账号：验证码注册、登录、资料、安全会话、同步和冲突选择；令牌不能进入工作区或日志。
- [x] 服务功能：AI预览/局部确认、提醒动作、飞书/Apple、附件、备份和导入导出。使用本地测试服务验证协议，不擅自修改生产数据。
- [x] 搜索、报告、课程导入和本地通知。
- [x] 回归：领域与界面测试、Windows 构建、原生启动/持久化；更新发行文件与功能清单。

## 验收边界

第三方账号与移动平台的真实设备验证单独记录，不以 Windows 或模拟服务测试代替。未完成项目保持未勾选，不能将迁移中的构建称为已完整验收。

## 2026-10-03 验证记录

- 前端 120 项功能/协议/生命周期测试通过，包含真实本地 Fastify CAS、提醒签名、AI 局部应用与撤销。
- Edge 19 项端到端回归通过，覆盖已有业务、主题层次、常驻导航与 390–1440px 窗口排布，新增独立登录/注册、密码显隐、验证码倒计时、密码二次确认、设置默认属性与服务控件一致性。
- TypeScript / Vite 发布构建通过；功能面板按需加载。
- 服务端 64 项测试通过；兼容补丁未部署，等待生产部署授权。
- Windows 原生 6 项测试通过：原子替换、凭据存取清除和单实例隔离。
- NSIS 安装包构建通过；原生 WebView 启动、请求/下载、同步基线、每日/手动/上一版备份及清除缓存后的文件恢复测试通过。发行文件位于 releases/react-client-0.2.0。未在用户环境执行安装。


## 主要变更文件

本轮导航调整：移除右上角更多菜单，主功能进入常驻导航；账号、通知、项目、偏好及备份使用独立内容页；课程导入和今日定制保留在对应页面。窄窗口保留文字入口及项目管理，未改变业务数据格式。

后续一致性修正：取消独立偏好页面，设置合为一个分类页面，账号和备份快捷入口连接相应分类。对照 lib/ui/auth_page.dart、settings_page.dart、account_panel.dart 和 security_panel.dart，恢复独立认证布局及本地返回，调整资料/密码/注销操作为应用内对话框，补齐密码确认和新建默认属性。通用控件收敛到 ui.css，原 Lucide 图标使用统一 Phosphor 导出。此记录仅证明列出的流程与共享样式，不表示 Flutter 每个设置项均已逐项验收。

一致性修正文件：react-client/src/App.tsx、Account.tsx、SettingsPage.tsx、Management.tsx、Editors.tsx、ui.css、icons.ts、main.tsx、services.css、production.css；Calendar.tsx、Tasks.tsx、TodayExtras.tsx、Tools.tsx、Workflow.tsx 的图标导入；App.test.tsx、workspace.test.ts、e2e/app.spec.ts、production.spec.ts、account-settings.spec.ts；react-client/README.md 和本记录。120 项单元、19 项界面、Windows 原生冒烟及 NSIS 构建通过，发行目录中的安装器、可执行文件与校验文件已更新。

- 界面与交互：react-client/src/App.tsx、Editors.tsx、Tasks.tsx、Calendar.tsx、Workflow.tsx、TodayExtras.tsx、Notices.tsx、Management.tsx、Account.tsx、Services.tsx、CourseImport.tsx、Reports.tsx、GlobalSearch.tsx。
- 业务与数据：react-client/src/workspace.ts、domain.ts、storage.ts、api.ts、courses.ts、timezone.ts、reminders.ts。
- 样式：react-client/src/production.css、workflow.css、today-extras.css、calendar-advanced.css、editor-advanced.css、services.css。
- 原生：react-client/src-tauri/src/lib.rs、native.rs、credentials.rs、instance.rs；Cargo.toml/Cargo.lock、tauri.conf.json、capabilities/default.json。
- 验证：react-client/src/*.test.ts(x)、e2e/app.spec.ts、e2e/production.spec.ts、scripts/native-smoke.mjs。
- 服务兼容：server/src/validation.js、server/test/preferences.test.js；说明与包配置：react-client/README.md、package.json/package-lock.json、src/main.tsx。
