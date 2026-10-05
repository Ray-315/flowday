# iPhone 开发与预览

iPhone 与 Mac 共用 React/Tauri 代码。手机使用底部「今天 / 日历 / 任务 / AI 助手 / 更多」导航，辅助功能集中到更多；设置分类使用选择器。日历首次打开默认列表，已有的日历视图偏好继续保留。表单支持安全区域、较大的触控目标和键盘输入。

iOS 登录令牌保存在应用沙盒内的独立会话目录，不进入工作区备份；文件权限 0600、目录 0700，不访问钥匙串。前台云同步使用同一账号；后台持续同步和远程推送尚未实现；原生实时活动支持专注倒计时和进行中的日程。

## 环境

完整 Xcode（含 iOS Simulator）、Rust、Node、CocoaPods。可参照 [Tauri iOS 环境要求](https://v2.tauri.app/start/prerequisites/#ios)。

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
brew install cocoapods
npm install
npm run ios:init -- --ci
```

脚本默认使用 `/Applications/Xcode.app/Contents/Developer`，可通过 `DEVELOPER_DIR` 指定其他 Xcode；不修改全局 `xcode-select`。生成的 Xcode 工程位于 `src-tauri/gen/apple`，不提交生成物，重新运行初始化即可生成。

## 模拟器

```sh
npm run ios:build -- --target aarch64-sim --debug --no-sign --ci
```

构建产物位于 `src-tauri/gen/apple/build`。模拟器 `.app` 不能直接安装到实体 iPhone。

开发热更新使用 `npm run ios:dev`；Vite 读取 Tauri 提供的 `TAURI_DEV_HOST`，默认桌面预览仍只监听 127.0.0.1。

## 真机

在 Xcode 中打开生成工程，选择自己的 Apple 开发团队、连接 iPhone 后运行；或配置 `APPLE_DEVELOPMENT_TEAM` 再执行 `npm run ios:dev`。发布 TestFlight/App Store 还需相应签名与发行配置，本仓库不包含证书或账号信息。

手机与 Mac 使用同一个 FlowDay 账号即可访问云端数据。iCloud 入口仍只同步日历，不代表整个工作区使用 iCloud。

## 灵动岛与锁屏实时活动

iOS 16.2 及以上在「今天」页显示「灵动岛与锁屏」区域。手动输入专注事项与 1–480 分钟，或选择正在进行、未完成且剩余时间不超过 8 小时的日程，点击「开启实时活动」。支持一项活动；点按灵动岛返回 App，在「今天」页结束活动。没有灵动岛的机型使用锁屏卡片。系统关闭实时活动权限时会提示到设置开启。

使用 ActivityKit + WidgetKit 原生扩展。紧凑、最小、展开和锁屏布局都已实现。倒计时由系统渲染，不依赖网页计时器持续运行。前台会同步关联日程的标题和结束时间，完成或删除日程会结束活动；切换账号时会清理其他工作区的活动。手动专注不创建日程或任务。

目前没有 APNs 远程更新、后台自动启动下一日程、提醒声音或专注完成记录。到时后显示结束状态，返回 App 后清除；系统也允许在锁屏移除。离线或后台不会接收其他设备修改的日程。

`npm run ios:init` / `ios:build` / `ios:dev` 会用 `scripts/ios-live-activity.mjs` 将版本管理中的 Swift 扩展重新加入生成的 Xcode 工程。需要 `xcodegen`。请使用这些脚本构建；直接重新运行裸 Tauri init 可能丢失扩展配置。App target 与 `FlowDayActivity` extension 必须使用同一开发团队，真机签名可设置 `APPLE_DEVELOPMENT_TEAM` 或在 Xcode 中分别选择团队。扩展 Bundle ID 为主 App ID 加 `.LiveActivity`。不需要为本地倒计时配置推送证书。

## 苹果日历导入与导出（Mac / iPhone）

日历页的「苹果日历」入口提供「导入」「导出」两个独立操作。通过系统 EventKit 授权，直接访问设备已配置的日历，无需在 FlowDay 输入 Apple ID。导入可选择只读日历，导出仅允许可写日历。

支持标题、起止时间、全天状态、地点与备注；默认范围为近 30 天到未来一年，可在「日期范围与选项」中调整（最多 400 天、2000 条）。保存本设备的关联关系，重复操作不会重复创建已关联日程。双方同时修改时需要选择版本并再次执行。不会自动传播删除；苹果重复事件按各次导入，FlowDay 重复规则暂不导出。导入结果遵循已有 FlowDay 云同步设置。

这是手动触发的双向传输，不是后台持续同步。对同一苹果日历建议只使用一种连接方式，避免与旧版服务器 CalDAV 导入重复。
