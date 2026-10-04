import { test, expect } from '@playwright/test';

test('standalone authentication preserves Flutter field order, password visibility, code cooldown and local return', async ({page}) => {
  await page.route('**/api/v1/**', route => route.fulfill({status:200,json:{}}));
  await page.route('**/api/v1/auth/registration-code', route => route.fulfill({status:200,json:{retryAfterSeconds:60}}));
  await page.route('**/api/v1/auth/login', route => route.fulfill({status:401,json:{error:{code:'INVALID_CREDENTIALS',message:'邮箱或密码错误'}}}));
  await page.goto('/');
  await page.getByRole('button',{name:'账号与同步',exact:true}).click();
  await expect(page.getByRole('heading',{name:'欢迎回来',exact:true})).toBeVisible();
  await expect(page.locator('.sidebar')).toHaveCount(0);
  await page.getByLabel('邮箱地址',{exact:true}).fill('test@example.test');
  await page.getByLabel('密码',{exact:true}).fill('test-only-password');
  await page.getByRole('button',{name:'显示密码',exact:true}).click();
  await expect(page.getByLabel('密码',{exact:true})).toHaveAttribute('type','text');
  await page.getByRole('button',{name:'隐藏密码',exact:true}).click();
  await page.getByRole('button',{name:'登录',exact:true}).click();
  await expect(page.getByRole('alert')).toContainText('邮箱或密码不正确');
  await page.getByRole('button',{name:'没有账号？立即注册',exact:true}).click();
  await expect(page.getByRole('heading',{name:'创建账号',exact:true})).toBeVisible();
  expect(await page.locator('.auth-form label > span').allTextContents()).toEqual(['昵称','邮箱地址','密码','邮箱验证码']);
  await page.getByRole('button',{name:'发送验证码',exact:true}).click();
  await expect(page.getByRole('button',{name:/秒后重发/})).toBeDisabled();
  await page.getByLabel('邮箱验证码',{exact:true}).fill('123abc');
  await expect(page.getByLabel('邮箱验证码',{exact:true})).toHaveValue('123');
  await page.getByRole('button',{name:'已有账号？立即登录',exact:true}).click();
  await page.getByRole('button',{name:'没有账号？立即注册',exact:true}).click();
  await expect(page.getByLabel('邮箱验证码',{exact:true})).toHaveValue('');
  for(const width of [1440,390]) {
    await page.setViewportSize({width,height:900});
    expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
    await expect(page.getByRole('button',{name:'注册',exact:true})).toBeVisible();
  }
  await page.getByRole('button',{name:'继续本地使用',exact:true}).click();
  await expect(page.getByRole('button',{name:'新建任务',exact:true})).toBeVisible();
});

test('one settings page saves defaults used by new tasks and events and retains theme after reload',async({page})=>{
  await page.route('**/api/v1/**',route=>route.abort());
  await page.goto('/');
  await page.getByRole('button',{name:'设置',exact:true}).click();
  await expect(page.getByRole('button',{name:'偏好设置',exact:true})).toHaveCount(0);
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await page.getByRole('button',{name:'任务与项目',exact:true}).click();
  await page.getByRole('combobox', { name: '默认任务优先级' }).click();
  await page.getByRole('option', { name: '紧急', exact: true }).click();
  await page.getByRole('combobox', { name: '默认任务难度' }).click();
  await page.getByRole('option', { name: '困难', exact: true }).click();
  await page.getByRole('combobox', { name: '默认预计时长（分钟）' }).click();
  await page.getByRole('option', { name: '90', exact: true }).click();
  await page.getByRole('button',{name:'日程与提醒',exact:true}).click();
  await page.getByRole('combobox', { name: '默认日程时长（分钟）' }).click();
  await page.getByRole('option', { name: '90', exact: true }).click();
  await page.getByRole('button',{name:'界面与外观',exact:true}).click();
  await page.getByRole('button',{name:'深色',exact:true}).click();
  await page.getByRole('button',{name:'FlowDay 首页',exact:true}).click();
  await page.getByRole('button',{name:'新建任务',exact:true}).click();
  const dialog=page.getByRole('dialog');
  await expect(dialog.getByRole('button',{name:'紧急',exact:true})).toHaveAttribute('aria-pressed','true');
  await expect(dialog.getByLabel('预计耗时（分钟）')).toHaveValue('90');
  await page.keyboard.press('Escape');
  await page.getByRole('button',{name:'新建日程',exact:true}).click();
  const start=await dialog.getByLabel('开始时间').inputValue();
  const end=await dialog.getByLabel('结束时间').inputValue();
  expect(Date.parse(end)-Date.parse(start)).toBe(90*60_000);
  await page.keyboard.press('Escape');
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme','dark');
});

test('signed-in account actions keep protected forms and shared service controls',async({page})=>{
  const user={id:'ui-test',email:'test@example.test',displayName:'测试账号'};
  const workspace={schemaVersion:1,projects:[],tasks:[],events:[],nodes:[],edges:[],captures:[],notices:[],preferences:{}};
  let passwordRequests=0;
  await page.route('**/api/v1/**',route=>{
    const path=new URL(route.request().url()).pathname;
    if(path.endsWith('/auth/login'))return route.fulfill({json:{token:'test-only-session',user}});
    if(path.endsWith('/workspace'))return route.fulfill({json:{version:1,data:workspace}});
    if(path.endsWith('/auth/password')){passwordRequests++;return route.fulfill({json:{ok:true}});}
    return route.fulfill({json:{}});
  });
  await page.goto('/');
  await page.getByRole('button',{name:'账号与同步',exact:true}).click();
  await page.getByLabel('邮箱地址',{exact:true}).fill(user.email);
  await page.getByLabel('密码',{exact:true}).fill('test-only-password');
  await page.getByRole('button',{name:'登录',exact:true}).click();
  await expect(page.locator('.account-summary')).toContainText(user.displayName);
  await page.getByRole('button',{name:'密码',exact:true}).click();
  const dialog=page.getByRole('dialog',{name:'修改密码',exact:true});
  await dialog.getByLabel('当前密码',{exact:true}).fill('test-only-password');
  await dialog.getByLabel('新密码',{exact:true}).fill('new-test-only-password');
  await dialog.getByLabel('确认新密码',{exact:true}).fill('mismatch');
  await dialog.getByRole('button',{name:'修改密码',exact:true}).click();
  await expect(dialog.getByRole('alert')).toContainText('两次输入的新密码不一致');
  expect(passwordRequests).toBe(0);
  await dialog.getByLabel('确认新密码',{exact:true}).fill('new-test-only-password');
  await dialog.getByRole('button',{name:'修改密码',exact:true}).click();
  await expect(dialog).toHaveCount(0);
  expect(passwordRequests).toBe(1);
  await page.getByRole('button',{name:'智能安排与服务',exact:true}).click();
  await expect(page.getByLabel('自然语言',{exact:true})).toBeVisible();
  const service=await page.getByLabel('自然语言',{exact:true}).evaluate(element=>{const style=getComputedStyle(element);return {font:style.fontFamily,size:style.fontSize,radius:style.borderRadius,background:style.backgroundColor};});
  await page.getByRole('button',{name:'FlowDay 首页',exact:true}).click();
  await page.getByRole('button',{name:'新建任务',exact:true}).click();
  const editor=await page.getByRole('dialog').getByLabel('任务名称',{exact:true}).evaluate(element=>{const style=getComputedStyle(element);return {font:style.fontFamily,size:style.fontSize,radius:style.borderRadius,background:style.backgroundColor};});
  expect(service).toEqual(editor);
});
