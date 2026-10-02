# Flowday API v1

默认 `http://127.0.0.1:3108/api/v1`。JSON 请求体；除注册、登录外均发送 `Authorization: Bearer <token>`。`GET /health` 无需认证。所有数据归属取自会话，不能提供 userId。错误结构为 `{ "error": { "code": "...", "message": "..." } }`。

## 认证与工作区

注册必须使用发送到对应邮箱的 6 位验证码，10 分钟有效、成功注册后失效。每个邮箱发送间隔 60 秒，每小时最多 5 次，单个验证码最多 5 次错误尝试。未配置微软发信服务返回 503 `MAIL_NOT_CONFIGURED`，发送失败返回 502 `MAIL_DELIVERY_FAILED`，均不会创建账号。已有账号登录不受影响。

| Method | Path | Request | Response |
| --- | --- | --- | --- |
| POST | /auth/registration-code | `{email}` | `{sent:true,retryAfterSeconds:60}` |
| POST | /auth/register | `{email,password,displayName,verificationCode}` | 201 `{token,user:{id,email,displayName}}` |
| POST | /auth/login | `{email,password}` | `{token,user:{id,email,displayName}}` |
| GET | /auth/me | — | `{user:{id,email,displayName}}` |
| POST | /auth/logout | — | 204 |
| PUT | /auth/profile | `{displayName}` | `{user}` |
| POST | /auth/password | `{currentPassword,newPassword}` | `{changed:true}` |
| GET | /auth/sessions | — | `{sessions:[{current,expiresAt}]}` |
| POST | /auth/sessions/revoke-others | — | `{revoked}` |
| POST | /auth/delete | `{password,confirmation:"DELETE"}` | 204 |
| GET | /workspace | — | `{version,data}` |
| PUT | /workspace | `{baseVersion,data}` | `{version}` |

注册密码 10–256 字符。首次工作区版本 0；data 为 schemaVersion 1，包含空 projects/tasks/events/nodes/edges/captures/notices 数组和 preferences 对象。对象字段与 Flutter `lib/domain/models.dart` 一致；不接受未知对象字段。可选字段省略时由 Flutter 模型使用默认值。整体请求最大 2 MiB，各集合最大 10000 个对象。

PUT 使用原子比较更新，旧版本返回 HTTP 409：`{error:{code:"VERSION_CONFLICT",message:"..."},currentVersion:1}`。重新读取并向用户保留本地修改，禁止盲目覆盖。提醒、恢复、AI 提交和清理也增加版本。服务校验标识唯一、引用存在、父级无循环、连线所属项目一致、日期/枚举类型及时间范围。

preferences 支持已知设置类型；未知设置仅支持字符串、有限数字、布尔和 null。todayModules 支持字符串数组。密码、API key、令牌、webhook 等字段禁止保存于工作区。

## 提醒

- `GET /reminders` → `{reminders:[...]}`。
- `POST /reminders`：`{title,dueAt,taskId?,intervalMinutes?:5,maxReminders?:3,strong?:true,channel?:"in_app"}`。dueAt 为 ISO 日期时间，建议带时区；intervalMinutes 1–10080，maxReminders 1–100；channel 可为 `in_app` 或 `feishu`。返回 `{reminder:{id,title,taskId,dueAt,intervalMinutes,maxReminders,sentCount,acknowledged,strong,channel,lastError}}`。
- `POST /reminders/:id/ack` → `{acknowledged:true}`。只有强提醒因此停止重复；已读状态不等于确认。

提醒队列独立持久化。工作区 PUT 为未来日程维护事件提醒（返回 eventId）；提前时间等默认值来自 preferences。普通提醒一次，强提醒按间隔/次数重复；日程完成、删除、结束或关联任务完成后停止。手动任务提醒仍用 POST 创建。用户只可访问自己的提醒。

