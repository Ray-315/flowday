import type { ReactNode } from 'react';
import { Settings } from './Editors';
import { Preferences, LocalBackups } from './Management';
import type { Workspace } from './workspace';

export const settingsSections = [
  ['general', '基础设置'], ['account', '账号与同步'], ['schedule', '日程与提醒'],
  ['tasks', '任务与项目'], ['workflow', '工作流'], ['appearance', '界面与外观'],
  ['notifications', '通知'], ['data', '数据与隐私'],
] as const;
export type SettingsSection = typeof settingsSections[number][0];

export function SettingsPage({data, onSave, onImport, rawBackup, scope, section, onSection, account, onToday, onCourses, onDone}: {
  data: Workspace; onSave: (next: Workspace) => boolean; onImport: (next: Workspace) => boolean;
  rawBackup: () => string | null; scope: string; section: SettingsSection;
  onSection: (next: SettingsSection) => void; account: ReactNode;
  onToday: () => void; onCourses: () => void; onDone: () => void;
}) {
  return <div className="settings-page">
    <nav className="settings-navigation" aria-label="设置分类">{settingsSections.map(([key, label]) =>
      <button key={key} aria-current={section === key ? 'page' : undefined} onClick={() => onSection(key)}>{label}</button>
    )}</nav>
    <section className="panel settings-content" key={section} aria-label={settingsSections.find(([key]) => key === section)![1]}>
      <h2>{settingsSections.find(([key]) => key === section)![1]}</h2>
      {section === 'account' ? account : section === 'appearance' ?
        <Settings data={data} onSave={onSave} onImport={onImport} rawBackup={rawBackup} onClose={onDone} embedded section="appearance"/> :
        section === 'data' ? <>
          <Settings data={data} onSave={onSave} onImport={onImport} rawBackup={rawBackup} onClose={onDone} embedded section="data"/>
          <div className="settings-section"><h3>本地备份</h3><LocalBackups scope={scope} onRestore={onImport}/></div>
        </> : <Preferences data={data} onSave={onSave} section={section}/>}
      {section === 'general' && <button className="settings-action" onClick={onToday}>首页模块<span aria-hidden="true">›</span></button>}
      {section === 'schedule' && <button className="settings-action" onClick={onCourses}>导入课程文件<span aria-hidden="true">›</span></button>}
    </section>
  </div>;
}
