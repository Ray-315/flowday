import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const developer = process.env.DEVELOPER_DIR || '/Applications/Xcode.app/Contents/Developer';
if (!existsSync(resolve(developer, 'usr/bin/xcodebuild'))) {
  console.error('找不到完整 Xcode，请安装 Xcode 或设置 DEVELOPER_DIR。');
  process.exit(1);
}
const result = spawnSync(resolve(root, 'node_modules/.bin/tauri'), ['ios', ...process.argv.slice(2)], {
  cwd: root,
  stdio: 'inherit',
  env: { ...process.env, CARGO_BUILD_JOBS: process.env.CARGO_BUILD_JOBS || '4', DEVELOPER_DIR: developer, PATH: `${developer}/usr/bin:${process.env.PATH || ''}` },
});
if(result.error) console.error(result.error.message);
process.exit(result.status ?? 1);
