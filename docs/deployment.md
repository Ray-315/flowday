# FlowDay 原生客户端与服务端部署

**已部署到 `https://flowday.mtrx.pro`。** 当前服务器、端口、Caddy 网络和维护命令见[实际部署与维护](deployment-production.md)。以下是可复用的通用教程。

服务端是 Node.js 24 + SQLite，原生 Flutter 客户端通过 HTTPS 访问 `/api/v1`。服务器只运行后端，不需要安装 Flutter 或 Codex。

本文中的 SSH 别名、域名、代理容器名和 Caddyfile 路径需要按目标服务器替换。现有生产部署已获用户确认并通过 `sn-assets-prod` 完成；新服务器仍须重新检查身份、端口和代理状态。

## 1. 先确认目标与现有入口

在本机 PowerShell 7 中操作。使用你已经配置好的 OpenSSH 别名；先完成身份与资源检查，再执行部署。

```powershell
cd D:\Flowday
$Target = 'YOUR_CONFIRMED_SSH_ALIAS'
scp .\scripts\deploy-preflight.sh "${Target}:/tmp/flowday-preflight.sh"
ssh $Target 'sh /tmp/flowday-preflight.sh 33108'
```

预检脚本只读取主机名、当前用户、目录、监听端口、容器名称/镜像/状态/端口及 Caddy/Nginx 服务状态。它不读取 `.env`、容器环境变量或完整代理配置，不启动、停止或重启任何服务。

确认输出中的机器与用户符合预期。Docker 或监听检查失败时，不能把空输出当作“没有占用”。记录现有代理是宿主机服务还是 Docker 容器，并确认域名的 DNS 指向这台机器。

| 实际入口 | FlowDay 的上游地址 | 操作方式 |
| --- | --- | --- |
| 宿主机 Caddy/Nginx | `127.0.0.1:33108`，或实际选定宿主机端口 | 添加到现有代理配置 |
| Docker Caddy | 同一 Docker 网络上的 `flowday-api:3108` | 将 API 接入现有代理网络 |

