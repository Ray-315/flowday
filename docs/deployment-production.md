# FlowDay 已部署服务器与维护

部署日期：2026-10-03（北京时间）。

## 客户端连接

新版客户端已固定连接以下地址，登录页无需填写服务器设置：

```text
https://flowday.mtrx.pro
```

客户端自动使用 `/api/v1`。旧版若保存了其他服务器的登录凭据，升级后需重新登录；原本地数据保留。此地址提供后端服务；本项目是原生客户端，没有 Web 首页。

## 实际部署信息

| 项目 | 当前配置 |
| --- | --- |
| 本机 SSH 别名 | `sn-assets-prod` |
| 主机／用户 | `VM-0-10-ubuntu`／`ubuntu` |
| 当前发布 | 执行 `readlink -f /opt/flowday/current` 查看 |
| 当前发布链接 | `/opt/flowday/current` |
| 配置文件 | `/opt/flowday/shared/flowday.env`，权限 600 |
| 代理网络覆盖 | `/opt/flowday/shared/compose.proxy.yaml` |
| Compose 项目／服务 | `flowday`／`api` |
| API 容器 | `flowday-api-1` |
| 宿主机入口 | `127.0.0.1:33108` |
| 容器内入口 | `3108` |
| 数据卷 | `flowday_flowday_data` |
| 现有代理 | `atrium-caddy`，继续管理原有 80／443 |
| 代理网络与上游 | `atrium_default`／`flowday-api:3108` |
| Caddy 配置 | 宿主机 `/opt/atrium/caddy/Caddyfile`，容器 `/etc/caddy/Caddyfile` |
| 修改前代理备份 | `/opt/atrium/caddy/Caddyfile.before-flowday-20261002T171114Z`（文件名为 UTC 时间） |
| 首次部署数据库快照 | 数据卷中 `/app/data/snapshots/deployment-20261003.sqlite` |

服务端加密与提醒动作密钥已生成。AI 模型服务尚未配置；飞书和 Apple 需要各账号在客户端设置中连接。不要把配置文件或密钥贴到聊天、日志或发布包。

## 日常检查

本机 PowerShell：

```powershell
ssh sn-assets-prod
```

服务器中：

```sh
cd /opt/flowday/current/server
dc() {
  sudo docker compose -p flowday \
    -f compose.yaml \
    -f /opt/flowday/shared/compose.proxy.yaml "$@"
}
dc ps
curl --fail --max-time 10 http://127.0.0.1:33108/health
curl --fail --max-time 15 https://flowday.mtrx.pro/health
```

两个健康接口都应返回 `{"status":"ok"}`。后续每条 Compose 命令都要保留项目名和网络覆盖文件，否则可能断开现有 Caddy 网络。

## 配置 AI 或更新服务配置

在服务器编辑配置，不要在命令行直接输入密钥：

```sh
nano /opt/flowday/shared/flowday.env
```

填写 `AI_BASE_URL`（兼容接口地址，通常包含 `/v1`）、`AI_API_KEY`、`AI_MODEL`。保持现有 `INTEGRATION_ENCRYPTION_KEY`、`ACTION_SIGNING_KEY`、端口和数据库配置。

在前述目录定义 `dc` 后应用配置：

```sh
dc up -d api
dc ps
curl --fail --max-time 10 http://127.0.0.1:33108/health
```

不要启动第二个 Caddy，不要把 API 发布到公网 80／443。

## 邮箱验证码与开放注册

发件地址：`flowday-noreply@mtrx.pro`。当前实现使用 Microsoft 365 企业邮箱的 Microsoft Graph 应用授权；若 Outlook 仅作为其他服务商邮箱的客户端，先确认实际邮件服务商。

### 获取三个配置值

