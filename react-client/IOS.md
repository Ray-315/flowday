# iPhone 开发与预览

iPhone 与 Mac 共用 React/Tauri 代码。手机使用底部「今天 / 日历 / 任务 / AI 助手 / 更多」导航，辅助功能集中到更多；设置分类使用选择器。日历首次打开默认列表，已有的日历视图偏好继续保留。表单支持安全区域、较大的触控目标和键盘输入。

iOS 登录令牌保存在应用沙盒内的独立会话目录，不进入工作区备份；文件权限 0600、目录 0700，不访问钥匙串。前台云同步使用同一账号；后台持续同步、推送和灵动岛尚未实现。

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
