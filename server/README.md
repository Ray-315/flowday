# Flowday server

独立 Node.js 服务，使用 Fastify 与 SQLite WAL。Node.js 24 或更高版本；默认 `127.0.0.1:3108`。前端通过 `/api/v1` 连接，无需安装 Flutter 到服务器。

## 本地启动

```powershell
cd D:\Flowday\server
npm ci
npm test
npm start
```

默认数据库为当前目录的 `data/flowday.sqlite`。配置来自进程环境变量；如使用 `.env`，执行 `node --env-file=.env src/index.js`。密码最少 10 字符，scrypt 散列；令牌有效期 30 天，数据库只保存其 SHA-256 散列。HTTP 请求体与认证信息不写日志。

## 自有 Linux 服务器

复制 `server/` 到服务器，例如 `/opt/flowday/server`，然后：

```sh
cp .env.example .env
chmod 600 .env
# 编辑 .env，填写自己的域名来源和可选集成参数
docker compose up -d --build
docker compose ps
curl --fail http://127.0.0.1:3108/health
```

容器以 `node` 非 root 用户运行，数据库保存在 `flowday_data` 命名卷。不要使用 `docker compose down -v` 删除生产数据。仅运行一个 API 实例；SQLite 不是多副本共享数据库。`DATABASE_PATH` 必须指向持久化卷。更新前应离线备份卷，或使用 SQLite 在线备份工具；运行中的 `.sqlite` 文件不能脱离 WAL 单独复制。

Nginx HTTPS 站点示例（先配置自己的证书路径）：

```nginx
server {
    listen 443 ssl;
    server_name flowday.example.com;
    ssl_certificate /etc/letsencrypt/live/flowday.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/flowday.example.com/privkey.pem;
    client_max_body_size 2m;
    location / {
        proxy_pass http://127.0.0.1:3108;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 40s;
    }
}
```

原生客户端不依赖 CORS；Web 客户端将 `CORS_ORIGIN` 设为逗号分隔的精确来源。默认不信任代理提供的客户端 IP；经 Nginx 访问时限流按代理 IP 汇总，避免伪造转发头绕过限制。

## 服务任务与集成

注册需要邮箱验证码。配置 `MAIL_FROM`、`MICROSOFT_TENANT_ID`、`MICROSOFT_CLIENT_ID`、`MICROSOFT_CLIENT_SECRET` 及已有 `ACTION_SIGNING_KEY`；微软应用通过 Graph 发送邮件。缺少配置时拒绝发送验证码，不能绕过邮箱验证注册。[生产配置教程](../docs/deployment-production.md#邮箱验证码与开放注册)包含后台操作步骤。

工作区同步会依据 `reminderMinutes`、`strongReminder`、`reminderInterval`、`maxReminders` 为未来日程维护提醒。修改时间或默认设置会重新安排；无关同步不重置确认状态或发送次数，完成/删除日程会停止。普通日程提醒发送一次；强提醒可重复直至确认、达到上限或日程结束。手动任务提醒仍通过 `/reminders` 创建。

账号管理新增 `PUT /auth/profile`、`POST /auth/password`、`GET /auth/sessions`、`POST /auth/sessions/revoke-others` 和 `POST /auth/delete`。修改密码撤销其他会话；注销需要密码与明确确认，只删除当前账号的数据。

进程每 15 秒检查持久化提醒，无需客户端在线。通知生成会增加工作区版本，客户端应处理 409。强提醒仅通过提醒确认接口停止（达到最大次数、任务完成或删除也会停止）；把通知标记为已读不会停止。普通提醒确认后仍按次数发送。

飞书支持每位用户通过 `/integrations/feishu` 配置独立机器人，凭据使用 `INTEGRATION_ENCRYPTION_KEY`（随机32字节的64位十六进制字符串）加密保存。`FEISHU_WEBHOOK_URL` 是可选的旧版默认机器人。卡片动作需要 `ACTION_SIGNING_KEY`（随机且至少24字符）及 `PUBLIC_BASE_URL`，链接30分钟有效、单次使用，打开链接后确认才执行。签名格式遵循[飞书官方机器人说明](https://open.feishu.cn/community/articles/7271149634339422210)。发送失败保存在 `lastError`；提醒仍先生成站内通知。外部发送为尽力投递，进程在站内通知提交与网络发送之间退出时可能漏发。

自然语言 AI 必须配置 `AI_BASE_URL`（包含 `/v1`）、`AI_API_KEY`、`AI_MODEL`；所配 OpenAI Chat Completions 兼容服务会收到用户文本及相关工作区对象。明确操作返回一个候选，歧义要求三个；服务器验证创建、修改、移动和软删除意图。`/ai/schedule` 使用服务端约束规划器生成三个策略，不依赖模型配置。预览不修改工作区，确认支持选择候选和局部动作；过时预览返回冲突。AI 操作保存可逆差异和原文，`/audit/:id/undo` 检查后续对象修改后撤销。

每日首次轮询创建包含工作区和附件字节的逻辑备份，之后清理删除超过30天的对象。支持指定日期恢复预览、JSON/CSV 导出、完整个人附件归档导出和导入。`POST /api/v1/import/archive` 接收 `{baseVersion,archive}`，完整校验后在同一事务中创建保护备份并替换工作区及附件；失败全部回滚。配置 `SNAPSHOT_DIR` 后每个 UTC 日期还生成一次一致 SQLite 数据库快照，使用 [Node SQLite 在线备份 API](https://nodejs.org/api/sqlite.html#sqlitebackupsourceDb-path-options)。快照包括账号和提醒队列，属于管理员文件；恢复需停止服务后将选定快照替换 DATABASE_PATH，并移走旧 WAL/SHM。务必将快照复制到独立备份介质并监控磁盘；当前不自动删除历史备份。附件上传最大1MiB、每人100MiB。

容器端口固定3108，宿主机回环端口由 `FLOWDAY_HOST_PORT` 调整。加密密钥和签名密钥只通过进程环境变量提供；妥善备份加密密钥，丢失后已有集成凭据无法解密。不要把密钥写入仓库或日志。

Apple Calendar 已提供 CalDAV 发现、连接、双向同步和版本冲突处理；每位用户的 Apple ID / 应用专用密码通过相同集成密钥加密。使用 [tsdav 官方 API](https://tsdav.vercel.app/docs/caldav/fetchCalendarObjects) 与 [ICAL.js](https://github.com/kewisch/ical.js)，保留原始外部内容，支持单次重复实例编辑和 EXDATE 删除。默认后台5分钟同步，条件写入保护远端版本；双方修改时保留冲突，用户明确选择版本后处理。默认仅允许 iCloud HTTPS 主机，其他服务器需 CALDAV_ALLOWED_HOSTS 管理员允许。真实 Apple 账户尚未联调；模拟 HTTP 测试覆盖实际 DAV 请求和双向变更。

课程厂商格式仍需真实文件样本。原生系统通知及附件交互由客户端接入这些接口。日期时间 API 建议始终发送带 Z 或偏移的 ISO8601；客户端需将用户时区正确转换。

接口定义见 `../docs/backend-api.md`。Docker 构建和实际外部集成需在部署环境验证。
