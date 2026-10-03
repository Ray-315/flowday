import { chromium } from '@playwright/test';
import { spawn } from 'node:child_process';
import { mkdir, mkdtemp, readFile, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';

const executable = fileURLToPath(new URL('../src-tauri/target/release/flowday-react.exe', import.meta.url));
const port = 9237;
const testDirectory = await mkdtemp(join(tmpdir(), 'flowday-native-'));
const server=createServer((request,response)=>{
  if(request.url==='/api/v1/redirect'){response.writeHead(307,{Location:'/api/v1/probe'});response.end();return;}
  if(request.url==='/api/v1/download'){response.writeHead(200,{'Content-Type':'application/octet-stream'});response.end(Buffer.from([0,1,127,255]));return;}
  let body='';request.on('data',chunk=>body+=chunk);request.on('end',()=>{response.writeHead(200,{'Content-Type':'application/json'});response.end(JSON.stringify({method:request.method,authorized:request.headers.authorization==='Bearer test-only',value:JSON.parse(body||'{}').value}));});
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const localServer=`http://127.0.0.1:${server.address().port}`;
const app = spawn(executable, [], {
  windowsHide: true,
  env: { ...process.env, FLOWDAY_TEST_DATA_DIR: testDirectory, WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS: `--remote-debugging-port=${port}` },
  stdio: 'ignore',
});
let browser;
let page;
let previous;
const key = 'flowday.react-trial.workspace.v1';
try {
  for (let attempt = 0; attempt < 60; attempt++) {
    if (app.exitCode !== null) throw new Error(`Native app exited: ${app.exitCode}`);
    try {
      browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`);
      break;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
  }
  if (!browser) throw new Error('WebView2 did not start');
  page = browser.contexts()[0].pages()[0];
  await page.waitForLoadState('domcontentloaded');
  await page.getByRole('button', { name: '新建任务', exact: true }).waitFor();
  const native = await page.evaluate(() => Boolean(window.__TAURI_INTERNALS__));
  if (!native) throw new Error('Application is not running in Tauri');
  const probes=await page.evaluate(async baseUrl=>{
    const invoke=window.__TAURI_INTERNALS__.invoke;
    const response=await invoke('http_request',{baseUrl,path:'/probe',method:'POST',token:'test-only',body:JSON.stringify({value:'native-transport'})});
    const redirect=await invoke('http_request',{baseUrl,path:'/redirect',method:'GET',token:null,body:null});
    const bytes=await invoke('http_download',{baseUrl,path:'/download',token:'test-only'});
    const empty={schemaVersion:1,tasks:[],events:[],projects:[],nodes:[],edges:[],notices:[],captures:[],preferences:{}};
    const baseline=JSON.stringify({version:7,json:JSON.stringify(empty)});
    await invoke('sync_baseline_write',{scope:'native-test',source:baseline});
    const stored=await invoke('sync_baseline_read',{scope:'native-test'});
    await invoke('workspace_write',{scope:'backup-probe',source:JSON.stringify(empty)});
    await invoke('workspace_write',{scope:'backup-probe',source:JSON.stringify({...empty,preferences:{themeMode:'dark'}})});
    await invoke('workspace_backup',{scope:'backup-probe'});
    const backups=await invoke('workspace_backups',{scope:'backup-probe'});
    const previous=JSON.parse(await invoke('workspace_backup_read',{scope:'backup-probe',id:'previous.json'}));
    const backupValid=backups.some(item=>item.id.startsWith('daily-'))&&backups.some(item=>item.id.startsWith('manual-'))&&Object.keys(previous.preferences).length===0;
    return {response:JSON.parse(response.body),redirect:redirect.status,bytes,baseline:stored===baseline,backupValid};
  },localServer);
  if(probes.response.method!=='POST'||!probes.response.authorized||probes.response.value!=='native-transport'||probes.redirect!==307||JSON.stringify(probes.bytes)!=='[0,1,127,255]'||!probes.baseline||!probes.backupValid)throw new Error('Native HTTP/download/baseline/backup probe failed');
  previous = await page.evaluate((key) => localStorage.getItem(key), key);
  await page.getByRole('button', { name: '新建任务', exact: true }).click();
  await page.getByLabel('任务名称', { exact: true }).fill('原生窗口测试');
  await page.getByRole('button', { name: '保存', exact: true }).click();
  await page.getByRole('dialog').waitFor({ state: 'detached' });
  const guestDirectory = join(testDirectory, 'workspaces', Buffer.from('guest').toString('hex'));
  for (let attempt=0;attempt<40;attempt++) {
    try {
      const stored=JSON.parse(await readFile(join(guestDirectory,'workspace.json'),'utf8'));
      if(stored.tasks.some(task=>task.title==='原生窗口测试')) break;
    } catch {}
    if(attempt===39)throw new Error('Native disk save did not finish');
    await new Promise(resolve=>setTimeout(resolve,100));
  }
  await page.evaluate(key=>localStorage.removeItem(key),key);
  await page.reload();
  await page.getByRole('button', { name: '编辑任务：原生窗口测试' }).waitFor();
  await mkdir(new URL('../artifacts/', import.meta.url), { recursive: true });
  await page.screenshot({ path: fileURLToPath(new URL('../artifacts/native-windows.png', import.meta.url)) });
  const backups=await readdir(guestDirectory);
  if(!backups.includes('workspace.json'))throw new Error('Native file missing');
  console.log('PASS: isolated native Tauri/WebView2 startup, editor, durable disk save and reload without browser cache');
} finally {
  if (page && previous !== undefined)
    await page
      .evaluate(
        ({ key, previous }) => {
          if (previous === null) localStorage.removeItem(key);
          else localStorage.setItem(key, previous);
        },
        { key, previous },
      )
      .catch(() => {});
  if (browser) await browser.close();
  app.kill();
  await new Promise(resolve=>server.close(resolve));
}