- Event 可选 `reminderRules` 为 `null` 或最多10项的规则列表，每项为 `{leadMinutes:0..10080}` 或 `{dueAt:ISO}`，必须且只能提供一种时间；重复规则拒绝。省略或 `null` 沿用默认一条提醒，`[]` 关闭事件自动提醒。默认提前时间取 Event `reminderLeadMinutes`（可空，0..10080），否则取全局 `preferences.reminderMinutes`；`preferences.courseReminderLeadMinutes`（0..10080）供客户端课程导入时写入事件覆盖值。
- 每条规则独立保留发送次数和确认状态。相对规则随事件开始时间调整，绝对规则在重新排程时保留指定时间；无关同步和规则排序不会重置进度。过期的提前点在事件仍未开始时立即提醒。全局强提醒间隔、次数、开关改变时重排自动规则。所有规则仍遵守上述日程结束后的停止条件。
- Task 和 Event 均支持可空 `strongReminder`（bool）、`reminderInterval`（1..10080分钟）、`maxReminders`（1..50）。空值继承；事件按“事件 → 关联任务 → 全局”逐字段取值。自动提醒有效重复次数最大50，普通提醒始终一次。带 `taskId` 的手工 POST 提醒在未提供 `strong/intervalMinutes/maxReminders` 时使用任务覆盖后的配置，显式请求参数优先；不带任务的手工提醒保持原默认值。
- 有截止时间的未完成任务生成一条 `ruleKey:"deadline"` 持久提醒，在截止时间触发；首次同步已经逾期的任务立即触发。该提醒采用任务强提醒配置，确认后终止强提醒链，到达次数上限后停止；普通提醒只发一次，不因每天轮询或无关同步重复。删除、完成、取消任务或清除截止时间会撤销自动截止提醒；更改截止时间或有效强提醒配置会重排。服务重启会补齐旧数据的截止提醒，不要求客户端持续运行。
- 提醒返回 `ruleKey`：`default`、`lead:<分钟>`、`at:<UTC毫秒>` 表示事件自动规则；`null` 表示手工或 AI 独立提醒。自动规则更新与 AI 修改其中一条时保留其他关联提醒。
- Notice 可选 `type` 为 `reminder|calendar_conflict|workflow|ai|system`，以及可空 `eventId/projectId/nodeId`，用于客户端跳转；原 `taskId` 保留。服务生成的提醒通知填入关联事件、任务、项目；日历冲突通知填入 `calendar_conflict` 及关联事件。引用必须存在于工作区；旧通知省略这些字段仍可同步。

## AI 两阶段提交与候选排程

- `POST /ai/preview`：`{text,timezone}`，timezone 为 IANA 名称；返回 `{previewId,baseVersion,intent,candidates,expiresAt}`，15 分钟有效。`intent` 保留兼容首个候选。`candidates` 是 `{id,label,intent:{actions:[...]},diff:[{type,id,before,after}]}` 数组；明确输入一个候选，歧义输入要求模型给出三个。未配置返回 503 `AI_NOT_CONFIGURED`；无效供应商结果返回 502 `AI_INVALID_RESPONSE`。
- 动作类型为 `todo`、`event`、`todo_update`、`event_update`、`event_delete`、`reminder`、`reminder_update`，最多200条。创建需要title；事件需要start/end，提醒需要dueAt。修改、删除需要当前用户已有对象id。Todo 支持 title/status/priority/difficulty/estimateMinutes/deadline/plannedStart/projectId；事件支持 title/start/end/taskId/projectId/completed；提醒支持 title/dueAt/taskId/intervalMinutes/maxReminders/strong/channel。提醒差异标记 collection="reminders"，与工作区变更在同一事务提交，审计撤销同样校验提醒后续修改。删除动作只接受type/id，并进入回收站。不得修改锁定、已开始、已完成事件。禁止创建流程节点和连线。
- `POST /ai/schedule`：`{taskIds,start,end,timezone,replan?:false,excluded?:[{start,end}]}`。排程范围必须在未来且不超过31天。返回与 AI 预览相同结构，包含尽快完成、均衡负载、减少改动三个候选。此接口由服务端约束规划器计算，无需模型密钥；自然语言解析仍需要模型配置。检查截止时间、估计耗时、优先级、流程节点依赖状态、允许拆分、现有日程和排除时间；只移动未开始、未完成、未锁定的时间块。减少改动策略保留已有事件标识。无可用安排返回422 `NO_SCHEDULE_AVAILABLE`；已全部安排返回422 `ALREADY_SCHEDULED`。
- `POST /ai/apply`：`{previewId,baseVersion,candidateId?,actionIndexes?}` → `{version,applied:true,auditId}`。多个候选必须提供 candidateId；actionIndexes 支持局部接受。服务器读取保存的意图，调用方不能替换动作。预览后工作区变化返回409 `PREVIEW_STALE`；过期返回410。同一 previewId 重试不会重复执行。
- `GET /audit` → `{records:[{id,action,createdAt,reversible,version?,input?,intent?,diff?}]}`，最近100条用户操作记录。AI 记录保存原文、选择与最终差异，其他操作保留动作记录。
- `POST /audit/:id/undo`：`{baseVersion}` → `{version,undone:true}`。撤销 AI 变更，保留无关对象的后续修改；被影响对象已再次改变返回409 `UNDO_CONFLICT`。撤销创建时若出现新的关联引用，正常引用校验会阻止删除。确认前预览不改变工作区。

