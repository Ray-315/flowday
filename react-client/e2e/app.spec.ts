import { test, expect } from '@playwright/test';

test('create, complete, reopen, edit and persist a task', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: '新建任务', exact: true }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('任务名称', { exact: true }).fill('迁移交互测试');
  await dialog.getByRole('button', { name: '保存', exact: true }).click();
  await expect(dialog).toHaveCount(0);
  await expect(page.getByRole('button', { name: '编辑任务：迁移交互测试' })).toBeVisible();
  await page.getByRole('checkbox', { name: '完成任务：迁移交互测试' }).click();
  await expect(page.getByRole('button', { name: '编辑任务：迁移交互测试' })).toHaveCount(0);
  await page.getByRole('button', { name: '已完成', exact: true }).click();
  await expect(page.getByRole('checkbox', { name: '完成任务：迁移交互测试' })).toBeChecked();
  await page.getByRole('checkbox', { name: '完成任务：迁移交互测试' }).click();
  await page.getByRole('button', { name: '全部', exact: true }).click();
  await page.getByRole('button', { name: '编辑任务：迁移交互测试' }).click();
  await dialog.getByLabel('任务名称', { exact: true }).fill('修改后的任务');
  await dialog.getByRole('button', { name: '保存', exact: true }).click();
  await page.reload();
  await expect(page.getByRole('button', { name: '编辑任务：修改后的任务' })).toBeVisible();
});

test('event validation, date navigation and keyboard dismissal', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: '新建日程', exact: true }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('日程名称').fill('讨论会');
  await dialog.getByLabel('开始时间').fill('2026-10-03T10:00');
  await dialog.getByLabel('结束时间').fill('2026-10-03T09:00');
  await dialog.getByRole('button', { name: '保存', exact: true }).click();
  await expect(dialog.getByRole('alert')).toContainText('结束时间必须晚于开始时间');
  await dialog.getByLabel('结束时间').fill('2026-10-03T11:00');
  await dialog.getByRole('button', { name: '保存', exact: true }).click();
  await page.getByRole('button', { name: '新建任务', exact: true }).click();
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  await expect(page.getByRole('button', { name: '新建任务', exact: true })).toBeFocused();
});

test('narrow window fits and navigation remains usable', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/?preview=1');
  await expect(page.getByRole('heading', { name: '任务', exact: true })).toBeVisible();
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
  expect(overflow).toBe(false);
  await page.getByRole('button', { name: '日历', exact: true }).click();
  await expect(page.getByRole('heading', { name: '日历', exact: true })).toBeVisible();
  await page.getByRole('button', { name: '任务', exact: true }).click();
  await expect(page.getByRole('button', { name: '编辑任务：阅读三篇相关论文' })).toBeVisible();
});

test('light, dark and mobile screenshots; no runtime errors', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.setViewportSize({ width: 1440, height: 960 });
  await page.goto('/?preview=1');
  await page.waitForTimeout(600);
  await page.screenshot({ path: 'artifacts/today-light.png', fullPage: true });
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await page.getByRole('button', { name: '界面与外观', exact: true }).click();
  await page.getByRole('button', { name: '深色', exact: true }).click();
  await page.getByRole('button', { name: 'FlowDay 首页', exact: true }).click();
  await page.waitForTimeout(350);
  await page.screenshot({ path: 'artifacts/today-dark.png', fullPage: true });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: 'artifacts/today-mobile.png', fullPage: true });
  expect(errors).toEqual([]);
});

test('backup import preserves workflow data and export is usable', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await page.getByRole('button', { name: '数据与隐私', exact: true }).click();
  const original = {
    schemaVersion: 1,
    projects: [{id:'p',title:'导入项目',color:0xff2680ff}],
    events: [],
    edges: [],
    captures: [],
    notices: [],
    preferences: {},
    tasks: [
      {
        id: 'imported',
        title: '导入任务',
        status: 'todo',
        priority: 'normal',
        estimateMinutes: 60,
        tags: ['保留标签'],
      },
    ],
    nodes: [{ id: 'node', title: '保留工作流', kind: 'task', status: 'ready', projectId: 'p', x:0, y:0 }],
  };
  await page.locator('input[type=file]').setInputFiles({
    name: 'backup.json',
    mimeType: 'application/json',
    buffer: Buffer.from(JSON.stringify(original)),
  });
  await page.getByRole('button', { name: '确认导入', exact: true }).click();
  await expect(page.getByRole('button', { name: '编辑任务：导入任务' })).toBeVisible();
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await page.getByRole('button', { name: '数据与隐私', exact: true }).click();
  const download = page.waitForEvent('download');
  await page.getByRole('button', { name: '导出备份', exact: true }).click();
  const result = await download;
  expect(result.suggestedFilename()).toMatch(/flowday.*\.json/);
  const preserved = await page.evaluate(() =>
    JSON.parse(localStorage.getItem('flowday.react-trial.workspace.v1')!),
  );
  expect(preserved.nodes).toEqual(original.nodes);
  expect(preserved.tasks[0].tags).toEqual(['保留标签']);
});

