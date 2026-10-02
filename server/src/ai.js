import {randomUUID} from 'node:crypto';
import {ApiError,check,object,date,validateData} from './validation.js';
const text=v=>typeof v==='string'&&v.trim().length>0&&v.length<=2000;
const types=['todo','event','todo_update','event_update','event_delete'];
export function applyIntent(data,intent,now,reminders=[]){
 object(intent,{actions:v=>Array.isArray(v)&&v.length>0&&v.length<=200},['actions']);
 const next=structuredClone(data),diff=[],nextReminders=structuredClone(reminders);
 for(const action of intent.actions){
  if(['reminder','reminder_update'].includes(action.type)){
   check(!diff.some(d=>d.collection==='reminders'&&d.id===action.id),'同一提醒只能修改一次');
   object(action,{type:v=>['reminder','reminder_update'].includes(v),id:text,title:text,taskId:v=>v===null||text(v),dueAt:date,intervalMinutes:v=>Number.isSafeInteger(v)&&v>=1&&v<=10080,maxReminders:v=>Number.isSafeInteger(v)&&v>=1&&v<=100,strong:v=>typeof v==='boolean',channel:v=>['in_app','feishu'].includes(v)},action.type==='reminder'?['type','title','dueAt']:['type','id']);
   let before=null,item;if(action.type==='reminder_update'){item=nextReminders.find(r=>r.id===action.id);check(item,'提醒不存在');before=structuredClone(item);}else {item={id:randomUUID(),taskId:null,eventId:null,intervalMinutes:5,maxReminders:3,strong:true,channel:'in_app',sentCount:0,acknowledged:false,lastError:null};nextReminders.push(item);}
   for(const [key,value] of Object.entries(action))if(!['type','id'].includes(key))item[key]=value;
   item.dueAt=new Date(item.dueAt).toISOString();
   if(before&&before.dueAt!==item.dueAt){item.sentCount=0;item.acknowledged=false;item.lastError=null;}
   diff.push({type:action.type,collection:'reminders',id:item.id,before,after:structuredClone(item)});continue;
  }
  object(action,{type:v=>types.includes(v),id:text,title:text,start:date,end:date,taskId:v=>v===null||text(v),projectId:v=>v===null||text(v),status:v=>['todo','doing','waiting','done','cancelled'].includes(v),estimateMinutes:v=>Number.isSafeInteger(v)&&v>0&&v<=10080,deadline:v=>v===null||date(v),plannedStart:v=>v===null||date(v),priority:v=>['low','normal','high','urgent'].includes(v),difficulty:v=>['low','normal','high'].includes(v),completed:v=>typeof v==='boolean'},['type']);
  const isTask=action.type.startsWith('todo'),collection=isTask?'tasks':'events';
  let before=null,item;
  if(action.type.includes('_')){
   check(text(action.id),'修改需要对象标识');item=next[collection].find(v=>v.id===action.id&&!v.deletedAt);check(item,'目标对象不存在');before=structuredClone(item);
   if(!isTask)check(!item.locked&&!item.completed&&Date.parse(item.start)>now,'不能移动已锁定、已开始或已完成的日程');
   if(action.type==='event_delete'){check(Object.keys(action).every(k=>['type','id'].includes(k)),'删除动作只允许对象标识');item.deletedAt=new Date(now).toISOString();diff.push({type:action.type,id:item.id,before,after:structuredClone(item)});continue;}
  }else {check(text(action.title),'创建需要标题');item={id:randomUUID(),...(isTask?{status:'todo',priority:'normal',estimateMinutes:60,actualMinutes:0,tags:[]}:{})};next[collection].push(item);}
  const allowed=isTask?['title','status','estimateMinutes','deadline','plannedStart','priority','difficulty','projectId']:['title','start','end','taskId','projectId','completed'];
  check(Object.keys(action).every(k=>['type','id',...allowed].includes(k)),'动作包含不支持的字段');
  for(const k of allowed)if(Object.hasOwn(action,k))item[k]=action[k];
  if(isTask&&item.status==='done'&&before?.status!=='done')item.completedAt=new Date(now).toISOString();
  diff.push({type:action.type,id:item.id,before,after:structuredClone(item)});
 }
 for(const change of diff.filter(d=>d.collection==='reminders'))if(change.after.taskId)check(next.tasks.some(t=>t.id===change.after.taskId&&!t.deletedAt&&!['done','cancelled'].includes(t.status)),'提醒目标任务无效');
 validateData(next);return {data:next,diff,reminders:nextReminders};
}
export function scheduleCandidates(data,input,now){
 object(input,{taskIds:v=>Array.isArray(v)&&v.length>0&&v.length<=100&&new Set(v).size===v.length&&v.every(text),start:date,end:date,timezone:text,replan:v=>typeof v==='boolean',excluded:v=>Array.isArray(v)&&v.length<=100&&v.every(x=>date(x.start)&&date(x.end)&&Date.parse(x.end)>Date.parse(x.start))},['taskIds','start','end','timezone']);
 try{new Intl.DateTimeFormat('en',{timeZone:input.timezone});}catch{check(false,'时区无效');}
 const start=Date.parse(input.start),end=Date.parse(input.end);check(start>=now&&end>start&&end-start<=31*86400000,'排程范围必须在未来且不超过31天');
 const tasks=input.taskIds.map(id=>{const task=data.tasks.find(t=>t.id===id&&!t.deletedAt&&!['done','cancelled'].includes(t.status));check(task,'任务不存在或已完成');check(!data.nodes.some(n=>n.taskId===id&&(['locked','waiting'].includes(n.status)||n.delayWaiting)),'任务依赖尚未满足');return task;});
 const movable=input.replan?data.events.filter(e=>input.taskIds.includes(e.taskId)&&!e.deletedAt&&!e.completed&&!e.locked&&Date.parse(e.start)>now):[];
 const busy=data.events.filter(e=>!e.deletedAt&&!movable.includes(e)).map(e=>[Date.parse(e.start),Date.parse(e.end)]).concat((input.excluded??[]).map(e=>[Date.parse(e.start),Date.parse(e.end)]));
 const priority={urgent:0,high:1,normal:2,low:3};
 const ordered=[...tasks].sort((a,b)=>(Date.parse(a.deadline??input.end)-Date.parse(b.deadline??input.end))||((priority[a.priority]??2)-(priority[b.priority]??2)));
 const strategies=[['尽快完成',0],['均衡负载',1],['减少改动',2]];
 return strategies.map(([label,strategy])=>{
  const occupied=[...busy],actions=[],reused=new Set();let cursor=start;
  for(const [taskIndex,task] of ordered.entries()){
   const existing=data.events.filter(e=>e.taskId===task.id&&!e.deletedAt&&!e.completed&&!movable.includes(e));
   let remaining=Math.max(0,(task.estimateMinutes??60)*60000-existing.reduce((sum,e)=>sum+Date.parse(e.end)-Date.parse(e.start),0));
   const deadline=Math.min(end,Date.parse(task.deadline??input.end));
   while(remaining>0){
    const length=task.splittable?Math.min(remaining,60*60000):remaining;
    const old=strategy===2?movable.find(e=>e.taskId===task.id&&!reused.has(e.id)):null;
    const preferred=strategy===2?Math.max(cursor,Date.parse(old?.start??input.start)):strategy===1?Math.max(cursor,Math.min(deadline-length,start+taskIndex*(end-start)/ordered.length)):cursor;
    const findSlot=from=>{let at=from;while(at+length<=deadline){const conflict=occupied.filter(([s,e])=>at<e&&at+length>s).sort((a,b)=>a[1]-b[1])[0];if(conflict){at=conflict[1];continue;}return at;}return null;};
    const at=findSlot(preferred)??findSlot(cursor);
    if(at===null)throw new ApiError(422,'NO_SCHEDULE_AVAILABLE','可用时段无法满足任务耗时和截止时间');
    const action={type:old?'event_update':'event',...(old?{id:old.id}:{}),title:task.title,taskId:task.id,...(task.projectId?{projectId:task.projectId}:{}),start:new Date(at).toISOString(),end:new Date(at+length).toISOString()};if(old)reused.add(old.id);
    actions.push(action);occupied.push([at,at+length]);remaining-=length;cursor=at+length;
   }
  }
  actions.push(...movable.filter(e=>!reused.has(e.id)).map(e=>({type:'event_delete',id:e.id})));
  if(!actions.length)throw new ApiError(422,'ALREADY_SCHEDULED','所选任务已经安排完整时间块');
  const intent={actions};return {id:String(strategy),label,intent,diff:applyIntent(data,intent,now).diff};
 });
}