## 备份

- `GET /backups` → `{backups:[{id,createdAt,reason,version}]}`，最近 100 条。
- `POST /backups` → `{id,createdAt,reason:"manual",version}`。
- `POST /backups/:id/restore`：`{baseVersion}` → `{version,protectionBackup:{id,createdAt,reason:"before_restore",version}}`。

恢复前先创建保护备份，两项操作与 CAS 在同一事务内。冲突时全部回滚。每日逻辑备份包含工作区及附件接口中的文件内容，不包含账号或提醒队列。恢复不回退版本号。其他用户对象返回404。

- `POST /backups/restore-preview`：`{at:ISO8601}` → `{backupId,createdAt,baseVersion,changes:[{collection,currentCount,restoredCount,changed}]}`。选择指定时间之前最近备份；预览后使用现有恢复接口确认。
- `GET /backups/status` → `{databaseSnapshot:{enabled,lastSuccessAt,lastError}}`。配置 SNAPSHOT_DIR 后每个 UTC 日期生成一次一致 SQLite 快照，包含账号、提醒、附件字节等完整数据库；这是管理员文件，不能通过个人 API 下载。
- `GET /export/json` 下载 schemaVersion1 个人工作区；`GET /export/csv?collection=tasks|events|statistics` 下载 UTF8 CSV，防止表格公式注入。
- `GET /export/archive` 下载 `{schemaVersion:1,workspace,attachments:[...metadata,contentBase64]}` 完整个人附件清单及字节，包含回收站中的附件。普通工作区 JSON 导入仍使用带 CAS 的工作区 PUT。
- `POST /import/archive` 接收 `{baseVersion,archive}`，其中 `archive` 是上述完整导出对象；返回 `{version,protectionBackup:{id,createdAt,version,reason},importedAttachments}`。服务先校验整个归档，再在单一事务中创建 `before_import_archive` 保护备份、按 CAS 替换工作区和全部个人附件。归档中的附件标识、所属任务或项目、内容格式、声明大小、日期和配额必须合法；其他用户已占用的附件标识不可导入。失败时工作区、附件和备份全部保持原状，过期版本返回409。保护备份可通过现有备份恢复接口还原原工作区及文件字节。
  - 附件字段完整保留导出格式：`id,ownerType,ownerId,kind,name,mediaType,size,url,markdown,createdAt,deletedAt,contentBase64`；不适用的值必须为 `null`，文件内容为规范 Base64。所属对象必须存在于归档工作区，可包含回收站对象；每文件最大1MiB，所有附件文件累计最大100MiB，工作区 JSON 最大2MiB，整个请求最大150MiB。此接口每15分钟最多10次请求。

## 用户级飞书配置与安全动作

- `GET /integrations/feishu` → `{configured}`；`PUT /integrations/feishu` 接受 `{webhookUrl,secret?}`，只允许飞书官方 HTTPS 机器人地址；响应仅返回配置状态。需要环境变量 INTEGRATION_ENCRYPTION_KEY（64位十六进制、32字节），凭据使用 AES256GCM 存储，不进入工作区或配置读取响应。
- `POST /integrations/feishu/test` → `{delivered:true}`；`POST /integrations/feishu/disconnect` 移除个人配置。旧环境变量 FEISHU_WEBHOOK_URL 可作为服务器默认机器人；设置它时断开个人配置仍会使用默认机器人。
- 自动事件提醒在用户飞书已配置时发至飞书，否则产生站内通知。发送卡片显示标题、日程时间及项目。签名机器人可配置个人 secret 或 FEISHU_WEBHOOK_SECRET。
- `POST /reminders/:id/actions`：`{action:"ack"|"start"|"complete"|"snooze"|"postpone"|"open",minutes?}` → `{token,expiresAt,url?}`。snooze/postpone 需要1–10080分钟。动作以 HMAC 签名绑定服务器记录，30分钟有效；写动作仅能执行一次，需要 ACTION_SIGNING_KEY（至少24字符）。PUBLIC_BASE_URL 用于卡片链接。
- `POST /reminder-actions`：`{token}` → `{executed:true,action}`，通过签名授权，无需额外登录。GET 卡片动作链接只打开确认表单，POST 才执行；避免预取修改数据。稍后提醒只修改提醒时间，开始/完成只修改关联任务。postpone 展示原起止与新起止时间，确认前不修改日程；若日程时间已改变返回409。open 的签名链接打开只读关联详情，在有效期内可重复读取，不改变工作区。
- 飞书失败记录 `lastError=FEISHU_DELIVERY_FAILED`；站内通知先持久化。外部发送采用尽力投递；崩溃窗口无法保证飞书恰好一次。浏览器推送和原生系统通知需要客户端设备适配。