test('invalid import does not replace current data and deletion requires confirmation', async ({ page }) => {
  await page.goto('/?preview=1');
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await page.getByRole('button', { name: '数据与隐私', exact: true }).click();
  await page.locator('input[type=file]').setInputFiles({
    name: 'invalid.json',
    mimeType: 'application/json',
    buffer: Buffer.from('{"schemaVersion":99}'),
  });
  await expect(page.getByRole('alert')).toContainText('不支持的备份版本');
  await page.getByRole('button', { name: 'FlowDay 首页', exact: true }).click();
  await page.getByRole('button', { name: '编辑任务：阅读三篇相关论文' }).click();
  await page.getByRole('button', { name: '删除任务', exact: true }).click();
  await page.getByRole('button', { name: '确认删除', exact: true }).click();
  await expect(page.getByRole('button', { name: '编辑任务：阅读三篇相关论文' })).toHaveCount(0);
  await page.reload();
  await expect(page.getByRole('button', { name: '编辑任务：阅读三篇相关论文' })).toBeVisible();
});

test('尺寸与深色层次：窄屏保持字号，背景比前景更黑且卡片无描边', async ({ page }) => {
  await page.setViewportSize({ width: 418, height: 675 });
  await page.goto('/?preview=1');
  const typography = await page.evaluate(() => ({
    title: parseFloat(getComputedStyle(document.querySelector('.task-title')!).fontSize),
    meta: parseFloat(getComputedStyle(document.querySelector('.task-meta')!).fontSize),
    day: parseFloat(getComputedStyle(document.querySelector('.month-grid button')!).fontSize),
  }));
  expect(typography.title).toBeGreaterThanOrEqual(14);
  expect(typography.meta).toBeGreaterThanOrEqual(12);
  expect(typography.day).toBeGreaterThanOrEqual(12);
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await page.getByRole('button', { name: '界面与外观', exact: true }).click();
  await page.getByRole('button', { name: '深色', exact: true }).click();
  await page.getByRole('button', { name: 'FlowDay 首页', exact: true }).click();
  await page.getByRole('button', { name: '新建任务', exact: true }).click();
  const layers = await page.evaluate(() => {
    const color = (selector: string) => getComputedStyle(document.querySelector(selector)!).backgroundColor;
    const brightness = (value: string) => {
      const [red, green, blue] = value.match(/[\d.]+/g)!.map(Number);
      return red * 0.2126 + green * 0.7152 + blue * 0.0722;
    };
    return {
      background: brightness(getComputedStyle(document.documentElement).backgroundColor),
      sidebar: brightness(color('.sidebar')),
      panel: brightness(color('.panel')),
      dialog: brightness(color('.editor-dialog')),
      border: getComputedStyle(document.querySelector('.panel')!).borderTopColor,
    };
  });
  expect(layers.background).toBeLessThan(layers.sidebar);
  expect(layers.sidebar).toBeLessThan(layers.panel);
  expect(layers.panel).toBeLessThan(layers.dialog);
  expect(layers.border).toBe('rgba(0, 0, 0, 0)');
});

test('不同窗口宽度只改变排布，不缩小正文与辅助文字', async ({ page }) => {
  await page.goto('/?preview=1');
  for (const width of [390, 418, 768, 1024, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    const metrics = await page.evaluate(() => ({
      title: parseFloat(getComputedStyle(document.querySelector('.task-title')!).fontSize),
      meta: parseFloat(getComputedStyle(document.querySelector('.task-meta')!).fontSize),
      panelOverflow: Array.from(document.querySelectorAll('.panel')).some(
        (panel) => panel.scrollWidth > panel.clientWidth + 1,
      ),
    }));
    expect(metrics.title, `width=${width}`).toBe(14);
    expect(metrics.meta, `width=${width}`).toBe(12);
    expect(metrics.panelOverflow, `width=${width}`).toBe(false);
  }
});
