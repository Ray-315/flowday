import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { expect, it, vi } from 'vitest';
import { SettingsPage, type SettingsSection } from './SettingsPage';
import { emptyWorkspace } from './workspace';
vi.mock('./Editors', () => ({ Settings: () => <div>导入导出面板</div> }));
vi.mock('./Management', () => ({ Preferences: () => null, LocalBackups: () => <div>本地备份面板</div> }));
it('keeps sync, backups and integrations in their own settings groups', async () => {
  Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
  const container = document.createElement('div');
  const root = createRoot(container);
  const render = async (section: SettingsSection) => act(async () => root.render(
    <SettingsPage data={emptyWorkspace()} onSave={()=>true} onImport={()=>true} rawBackup={()=>null} scope="test" section={section} onSection={()=>{}}
      account={<div>账号安全面板</div>} cloudSync={<div>工作区同步面板</div>} cloudBackups={<div>服务器备份面板</div>}
      apple={<div>iCloud 连接面板</div>} feishu={<div>飞书连接面板</div>} onToday={()=>{}} onCourses={()=>{}} onDone={()=>{}}/>
  ));
  const click = async (label: string) => act(async () => [...container.querySelectorAll('button')].find(button=>button.textContent===label)!.click());
  try {
    await render('cloud');
    expect(container.textContent).toContain('工作区同步面板');
    expect(container.textContent).not.toContain('iCloud 连接面板');
    await click('云备份');
    expect(container.textContent).toContain('服务器备份面板');
    expect(container.textContent).not.toContain('工作区同步面板');
    await click('本地备份');
    expect(container.textContent).toContain('本地备份面板');
    await render('integrations');
    expect(container.textContent).toContain('iCloud 连接面板');
    await click('飞书通知');
    expect(container.textContent).toContain('飞书连接面板');
    expect(container.textContent).not.toContain('iCloud 连接面板');
    await render('account');
    expect(container.textContent).toContain('账号安全面板');
    expect(container.textContent).not.toContain('工作区同步面板');
  } finally { await act(async () => root.unmount()); }
});
