# FlowDay 客户端与独立后端实施计划

## 目标

按用户第一张 Today 示意图及各模块对应示意图继续实现应用，将账号与同步服务独立部署在服务器。保留已有本地数据与本地使用入口。

## 文件与接口

- `server/`：Fastify HTTP API、SQLite WAL 数据库、账号/会话、用户工作区、版本并发检查、提醒调度、备份、AI 预览及 Docker 部署。
- `lib/data/api_client.dart`、`sync_controller.dart`：独立接口客户端、会话、版本冲突和同步。
- `lib/ui/auth_page.dart`、`account_panel.dart`：登录注册、服务器连接、账号与同步。
- `lib/ui/today_page.dart`、`mini_calendar.dart`：第一张图的时间轴、Todo、小日历和概览。
- `lib/ui/task_pages.dart`、`calendar_page.dart`：表格/分组/右侧详情，日历侧栏及拖拽。
- `lib/ui/settings_page.dart`、`app.dart`、`theme.dart`：分栏设置、账号接入、导航与视觉统一。
- `test/` 与 `server/test/`：客户端交互、同步错误/冲突、账号隔离、服务端数据校验与持久化测试。

## 执行

- [x] Today 第一张布局、Calendar/Todo/Projects 页面与实际数据交互。
- [ ] 设置、统计和 Workflow 全部示意图细节继续完善。
- [x] 实现后端并运行接口/数据隔离测试。
- [x] 客户端接入服务端，账号缓存分目录，登录不自动上传本地访客数据。
- [x] 验证服务端版本冲突，保留双方数据后明确选择。
- [x] 本机真实 HTTP 联调、静态检查、61 项客户端测试、8 项后端测试、Windows 构建与截图检查。
- [x] 提供服务器部署配置。
- [ ] 远程部署待服务器目标与域名明确后执行。
- [ ] 接通客户端提醒/AI/服务器备份操作入口。

## 约定

主接口 `/api/v1`。工作区 `GET /workspace` 返回 `{version,data}`，`PUT /workspace` 接收 `{baseVersion,data}`；过期版本返回 409。用户 ID 由已认证会话确定。客户端凭据暂仅留在内存中，退出应用需重新登录；业务数据持久化不包含令牌或密码。

示意图作为设计输入；不复制虚构统计、账号数据和不属于 PRD 的协作功能。外部集成必须有真实接入结果，不能显示伪造成功状态。