1. 打开 [Microsoft Entra 管理中心](https://entra.microsoft.com)，进入「应用注册」→「新注册」，名称填写 `FlowDay`，选择仅当前组织，重定向 URI 留空。
2. 注册完成后，在「概述」页复制「目录（租户）ID」到 `MICROSOFT_TENANT_ID`，「应用程序（客户端）ID」到 `MICROSOFT_CLIENT_ID`。
3. 「证书和密码」→「客户端密码」→「新客户端密码」。将生成的**值**填写到 `MICROSOFT_CLIENT_SECRET`，不是「密码 ID」。值只显示一次，直接存入服务器配置，不要贴到聊天或日志。密码到期前需更换。
4. 「API 权限」→「添加权限」→ Microsoft Graph →「应用程序权限」→ `Mail.Send`，由管理员授予同意。不需要读取邮件权限。按[Exchange 应用访问范围文档](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac)把应用权限限制到发件邮箱；避免额外保留未受限的租户级授权。没有租户管理权限时由邮箱管理员操作。
5. 确认 Microsoft 365 中该发件邮箱真实存在且可以发信，域名邮件记录由邮件管理员按 Microsoft 365 要求配置；Cloudflare 的 FlowDay 网站记录不能代替邮箱记录。

### 写入服务器配置

本机执行 `ssh sn-assets-prod`，登录后编辑：

```sh
nano /opt/flowday/shared/flowday.env
```

填写下面四项，值只保存在服务器：

```dotenv
MAIL_FROM=flowday-noreply@mtrx.pro
MICROSOFT_TENANT_ID=
MICROSOFT_CLIENT_ID=
MICROSOFT_CLIENT_SECRET=
```

保持原有 `ACTION_SIGNING_KEY`。保存退出后执行：

```sh
cd /opt/flowday/current/server
sudo docker compose -p flowday -f compose.yaml \
  -f /opt/flowday/shared/compose.proxy.yaml up -d api
```

新版客户端进入注册页，填邮箱并点击「发送验证码」，收到邮件后输入验证码完成注册。验证码 6 位、10 分钟有效；发送间隔 60 秒、每个邮箱每小时最多 5 次，输错 5 次需重新获取。发送接口成功仅表示微软已接受发送请求，最终送达仍需检查收件箱与垃圾邮件箱。[微软发送接口说明](https://learn.microsoft.com/en-us/graph/api/user-sendmail?view=graph-rest-1.0)

缺少配置或发信失败时，服务拒绝新注册。现有账号仍可正常登录。完成实际收信和注册验证后才算开放注册完成。

### 当前发信联调结果（2026-10-03）

- 邮箱验证码后端已部署到 `/opt/flowday/releases/FlowDay-20261003-021508`，公开注册接口已强制验证。
- 三个微软授权配置已填入；授权接口返回 200，`Mail.Send` 权限有效。
- 发件地址 `flowday-noreply@mtrx.pro` 已修复，Graph 发信返回 202 Accepted；公网 `POST /api/v1/auth/registration-code` 返回 200 `{sent:true,retryAfterSeconds:60}`，验证码注册入口已可用。
- 已向发件邮箱发送验证码测试邮件。微软接受发送请求已验证；收件箱送达与新版客户端注册仍需实际确认。
- 更新前数据库备份位于数据卷 `/app/data/snapshots/before-email-registration-20261003.sqlite`；原配置备份位于 `/opt/flowday/shared/flowday.env.before-email-registration`，含敏感值，只保留在服务器。

## 更新与备份

[完整部署教程](deployment.md)第 7–9 节包含数据库在线快照、发布更新和回滚步骤。实际维护时使用本页的 SSH、域名、目录和端口，并为所有 Compose 命令增加：

```sh
-p flowday -f compose.yaml -f /opt/flowday/shared/compose.proxy.yaml
```

备份须同时保留数据库快照和匹配的 `flowday.env`。不要直接复制正在使用的 SQLite 主文件，也不要执行 `docker compose down -v`。

## 本次实际验证

- 本机后端 61 项自动测试通过；客户端 186 项测试与 Windows release 编译通过。
- 服务器镜像构建、持久卷初始化和 Docker 健康检查通过。
- 本机及服务器的公网 HTTPS 健康检查通过，Caddy 容器内上游访问通过。
- 使用临时账号通过公网验证注册登录、工作区写入／读取／版本冲突、多提醒确认和签名动作、附件上传下载、完整归档恢复、三候选排程／应用／审计撤销、CSV 导出。
- 临时账号已删除，验证结束时用户数量为 0。
- 数据库完整性检查为 `ok`，首次部署快照已生成。
- Caddy 原配置全部字节保留，仅追加 FlowDay 站点；原有容器持续运行。

真实 AI、Apple、飞书与各平台通知交付仍需账号和设备联调，以上部署验证不替代这些验收。