## 附件

- `GET /attachments` → `{attachments:[{id,ownerType,ownerId,kind,name,mediaType,size,url,markdown,createdAt,deletedAt}]}`。
- `POST /attachments`：`{ownerType:"task"|"project",ownerId,kind:"file"|"url"|"markdown",name,mediaType?,contentBase64?,url?,markdown?}` →201 `{attachment}`。文件最大1MiB，每人文件总量100MiB；Markdown最大10万字符；所属任务或项目必须属于当前用户。附件二进制存 SQLite，因此数据库快照包含文件。
- `GET /attachments/:id/download` 需要登录且验证归属，以附件方式下载；他人标识返回404。`POST /attachments/:id/delete`、`POST /attachments/:id/restore` 为回收站动作，30天后清理。
- 原生模型内嵌 attachments 的 `{id,title,kind,content}` 同样由工作区保存；实际二进制上传使用本节独立接口。项目、任务、事件的内嵌附件都会进入工作区备份和 JSON 导出。

## Apple Calendar / CalDAV 双向同步

- `POST /integrations/apple/discover`：`{username,password,serverUrl?:"https://caldav.icloud.com"}` → `{calendars:[{url,displayName}]}`。iCloud 使用 Apple ID 和应用专用密码，通过实际 PROPFIND 完成账户、主目录与日历发现。
- `PUT /integrations/apple`：上述凭据加 `{calendarUrl}` → 连接状态。所选地址必须出现在账户发现结果中；凭据使用 INTEGRATION_ENCRYPTION_KEY 加密。更换到另一日历前先断开旧连接。
- `GET /integrations/apple` → `{configured,calendar?,lastSyncAt?,lastError?,records,conflicts}`。records 为 `{eventId,source:"apple"|"local",status:"synced"|"pending"|"conflict",lastSyncAt,conflictId}`；conflicts 为 `{id,eventId,local,remote,remoteDeleted,createdAt}`。外部来源与同步状态通过事件标识关联，不占用业务事件模型额外字段。响应不返回密码。
- `POST /integrations/apple/sync`：`{eventIds?:[]}` → `{version,imported,pushed,deleted,conflicts}`。默认同步该账户选定日历与所有本地日程；eventIds 可限制本次向外写入的本地事件，向内导入仍涵盖选定日历。服务端后台默认每5分钟同步，CALDAV_SYNC_INTERVAL_MS 可调整且至少60秒。失败时 lastError=CALDAV_SYNC_FAILED，可重试；此前完成的对象同步会保留。
- 同步标题、时间、全天、地点、备注和支持的重复规则。导入事件默认 locked=true，本地项目、任务关联和标签保留。用 UID 与远端地址保存映射，重复同步不重复创建。远端删除进入本地回收站，本地删除对外删除；写入使用 If-Match，创建使用 If-None-Match，远端在请求中变化返回409 CALDAV_REMOTE_CHANGED。
- 双方都改变同一事件时生成冲突及站内通知，保留两个版本，不覆盖。`POST /integrations/apple/conflicts/:id/resolve`：`{choice:"local"|"remote",baseVersion}` → `{version,resolved:true}`。重新读取远端和工作区校验用户所见版本；发生后续变更时需重新同步。所有连接、映射与冲突按会话用户隔离。
- `POST /integrations/apple/disconnect`：`{keepLocal?:true}` → `{configured:false}`。默认保留本地副本；false 将同步副本移至回收站。断开不会删除远端日历。
- 外部复杂重复规则由 ICAL.js 展开到过去30天至未来366天；已映射实例继续跟踪。单次编辑保留主系列并写 recurrence exception；删除实例写 EXDATE。每资源最多2000实例，迭代最多20000次，超限返回明确错误，避免无界展开。原始外部时区、未知属性和其他组件在修改时保留。
- 默认仅允许 iCloud HTTPS 主机；其他 CalDAV 服务器需管理员通过 CALDAV_ALLOWED_HOSTS 精确允许。每次请求、发现地址和重定向均检查主机；使用 tsdav 与 ICAL.js，不执行用户提供的任意网络地址。实际 Apple 账号和设备联调仍未执行；模拟 HTTP 测试覆盖 PROPFIND/REPORT/PUT/DELETE、冲突与重复实例。

## 待完成的外部接入

Apple 实际账户授权和线上网络联调仍需要部署环境。“极简课程表”专用导入器需要真实导出样本；通用客户端导入不代表已适配该厂商格式。
