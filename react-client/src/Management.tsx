import { useEffect, useState } from 'react';
import { invoke, isTauri } from '@tauri-apps/api/core';
import { parseWorkspace, type Workspace } from './workspace';
import { restoreItem, trashItem } from './domain';
import { workspaceStorage } from './storage';
import { requestNotifications } from './reminders';
import type { Editing } from './App';

export function Projects({data,onSave,onEdit}:{data:Workspace;onSave:(data:Workspace)=>boolean;onEdit:(editing:Editing)=>void}){
  const[tab,setTab]=useState('项目');const[error,setError]=useState('');
  const projects=data.projects.filter(item=>tab==='回收站'?!!item.deletedAt:!item.deletedAt&&(tab==='归档'?item.archived:!item.archived));
  function change(id:string,action:string){try{if(action==='restore')onSave(restoreItem(data,'projects',id));else if(action==='delete')onSave(trashItem(data,'projects',id));else onSave({...data,projects:data.projects.map(item=>item.id===id?{...item,archived:!item.archived}:item)});}catch(failure){setError(failure instanceof Error?failure.message:'操作失败');}}
  return <div><div className="choice-group">{['项目','归档','回收站'].map(value=><button key={value} aria-pressed={tab===value} className={tab===value?'selected':''} onClick={()=>setTab(value)}>{value}</button>)}</div><div className="management-list">{projects.map(item=>{const tasks=data.tasks.filter(task=>task.projectId===item.id&&!task.deletedAt);const done=tasks.filter(task=>task.status==='done').length;return <article key={item.id}><div><button className="management-title" onClick={()=>onEdit({kind:'project',item})}>{item.title}</button><span>{done}/{tasks.length}</span></div><div className="notice-actions">{tab==='回收站'?<button onClick={()=>change(item.id,'restore')}>恢复</button>:<><button onClick={()=>change(item.id,'archive')}>{item.archived?'取消归档':'归档'}</button><button onClick={()=>{if(window.confirm(`删除项目“${item.title}”？`))change(item.id,'delete');}}>删除</button></>}</div></article>;})}</div><button className="primary-button" onClick={()=>onEdit({kind:'project'})}>新建项目</button>{error&&<p className="form-error" role="alert">{error}</p>}</div>;
}
export function Preferences({data,onSave,section='general'}:{data:Workspace;onSave:(data:Workspace)=>boolean;section?:string}){
  const[error,setError]=useState('');
  const update=(key:string,value:unknown)=>{if(!onSave({...data,preferences:{...data.preferences,[key]:value}}))setError('设置保存失败');};
  const zone=String(data.preferences.timezone??'system');
  const zones=['system','Asia/Shanghai','Asia/Tokyo','Europe/London','Europe/Berlin','America/New_York','America/Los_Angeles','UTC'];
  const names:Record<string,string>={low:'低',normal:'普通',high:'高',urgent:'紧急'};
  function choice(label:string,key:string,fallback:string|number,options:readonly (string|number)[]){return <label className="field settings-row" key={key}><span>{label}</span><select value={String(data.preferences[key]??fallback)} onChange={event=>update(key,typeof fallback==='number'?Number(event.target.value):event.target.value)}>{options.map(value=><option key={value} value={value}>{key==='defaultDifficulty'?({low:'简单',normal:'中等',high:'困难'} as Record<string,string>)[value]:names[value]??value}</option>)}</select></label>;}
  return <div className="settings-fields">
    {section==='general'&&<>
    <label className="field"><span>时区</span><select value={zone} onChange={event=>update('timezone',event.target.value)}>{[...new Set([...zones,zone])].map(value=><option key={value} value={value}>{value==='system'?'系统时区':value}</option>)}</select></label>
    </>}
    {section==='schedule'&&<>
    {choice('默认视图','calendarView','月',['月','周','日','时间轴','列表'])}
    {choice('默认日程时长（分钟）','defaultEventMinutes',60,[15,30,60,90,120])}
    {choice('时间粒度（分钟）','timeStepMinutes',15,[5,15,30,60])}
    {choice('重叠日程显示','overlapStyle','并排',['并排','层叠','聚合'])}
    <label className="field settings-row"><span>默认提前提醒（分钟）</span><input type="number" min={0} max={10080} value={Number(data.preferences.reminderMinutes??15)} onChange={event=>{const value=Number(event.target.value);if(value>=0&&value<=10080)update('reminderMinutes',value);}}/></label>
    <label className="field"><span>强提醒间隔（分钟）</span><input type="number" min={1} max={10080} value={Number(data.preferences.reminderInterval??5)} onChange={event=>{const value=Number(event.target.value);if(value>=1&&value<=10080)update('reminderInterval',value);}}/></label>
    <label className="field"><span>最多提醒次数</span><input type="number" min={1} max={100} value={Number(data.preferences.maxReminders??3)} onChange={event=>{const value=Number(event.target.value);if(value>=1&&value<=100)update('maxReminders',value);}}/></label>
    </>}
    {section==='tasks'&&<>
      {choice('默认任务优先级','defaultTaskPriority','normal',['low','normal','high','urgent'])}
      {choice('默认任务难度','defaultDifficulty','normal',['low','normal','high'])}
      {choice('默认预计时长（分钟）','defaultEstimateMinutes',60,[15,30,60,90,120])}
    </>}
    {section==='notifications'&&<label className="toggle-field settings-row"><span>系统通知</span><input type="checkbox" checked={data.preferences.nativeNotifications===true} onChange={async event=>{try{if(!event.target.checked)update('nativeNotifications',false);else if(await requestNotifications())update('nativeNotifications',true);else setError('系统通知未获授权');}catch{setError('无法启用系统通知');}}}/><span className="toggle"/></label>}
    {([['general','weekStartsMonday','周一作为每周开始',true],['schedule','strongReminder','强提醒',false],['workflow','workflowAllowManualUnlock','允许手动解锁节点',true],['workflow','workflowAutoLayout','自动整理节点布局',false],['workflow','workflowAutoTodo','自动创建关联任务',true],['workflow','workflowAutoUnlock','完成节点自动解锁后续',true],['workflow','workflowCheckDependencies','检查节点依赖',true],['workflow','workflowSkipCompletes','跳过节点视为完成',true]] as const).filter(([group])=>group===section).map(([,key,label,fallback])=><label className="toggle-field settings-row" key={key}><span>{label}</span><input type="checkbox" checked={Boolean(data.preferences[key]??fallback)} onChange={event=>update(key,event.target.checked)}/><span className="toggle"/></label>)}
    {error&&<p className="form-error" role="alert">{error}</p>}
  </div>;
}
type Backup={id:string;modifiedAt:number;size:number};
export function LocalBackups({scope,onRestore}:{scope:string;onRestore:(data:Workspace)=>boolean}){
  const[items,setItems]=useState<Backup[]>([]);const[error,setError]=useState('');
  async function load(){if(isTauri())setItems(await invoke<Backup[]>('workspace_backups',{scope}));else{const raw=localStorage.getItem(`${workspaceStorage.key(scope)}.before-import`);setItems(raw?[{id:'before-import',modifiedAt:0,size:raw.length}]:[]);}}
  async function run(operation:()=>Promise<unknown>){try{setError('');await operation();await load();}catch(failure){setError(typeof failure==='string'?failure:failure instanceof Error?failure.message:'备份操作失败');}}
  useEffect(()=>{void run(load);},[scope]);
  return <div><button className="primary-button" onClick={()=>void run(async()=>{await workspaceStorage.flush();if(isTauri())await invoke('workspace_backup',{scope});else workspaceStorage.protect(scope);})}>创建备份</button><div className="management-list">{items.map(item=><article key={item.id}><div><span>{item.modifiedAt?new Date(item.modifiedAt).toLocaleString():'导入前备份'}</span><span>{Math.ceil(item.size/1024)}KB</span></div><button className="secondary-button" onClick={()=>void run(async()=>{if(!window.confirm('备份当前数据后恢复此版本？'))return;const source=isTauri()?await invoke<string>('workspace_backup_read',{scope,id:item.id}):localStorage.getItem(`${workspaceStorage.key(scope)}.before-import`)!;const data=parseWorkspace(source);workspaceStorage.protect(scope);if(!onRestore(data))throw new Error('恢复失败');await workspaceStorage.flush();})}>恢复</button></article>)}</div>{error&&<p className="form-error" role="alert">{error}</p>}</div>;
}