**已有服务占用 80/443 时，继续使用它。不要再启动一个绑定 80/443 的 Caddy 容器。** Docker 容器内的 `127.0.0.1` 指向该容器自身；它不是宿主机回环地址。只绑定宿主机 `127.0.0.1` 的端口，也不能默认通过 `host.docker.internal` 从另一个容器访问。[Docker 端口发布说明](https://docs.docker.com/engine/network/port-publishing/)

## 2. 在本机生成发布包

仅打包后端和部署说明，不编译客户端：

```powershell
.\scripts\package-release.ps1
```

重新编译并打包 Windows 客户端，同时生成后端包：

```powershell
.\scripts\package-release.ps1 -BuildWindows
```

客户端地址已固定为 `https://flowday.mtrx.pro`，不再通过启动设置或构建参数修改。脚本先分析 Flutter，再进行 Windows release 构建；构建失败不会打包客户端。只有明确传入 `-BuildWindows` 才会执行构建。已有发布目录也可以通过 `-IncludeWindows` 打包，但脚本会检查安全存储插件等运行文件是否完整。

输出位于 `releases/`：后端 `*-server.tar.gz`、可选的完整客户端 `*-windows.zip`，以及对应 `.sha256` 文件。后端采用文件白名单，不包含 `.env`、数据库、附件数据、日志或 `node_modules`。Windows 包保留完整运行目录及字体资源，不能只复制 `flowday.exe`。

Android/iOS/macOS 的签名与构建需要各自平台工具和发行配置；这里的 Windows 包不能替代这些平台的安装包。

上传本次后端包和校验文件，文件名以脚本实际输出为准：

```powershell
$Archive = 'D:\Flowday\releases\YOUR_RELEASE-server.tar.gz'
scp $Archive "${Target}:/tmp/"
scp "$Archive.sha256" "${Target}:/tmp/"
ssh $Target
```

下文命令在已确认的 Linux 服务器上执行。示例使用 `/opt/flowday` 作为新部署目录；若你有其他部署规范，统一替换它。不要覆盖已有同名项目。

## 3. 创建发布目录与配置

先校验上传文件，再解压到新的发布目录：

```sh
cd /tmp
sha256sum -c YOUR_RELEASE-server.tar.gz.sha256
release_id='YOUR_RELEASE'
release_dir="/opt/flowday/releases/$release_id"
sudo install -d -m 0755 -o "$(id -u)" -g "$(id -g)" /opt/flowday/releases /opt/flowday/shared
test ! -e "$release_dir"
mkdir "$release_dir"
tar -xzf "/tmp/$release_id-server.tar.gz" -C "$release_dir"
cd "$release_dir/server"
```

若校验、目标目录检查或解压失败，先处理错误，不继续执行后续步骤。

第一次部署时创建持久配置；更新时保留原文件：

```sh
if [ ! -e /opt/flowday/shared/flowday.env ]; then
  install -m 0600 .env.example /opt/flowday/shared/flowday.env
fi
chmod 600 /opt/flowday/shared/flowday.env
nano /opt/flowday/shared/flowday.env
ln -s /opt/flowday/shared/flowday.env .env
```

在编辑器中设置这些非秘密配置：

```dotenv
HOST=0.0.0.0
PORT=3108
FLOWDAY_HOST_PORT=33108
DATABASE_PATH=/app/data/flowday.sqlite
PUBLIC_BASE_URL=https://flowday.your-domain.tld
SNAPSHOT_DIR=/app/data/snapshots
```

容器内端口固定为 3108。`FLOWDAY_HOST_PORT` 是宿主机端口：如果预检确认 3108 空闲，可以使用 3108；否则选择确认空闲的端口，例如 33108。Compose 同时将该端口绑定到宿主机回环地址。

AI 参数由管理员在这个权限为 600 的文件中填写；客户端不保存 AI、飞书或 Apple 应用专用密码。仅使用原生客户端时，`CORS_ORIGIN` 可以保持为空。

需要飞书或 Apple CalDAV 集成时，先生成服务端加密/动作密钥。以下命令只把随机密钥写入配置文件，不输出密钥；已有非空值会保留：

```sh
sudo docker run --rm -i \
  --mount type=bind,src=/opt/flowday/shared/flowday.env,dst=/config/flowday.env \
  node:24-bookworm-slim node --input-type=module - <<'JS'
import {readFileSync, writeFileSync} from 'node:fs';
import {randomBytes} from 'node:crypto';
const path = '/config/flowday.env';
let text = readFileSync(path, 'utf8');
for (const key of ['INTEGRATION_ENCRYPTION_KEY', 'ACTION_SIGNING_KEY']) {
  const expression = new RegExp('^' + key + '=\\s*$', 'm');
  if (expression.test(text)) text = text.replace(expression, key + '=' + randomBytes(32).toString('hex'));
}
writeFileSync(path, text, {mode: 0o600});
JS
```

妥善备份此配置文件。加密密钥改变或丢失后，已有集成凭据无法解密。不要执行会展开秘密配置的 `docker compose config`，也不要把完整 `docker inspect`、`.env` 或代理配置贴到公开日志中。

## 4. 启动 API

使用固定 Compose 项目名，避免发布目录变化导致创建另一份空数据卷：

```sh
cd "$release_dir/server"
sudo docker compose -p flowday build api
sudo docker compose -p flowday up -d api
sudo docker compose -p flowday ps
curl --fail --max-time 10 http://127.0.0.1:33108/health
```

预期健康接口返回成功 HTTP 状态。若使用了其他宿主机端口，替换这里的 33108。服务端使用 Node.js 24 容器；数据库和附件字节位于持久化命名卷中。只运行一个 API 实例。**不要执行 `docker compose down -v` 删除生产数据。**

首次确认健康后创建当前发布链接：

```sh
sudo ln -sfnT "$release_dir" /opt/flowday/current
```

`current` 应是本教程管理的软链接；如果那里已经是一个真实目录，先确认其用途。

## 5A. 已有宿主机 Caddy

确认现有服务实际使用的配置路径，将变量替换成那个路径。保留所有已有站点和全局配置：

```sh
CADDY_CONFIG='/ACTUAL/PATH/TO/Caddyfile'
stamp=$(date -u +%Y%m%dT%H%M%SZ)
sudo cp --preserve=all "$CADDY_CONFIG" "$CADDY_CONFIG.before-flowday-$stamp"
sudoedit "$CADDY_CONFIG"
```

在已有 Caddyfile 中加入这个站点块，域名与端口替换成实际值：

```caddyfile
flowday.your-domain.tld {
    reverse_proxy 127.0.0.1:33108
}
```

验证成功后，重载现有服务：

```sh
sudo caddy validate --config "$CADDY_CONFIG" --adapter caddyfile
sudo systemctl reload caddy
curl --fail --max-time 15 https://flowday.your-domain.tld/health
```

不要以 `caddy start`、`caddy reverse-proxy` 或另一个 Docker 容器替代这个重载步骤。Caddy 的验证与重载操作见[官方命令说明](https://caddyserver.com/docs/command-line)，systemd 部署见[官方运行说明](https://caddyserver.com/docs/running)。

如果现有入口实际是 Nginx，复用该入口及已有证书管理方式，参考包内 `server/README.md` 的 Nginx 站点配置。先执行 `sudo nginx -t`，成功后执行 `sudo systemctl reload nginx`，不同时启动 Caddy。

## 5B. 已有 Docker Caddy

宿主机回环地址不会跨容器。先确认代理容器的挂载与网络，以下只显示路径与网络名：

```sh
CADDY_CONTAINER='YOUR_EXISTING_CADDY_CONTAINER'
sudo docker inspect --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}' "$CADDY_CONTAINER"
sudo docker inspect --format '{{range $name, $settings := .NetworkSettings.Networks}}{{println $name}}{{end}}' "$CADDY_CONTAINER"
```

把 API 接入该代理**已经存在**的网络。在 `/opt/flowday/shared/compose.proxy.yaml` 中保存：

```yaml
services:
  api:
    networks:
      default: {}
      existing_proxy:
        aliases:
          - flowday-api
networks:
  existing_proxy:
    external: true
    name: YOUR_EXISTING_PROXY_NETWORK
```

应用此配置：

```sh
cd "$release_dir/server"
sudo docker compose -p flowday -f compose.yaml -f /opt/flowday/shared/compose.proxy.yaml up -d api
```

使用这种入口时，后续构建、更新、备份和回滚的每条 Compose 命令都应使用这两个 `-f` 参数，并保持 `-p flowday`。

备份并编辑刚才确认的宿主机挂载配置文件；不要覆盖已有内容。站点块使用容器端口：

```caddyfile
flowday.your-domain.tld {
    reverse_proxy flowday-api:3108
}
```

把以下路径替换成代理容器内的实际配置路径，然后验证、重载**这个现有容器**：

```sh
CADDY_IN_CONTAINER='/ACTUAL/PATH/TO/Caddyfile'
sudo docker exec "$CADDY_CONTAINER" caddy validate --config "$CADDY_IN_CONTAINER" --adapter caddyfile
sudo docker exec "$CADDY_CONTAINER" caddy reload --config "$CADDY_IN_CONTAINER" --adapter caddyfile
curl --fail --max-time 15 https://flowday.your-domain.tld/health
```

如果已有代理使用不同的管理端口或关闭了 Caddy 管理 API，使用该部署已有的重载流程。不要为 FlowDay 新建第二个 80/443 入口。

## 6. 客户端连接与验证

解压完整 Windows 包后运行 `FlowDay/flowday.exe`，直接注册或登录。新版固定使用 `https://flowday.mtrx.pro/api/v1`，登录页没有服务器地址输入框。

先注册测试账号，再创建一个日程。验证同步、重启客户端后的安全会话恢复、系统通知授权、未来日程通知和另一客户端的同步。系统钥匙串/凭据服务不可用时，客户端不会把令牌降级写入普通文件。

服务器提醒队列能在客户端离线时持续运行，生成站内通知并按配置发送飞书。原生系统通知是客户端本地安排与应用在线时的服务器轮询：**关闭客户端后的服务器原生推送尚未接入**。Linux 的本地到点提示需要应用运行；Android 通知采用非精确系统调度，实际交付受系统权限与后台限制影响。Apple 只提前安排最近 60 条，以适配系统队列限制；Windows 非 MSIX 安装的已显示通知存在平台取消限制。[原生通知插件说明](https://pub.dev/packages/flutter_local_notifications)

课程文件可在导入前预览和查看冲突。CSV/JSON/ICS 基础适配不能作为“极简课程表”专有格式已验证的证明，厂商格式仍需真实样本。真实 Apple 账户、飞书机器人、AI 服务与移动设备应在自己的测试环境完成联调。

## 7. 更新前制作一致数据库快照

数据库采用 SQLite WAL，不能只复制正在使用的 `.sqlite` 文件而忽略 WAL。以下使用 [Node SQLite 在线备份 API](https://nodejs.org/api/sqlite.html#sqlitebackupsourceDb-path-options)，快照包含账号、任务、日程、队列和数据库中的附件字节。

```sh
cd /opt/flowday/current/server
snapshot_name="before-update-$(date -u +%Y%m%dT%H%M%SZ).sqlite"
sudo docker compose -p flowday exec -T api node --input-type=module - "$snapshot_name" <<'JS'
import {DatabaseSync, backup} from 'node:sqlite';
import {mkdirSync, chmodSync} from 'node:fs';
const directory = '/app/data/snapshots';
mkdirSync(directory, {recursive: true, mode: 0o700});
const path = directory + '/' + process.argv[2];
const database = new DatabaseSync(process.env.DATABASE_PATH, {readOnly: true});
try { await backup(database, path); chmodSync(path, 0o600); }
finally { database.close(); }
JS
sudo install -d -m 0700 /opt/flowday/backups
sudo docker compose -p flowday cp "api:/app/data/snapshots/$snapshot_name" "/opt/flowday/backups/$snapshot_name"
sudo chmod 600 "/opt/flowday/backups/$snapshot_name"
sudo cp --preserve=mode /opt/flowday/shared/flowday.env "/opt/flowday/backups/flowday.env.$snapshot_name"
sudo chmod 600 "/opt/flowday/backups/flowday.env.$snapshot_name"
```

把数据库快照与对应配置通过授权的备份工具复制到独立、受保护的备份介质。数据库备份在同一磁盘上不能防止磁盘损坏；配置包含密钥，不能加入发布包。每日快照当前不自动删除，管理员需监控容量和设置自己的保留策略。

## 8. 更新与代码回滚

保留上次发布目录与当前容器镜像标记，再按第 2–3 节上传、校验并解压新包。下面的 `NEW_RELEASE` 必须是新目录，不能覆盖当前目录：

```sh
cd /opt/flowday/current/server
previous_release=$(readlink -f /opt/flowday/current)
api_container=$(sudo docker compose -p flowday ps -q api)
previous_image=$(sudo docker inspect --format '{{.Image}}' "$api_container")
rollback_tag="flowday-api:rollback-$(date -u +%Y%m%dT%H%M%SZ)"
sudo docker image tag "$previous_image" "$rollback_tag"

new_release='/opt/flowday/releases/NEW_RELEASE'
cd "$new_release/server"
ln -s /opt/flowday/shared/flowday.env .env
sudo docker compose -p flowday build api
sudo docker compose -p flowday up -d api
sudo docker compose -p flowday ps
curl --fail --max-time 10 http://127.0.0.1:33108/health
curl --fail --max-time 15 https://flowday.your-domain.tld/health
sudo ln -sfnT "$new_release" /opt/flowday/current
```

镜像构建或健康检查失败时，保留上次发布和数据，先排查。变量 `previous_release` 与 `rollback_tag` 要记录到管理员的更新记录中，供重新登录后回滚使用；它们不是密钥。

需要代码回滚时，给旧镜像创建明确的覆盖文件，然后从旧发布目录启动：

```sh
cat > /opt/flowday/shared/compose.rollback.yaml <<EOF
services:
  api:
    image: $rollback_tag
EOF
cd "$previous_release/server"
sudo docker compose -p flowday -f compose.yaml -f /opt/flowday/shared/compose.rollback.yaml up -d --no-build api
curl --fail --max-time 10 http://127.0.0.1:33108/health
sudo ln -sfnT "$previous_release" /opt/flowday/current
```

Docker Caddy 部署还需把 `-f /opt/flowday/shared/compose.proxy.yaml` 加入这条命令。代码回滚继续使用当前数据；如果还需要恢复数据库，按下一节执行。不要删除卷，也不要使用尚未校验的快照覆盖数据库。

代理配置回滚使用第 5 节保存的原文件，恢复后先 `caddy validate` 再重载现有代理；保留其他站点。

## 9. 恢复数据库快照

恢复会回到快照时刻，快照之后的数据不会保留。先为当前数据库再制作一份快照，并确认所选快照与配置密钥匹配。下面以仍保存在持久卷 `snapshots/` 中的快照为例。

```sh
cd /opt/flowday/current/server
restore_name='YOUR_VERIFIED_SNAPSHOT.sqlite'
sudo docker compose -p flowday stop api
sudo docker compose -p flowday run --rm --no-deps --entrypoint node api --input-type=module - "$restore_name" <<'JS'
import {DatabaseSync} from 'node:sqlite';
import {existsSync, mkdirSync, renameSync, copyFileSync, chmodSync} from 'node:fs';
import {resolve, basename} from 'node:path';
const name = process.argv[2];
if (!/^[A-Za-z0-9_.-]+$/.test(name)) throw Error('Invalid snapshot name');
const source = '/app/data/snapshots/' + name;
const databasePath = resolve(process.env.DATABASE_PATH);
if (!databasePath.startsWith('/app/data/')) throw Error('Database is outside the persistent volume');
const check = new DatabaseSync(source, {readOnly: true});
try {
  if (check.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok') throw Error('Snapshot integrity check failed');
} finally { check.close(); }
const previous = '/app/data/before-restore-' + Date.now();
mkdirSync(previous, {mode: 0o700});
for (const suffix of ['', '-wal', '-shm']) {
  const path = databasePath + suffix;
  if (existsSync(path)) renameSync(path, previous + '/' + basename(path));
}
copyFileSync(source, databasePath);
chmodSync(databasePath, 0o600);
JS
sudo docker compose -p flowday up -d api
curl --fail --max-time 10 http://127.0.0.1:33108/health
```

旧数据库及 WAL/SHM 会移入新的 `before-restore-*` 目录，保留现场。任何检查失败时，不继续执行后续恢复步骤。外部备份需要先通过受保护的管理流程放回卷内并设置为容器 `node` 用户可读；不直接覆盖正在运行的数据库。

部署结束后，再次运行只读预检，并验证原有站点仍可访问。现有生产部署已完成，详细实测结果见[实际部署与维护](deployment-production.md)；新环境以现场检查为准。
