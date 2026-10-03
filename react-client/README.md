# FlowDay React + Tauri 客户端

React、TypeScript、Vite、Motion、Tauri 2 / Rust 实现的 Windows 客户端，与 Flutter schemaVersion 1 和现有 Fastify API 兼容。

## 功能

- 常驻导航：今天、日历、任务、工作流、报告、通知与智能安排；设置按基础、账号、日程、任务、工作流、外观、通知及数据分类。账号与本地备份快捷入口连接同一套设置，登录与注册使用独立页面。课程导入位于日历，今日布局位于今天。
- 共享主题控件与 Phosphor 图标；登录支持密码显隐、验证码倒计时及继续本地使用，修改密码保留二次确认。新建任务和日程读取默认属性。

- 今日模块排序/隐藏、速记、逾期、工作流节点、通知与每周负荷。
- 任务与项目完整编辑、子任务、附件、重复范围、完成联动、批选、归档及回收恢复。
- 日历、拖放排程、时间块缩放、锁定和所选时区。
- 七类工作流节点、AND/OR、分支、等待、分组、跨项目、框选拖动、复制、布局、撤销重做和小地图。
- 验证码注册、登录、资料、安全会话、账号隔离、版本同步及冲突处理。
- AI 候选预览、局部应用、排程与审计撤销；签名提醒；云备份和附件；Apple 日历及飞书接口。
- CSV/JSON/ICS 课程导入、列映射、重复课表和冲突处理；全局搜索和报告导出。
- Windows 原子文件保存、每日/手动/恢复前备份、系统凭据存储、系统通知、主题和减少动效。

## 启动与构建

```powershell
cd D:\Flowday\react-client
npm ci
npm run dev
npm run tauri -- dev
npm run tauri -- build --bundles nsis
```

开发预览：http://127.0.0.1:1420/?preview=1 。预览数据不写入工作区。正式客户端默认空数据，可导入 Flutter JSON 备份。

Windows 构建需要 Rust、Microsoft C++ Build Tools 和 WebView2。安装器位于 src-tauri/target/release/bundle/nsis/。

## 数据与服务

工作区位于应用数据目录 workspaces/<编码后的账号范围>/workspace.json，访客和各账号独立。试用 localStorage 会迁移到文件；保留原键和应用标识以兼容已有数据，不覆盖 Flutter 数据目录。

写入采用临时文件、同步磁盘后原子替换。原生客户端不受浏览器缓存配额限制；失败时保留可导出的当前数据并显示错误。导入或云替换前保存保护副本。令牌只保存在 Windows Credential Manager，不进入工作区或备份。浏览器开发模式不持久保存登录凭据。

API 默认使用 https://flowday.mtrx.pro/api/v1 。本轮未部署或修改生产服务。服务端兼容补丁在 ../server/src/validation.js，需随服务端更新部署，以接受今日布局数组、系统时区和旧通知的可空类型。

## 验证

```powershell
npm test
npm run test:ui
npm run build
cargo test --offline --lib --manifest-path src-tauri/Cargo.toml
npm run test:native
cd ..\server
npm test
```

浏览器回归使用本机 Edge。原生冒烟测试使用隔离的临时 WebView/工作区，不读取用户凭据；用本机 HTTP 服务检查请求、下载和同步记录，并验证清除浏览器缓存后仍可从文件恢复任务。调试端口只在测试进程启用。

## 验收边界

Windows 客户端及本地服务协议已实现。Apple、飞书、邮件和 AI 提供商需要服务器配置与实际账号，未进行生产端到端验收。Windows 系统通知标识要求安装客户端；本地提醒在客户端运行期间触发，关闭后的提醒由服务端队列及其已配置渠道处理。

iOS/Android/macOS 发行包和原生安全存储未完成，灵动岛未接入。Windows 和浏览器测试不能代替其他平台设备验收。ICS 无结束重复和 RECURRENCE-ID 调课实例保持 Flutter 原有拒绝边界。

字体使用现有 HarmonyOS Sans SC 全量 WOFF2，无远程字体请求。
