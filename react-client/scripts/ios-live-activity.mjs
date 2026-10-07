import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import YAML from 'yaml';

// Generated Xcode files are ignored; reapply the extension from versioned sources.
export function configureLiveActivity(root, env) {
  const directory = resolve(root, 'src-tauri/gen/apple');
  const path = resolve(directory, 'project.yml');
  if (!existsSync(path)) throw new Error('请先运行 npm run ios:init');
  const project = YAML.parse(readFileSync(path, 'utf8'));
  const target = project.targets['flowday-react_iOS'];
  // Keep deployment versions as strings: YAML numbers make XcodeGen drop 15.0.
  project.options.deploymentTarget.iOS = '15.0';
  target.deploymentTarget = '15.0';
  target.info.properties.NSSupportsLiveActivities = true;
  target.info.properties.NSCalendarsUsageDescription = '允许 FlowDay 与你选择的苹果日历双向同步日程。';
  target.info.properties.NSCalendarsFullAccessUsageDescription = '允许 FlowDay 读取、创建和更新你选择的苹果日历日程。';
  for (const source of target.sources) {
    if (source.path === 'Externals') source.excludes = [...new Set([...(source.excludes || []), '**/*.a'])];
  }
  target.dependencies = target.dependencies.filter(item => item.target !== 'FlowDayActivity');
  target.dependencies.push({ target: 'FlowDayActivity', embed: true });
  const identifier = project.settingGroups.app.base.PRODUCT_BUNDLE_IDENTIFIER;
  project.targets.FlowDayActivity = {
    type: 'app-extension', platform: 'iOS', deploymentTarget: '16.2',
    sources: [
      { path: resolve(root, 'ios/FlowDayActivity') },
      { path: resolve(root, 'src-tauri/plugins/live-activity/ios/Sources/FlowActivityAttributes.swift') },
    ],
    info: { path: 'FlowDayActivity-Info.plist', properties: {
      CFBundleDisplayName: 'FlowDay 专注',
      CFBundleShortVersionString: target.info.properties.CFBundleShortVersionString,
      CFBundleVersion: target.info.properties.CFBundleVersion,
      NSExtension: { NSExtensionPointIdentifier: 'com.apple.widgetkit-extension' },
    } },
    settings: { base: {
      PRODUCT_BUNDLE_IDENTIFIER: `${identifier}.LiveActivity`,
      SWIFT_VERSION: '5.0',
      SKIP_INSTALL: true, APPLICATION_EXTENSION_API_ONLY: true,
      TARGETED_DEVICE_FAMILY: '1,2',
      ...(target.settings.base.DEVELOPMENT_TEAM ? { DEVELOPMENT_TEAM: target.settings.base.DEVELOPMENT_TEAM } : {}),
      ...(env.APPLE_DEVELOPMENT_TEAM ? { DEVELOPMENT_TEAM: env.APPLE_DEVELOPMENT_TEAM } : {}),
    } },
  };
  writeFileSync(path, YAML.stringify(project));
  const result = spawnSync('xcodegen', ['generate', '--spec', path], { cwd: directory, env, stdio: 'inherit' });
  if (result.status !== 0) throw new Error('生成实时活动扩展工程失败');
}
