import { test, expect, type Page } from '@playwright/test';

const key = 'flowday.react-trial.workspace.v1';
const receiptKey = `${key}.reminder-receipts`;
const today = (() => {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
})();
function workspace() {
  return {
    schemaVersion: 1,
    projects: [
      {
        id: 'project',
        title: '回归项目',
        color: 0xff4b70e8,
        parentId: null,
        description: '',
        archived: false,
        attachments: [],
      },
    ],
    tasks: [
      {
        id: 'task',
        title: '回归任务',
        status: 'todo',
        priority: 'normal',
        difficulty: 'normal',
        projectId: 'project',
        parentId: null,
        description: '',
        tags: [],
        estimateMinutes: 60,
        actualMinutes: 0,
        splittable: true,
        archived: false,
        attachments: [],
      },
    ],
    events: [
      {
        id: 'event',
        title: '回归时间块',
        start: `${today}T09:00:00+08:00`,
        end: `${today}T10:00:00+08:00`,
        color: 0xff4b70e8,
        projectId: 'project',
        taskId: 'task',
        location: '',
        notes: '',
        tags: [],
        completed: false,
        locked: false,
        allDay: false,
        actualMinutes: 0,
        attachments: [],
      },
    ],
    nodes: [] as Record<string, unknown>[],
    edges: [] as Record<string, unknown>[],
    captures: [],
    notices: [] as Record<string, unknown>[],
    preferences: {
      timezone: 'Asia/Shanghai',
      reduceMotion: true,
      nativeNotifications: false,
      calendarView: '日',
    },
  };
}
async function seed(page: Page, data = workspace(), receipts: Record<string, unknown> = {}) {
  // Development-only local fixtures; no account or production request is needed.
  await page.route('**/api/v1/**', (route) => route.abort());
  await page.addInitScript(
    ({ data, key, receiptKey, receipts }) => {
      if (!localStorage.getItem(key)) {
        localStorage.setItem(key, JSON.stringify(data));
        localStorage.setItem(receiptKey, JSON.stringify(receipts));
      }
    },
    { data, key, receiptKey, receipts },
  );
  await page.goto('/');
  await expect(page.getByLabel('快速输入', { exact: true })).toBeVisible();
}
const persisted = (page: Page) => page.evaluate((key) => JSON.parse(localStorage.getItem(key)!), key);
async function menu(page: Page, name: string) {
  await page.getByRole('button', { name, exact: true }).click();
}

test('major features have visible navigation and full pages on desktop and narrow windows', async ({ page }) => {
  await seed(page);
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 960 });
    for (const name of ['报告', '通知', '智能安排与服务', '项目管理', '设置', '本地备份']) {
      const entry = page.getByRole('button', { name, exact: true });
      await expect(entry).toBeVisible();
      await entry.click();
      await expect(page.locator('.page-header h1')).toContainText(name==='本地备份'?'设置':name);
      await expect(page.getByRole('dialog')).toHaveCount(0);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    }
    await expect(page.getByRole('button', {name:'偏好设置',exact:true})).toHaveCount(0);
    await page.getByRole('button', {name:'账号与同步',exact:true}).first().click();
    await expect(page.getByRole('heading', {name:'欢迎回来',exact:true})).toBeVisible();
    await expect(page.locator('.sidebar')).toHaveCount(0);
    await page.getByRole('button', {name:'继续本地使用',exact:true}).click();
    await page.getByRole('button', { name: '日历', exact: true }).click();
    await expect(page.getByRole('button', { name: '课程导入', exact: true })).toBeVisible();
    await expect(page.locator('.header-menu')).toHaveCount(0);
  }
});

test('Today module order and visibility persist, and captures convert exactly once', async ({ page }) => {
  await seed(page);
  await menu(page, '定制今天');
  const customization = page.getByRole('dialog', { name: '自定义 Today' });
  await customization.getByLabel('本周压力', { exact: true }).check();
  await customization.getByRole('button', { name: '上移今日任务', exact: true }).click();
  await customization.getByRole('button', { name: '保存', exact: true }).click();
  await expect(page.getByRole('heading', { name: '本周压力', exact: true })).toBeVisible();
  expect((await persisted(page)).preferences.todayModuleOrder.slice(0, 3)).toEqual([
    'capture',
    'todo',
    'timeline',
  ]);
  await page.reload();
  await expect(page.getByRole('heading', { name: '本周压力', exact: true })).toBeVisible();
  await expect(page.locator('.today-module').nth(1).getByRole('heading', { name: '任务' })).toBeVisible();
  await page.getByLabel('快速输入', { exact: true }).fill('浏览器记录转任务');
  await page.getByRole('button', { name: '保存快速输入', exact: true }).click();
  await expect(page.getByRole('heading', { name: '智能安排与服务.' })).toBeVisible();
  await page.getByRole('button', { name: '今天', exact: true }).first().click();
  await page.locator('.today-captures summary').click();
  await page.getByRole('button', { name: '转为任务', exact: true }).click();
  const editor = page.getByRole('dialog', { name: '编辑任务' });
  await expect(editor.getByLabel('任务名称', { exact: true })).toHaveValue('浏览器记录转任务');
  await editor.getByRole('button', { name: '保存', exact: true }).click();
  await page.reload();
  const data = await persisted(page);
  expect(data.captures).toMatchObject([{ text: '浏览器记录转任务', processed: true }]);
  expect(data.tasks.filter((task: { title: string }) => task.title === '浏览器记录转任务')).toHaveLength(1);
});

test('advanced task fields survive persistence and batch archive/trash/restore', async ({ page }) => {
  await seed(page);
  await page.getByRole('button', { name: '编辑任务：回归任务', exact: true }).click();
  const dialog = page.getByRole('dialog', { name: '编辑任务' });
  await dialog.locator('summary').filter({ hasText: '更多设置' }).click();
  await dialog.getByLabel('描述', { exact: true }).fill('保留高级字段');
  await dialog.getByLabel(/^状态/).selectOption('doing');
  await dialog.getByLabel(/^难度/).selectOption('high');
  await dialog.getByLabel('预计耗时（分钟）', { exact: true }).fill('90');
  await dialog.getByLabel('实际耗时（分钟）', { exact: true }).fill('35');
  await dialog.getByLabel('计划开始', { exact: true }).fill('2050-10-05T09:00');
  await dialog.getByLabel('标签', { exact: true }).fill('回归,高级');
  await dialog.getByLabel('允许拆分', { exact: true }).uncheck();
  await dialog.getByRole('button', { name: '保存', exact: true }).click();
  await page.getByRole('button', { name: '任务', exact: true }).click();
  await page.getByRole('checkbox', { name: '选择任务：回归任务', exact: true }).check();
  await page.locator('.batch-actions').getByRole('button', { name: '归档', exact: true }).click();
  await page.getByRole('button', { name: '归档', exact: true }).click();
  await page.getByRole('checkbox', { name: '选择任务：回归任务', exact: true }).check();
  await page.locator('.batch-actions').getByRole('button', { name: '取消归档', exact: true }).click();
  await page.getByRole('button', { name: '全部', exact: true }).click();
  await page.getByRole('checkbox', { name: '选择任务：回归任务', exact: true }).check();
  await page.locator('.batch-actions').getByRole('button', { name: '删除', exact: true }).click();
  await page.getByRole('button', { name: '回收站', exact: true }).click();
  await page.getByRole('checkbox', { name: '选择任务：回归任务', exact: true }).check();
  await page.locator('.batch-actions').getByRole('button', { name: '恢复', exact: true }).click();
  await page.reload();
  expect((await persisted(page)).tasks[0]).toMatchObject({
    status: 'doing',
    difficulty: 'high',
    estimateMinutes: 90,
    actualMinutes: 35,
    description: '保留高级字段',
    tags: ['回归', '高级'],
    splittable: false,
    archived: false,
    deletedAt: null,
    plannedStart: '2050-10-05T01:00:00.000Z',
  });
});

test('calendar week/month/list navigation and keyboard resize persist without changing linkage', async ({
  page,
}) => {
  await seed(page);
  await page.getByRole('button', { name: '日历', exact: true }).click();
  const panel = page.locator('.calendar-full');
  await panel.getByRole('slider', { name: '调整 回归时间块 结束时间' }).press('ArrowDown');
  await panel.getByRole('button', { name: '周', exact: true }).click();
  await expect(panel.locator('.calendar-range-week .calendar-range-day')).toHaveCount(7);
  await panel.getByRole('button', { name: '下一周', exact: true }).click();
  await panel.getByRole('button', { name: '月', exact: true }).click();
  await expect(panel.locator('.calendar-range-month .calendar-range-day')).toHaveCount(42);
  await panel.getByRole('button', { name: '下个月', exact: true }).click();
  await panel.getByRole('button', { name: '列表', exact: true }).click();
  await expect(panel.locator('.calendar-range-list .calendar-range-day')).toHaveCount(0);
  await page.reload();
  const event = (await persisted(page)).events[0];
  expect(Date.parse(event.end) - Date.parse(event.start)).toBe(75 * 60000);
  expect(event.taskId).toBe('task');
  expect(event.projectId).toBe('project');
});

test('project archive and recycle-bin restoration retain project tasks', async ({ page }) => {
  await seed(page);
  await menu(page, '项目管理');
  const dialog = page.locator('.workspace-page');
  await dialog.locator('article').getByRole('button', { name: '归档', exact: true }).click();
  await dialog.locator('.choice-group').getByRole('button', { name: '归档', exact: true }).click();
  await dialog.getByRole('button', { name: '取消归档', exact: true }).click();
  await dialog.locator('.choice-group').getByRole('button', { name: '项目', exact: true }).click();
  page.once('dialog', (confirmation) => confirmation.accept());
  await dialog.getByRole('button', { name: '删除', exact: true }).click();
  await dialog.locator('.choice-group').getByRole('button', { name: '回收站', exact: true }).click();
  await dialog.getByRole('button', { name: '恢复', exact: true }).click();
  await page.keyboard.press('Escape');
  await page.reload();
  const data = await persisted(page);
  expect(data.projects[0]).toMatchObject({ archived: false, deletedAt: null });
  expect(data.tasks[0].projectId).toBe('project');
  await expect(page.getByRole('button', { name: '编辑任务：回归任务', exact: true })).toBeVisible();
});

test('workflow task-node creation and condition branch selection survive reload', async ({ page }) => {
  const data = workspace();
  data.nodes = [
    {
      id: 'condition',
      projectId: 'project',
      title: '分支判断',
      kind: 'condition',
      status: 'ready',
      x: 30,
      y: 300,
      anyPredecessor: false,
    },
    {
      id: 'yes-node',
      projectId: 'project',
      title: '选中分支',
      kind: 'note',
      status: 'locked',
      x: 310,
      y: 300,
      anyPredecessor: false,
    },
    {
      id: 'no-node',
      projectId: 'project',
      title: '未选分支',
      kind: 'note',
      status: 'locked',
      x: 310,
      y: 460,
      anyPredecessor: false,
    },
  ];
  data.edges = [
    {
      id: 'yes',
      projectId: 'project',
      sourceId: 'condition',
      targetId: 'yes-node',
      label: '通过',
      active: true,
      delayMinutes: 0,
    },
    {
      id: 'no',
      projectId: 'project',
      sourceId: 'condition',
      targetId: 'no-node',
      label: '不通过',
      active: true,
      delayMinutes: 0,
    },
  ];
  await seed(page, data);
  await page.getByRole('button', { name: '工作流', exact: true }).click();
  await page.locator('.workflow-toolbar').getByRole('button', { name: '节点', exact: true }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByLabel('节点名称', { exact: true }).fill('浏览器新增节点');
  await dialog.getByLabel('节点类型', { exact: true }).selectOption('task');
  await dialog.getByRole('button', { name: '保存', exact: true }).click();
  await expect(page.locator('.workflow-node').filter({ hasText: '浏览器新增节点' })).toBeVisible();
  await page.getByRole('button', { name: '分支判断', exact: true }).click();
  await page.getByLabel('条件出口', { exact: true }).selectOption('yes');
  await page.reload();
  const saved = await persisted(page);
  expect(saved.nodes.find((node: { id: string }) => node.id === 'condition')).toMatchObject({
    selectedBranchEdgeId: 'yes',
    status: 'done',
  });
  const created = saved.nodes.find((node: { title: string }) => node.title === '浏览器新增节点');
  expect(created.taskId).toBeTruthy();
  expect(saved.tasks.find((task: { id: string }) => task.id === created.taskId).title).toBe('浏览器新增节点');
});

test('notice snooze and acknowledgement update persisted reminder receipts and linked task actions', async ({
  page,
}) => {
  const data = workspace();
  data.events = [];
  data.notices = [
    {
      id: 'notice',
      title: '持久提醒',
      body: '回归动作',
      createdAt: new Date().toISOString(),
      taskId: 'task',
      type: 'reminder',
      read: false,
      acknowledged: false,
    },
  ];
  await seed(page, data, {
    reminder: {
      sentCount: 1,
      lastSent: new Date().toISOString(),
      noticeId: 'notice',
      noticeIds: ['notice'],
      acknowledged: false,
    },
  });
  await menu(page, '通知');
  const dialog = page.locator('.workspace-page');
  await dialog.getByLabel('稍后提醒（分钟）').fill('15');
  await dialog.getByRole('button', { name: '稍后提醒', exact: true }).click();
  const snoozed = await page.evaluate((key) => JSON.parse(localStorage.getItem(key)!), receiptKey);
  expect(Date.parse(snoozed.reminder.snoozedUntil)).toBeGreaterThan(Date.now() + 14 * 60000);
  await dialog.getByRole('button', { name: '开始', exact: true }).click();
  expect((await persisted(page)).tasks[0].status).toBe('doing');
  await dialog.getByRole('button', { name: '知晓', exact: true }).click();
  await expect(dialog.getByRole('button', { name: '已知晓', exact: true })).toBeDisabled();
  const acknowledged = await page.evaluate((key) => JSON.parse(localStorage.getItem(key)!), receiptKey);
  expect(acknowledged.reminder.acknowledged).toBe(true);
  expect(acknowledged.reminder.snoozedUntil).toBeUndefined();
  await dialog.getByRole('button', { name: '完成', exact: true }).click();
  await page.reload();
  expect((await persisted(page)).tasks[0].status).toBe('done');
  expect((await persisted(page)).notices[0]).toMatchObject({ read: true, acknowledged: true });
});
test('calendar display preferences persist and Sunday-first mobile week stays within the window', async ({
  page,
}) => {
  const data = workspace();
  Object.assign(data.preferences, { weekStartsMonday: false, overlapStyle: '并排' });
  data.events.push({
    ...data.events[0],
    id: 'overlap',
    title: '第二个时间块',
    taskId: 'task',
    start: `${today}T09:30:00+08:00`,
    end: `${today}T10:30:00+08:00`,
  });
  await seed(page, data);
  await page.getByRole('button', { name: '日历', exact: true }).click();
  const calendar = page.locator('.calendar-full');
  await calendar.getByLabel('重叠样式').selectOption('层叠');
  const stacked = await calendar
    .locator('.event-block')
    .evaluateAll((blocks) => blocks.map((block) => (block as HTMLElement).style.left));
  expect(stacked[0]).not.toBe(stacked[1]);
  await calendar.getByLabel('重叠样式').selectOption('聚合');
  await expect(calendar.locator('.event-block')).toHaveCount(1);
  await calendar.getByRole('button', { name: '查看 2 个重叠日程' }).click();
  await expect(
    page.getByRole('dialog', { name: '重叠日程' }).getByRole('button', { name: /第二个时间块/ }),
  ).toBeVisible();
  await page.keyboard.press('Escape');
  await calendar.getByRole('button', { name: '周', exact: true }).click();
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(calendar.locator('.calendar-range-week .calendar-range-day')).toHaveCount(7);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await expect(calendar.locator('.calendar-range-day > .date-button').first()).toContainText('周日');
  await page.reload();
  await expect(page.locator('.schedule-panel .timeline').first()).toBeVisible();
  await page.getByRole('button', { name: '日历', exact: true }).click();
  await expect(
    page.locator('.calendar-full').getByRole('button', { name: '周', exact: true }),
  ).toHaveAttribute('aria-pressed', 'true');
  await page.locator('.calendar-full').getByRole('button', { name: '时间轴', exact: true }).click();
  await expect(page.locator('.calendar-range-timeline .calendar-range-event')).toHaveCount(2);
  const saved = await persisted(page);
  expect(saved.preferences).toMatchObject({
    calendarView: '时间轴',
    overlapStyle: '聚合',
    weekStartsMonday: false,
  });
});
