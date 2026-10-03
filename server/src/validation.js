export class ApiError extends Error {
  constructor(status, code, message, extra = {}) { super(message); Object.assign(this, { status, code, extra }); }
}
export const check = (ok, message = '请求数据无效') => { if (!ok) throw new ApiError(400, 'VALIDATION_ERROR', message); };
export const emptyData = () => ({schemaVersion:1,projects:[],tasks:[],events:[],nodes:[],edges:[],captures:[],notices:[],preferences:{}});
const string = v => typeof v === 'string' && v.length <= 20000;
const text = v => string(v) && v.trim().length > 0;
const id = v => text(v) && v.length <= 128;
export const date = v => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(v) && Number.isFinite(Date.parse(v));
const integer = v => Number.isSafeInteger(v) && v >= 0;
const bool = v => typeof v === 'boolean';
const nullable = f => v => v === null || f(v);
const one = values => v => values.includes(v);
export function object(value, fields, required = []) {
  check(value && typeof value === 'object' && !Array.isArray(value));
  check(Object.keys(value).every(k => Object.hasOwn(fields, k)), '存在未知字段');
  for (const k of required) check(Object.hasOwn(value,k), `缺少字段 ${k}`);
  for (const [k,v] of Object.entries(value)) check(fields[k](v), `字段 ${k} 无效`);
}
const common = {id,title:text,description:string,deletedAt:nullable(date)};
const repeatRule = nullable(v=>{object(v,{frequency:one(['daily','weekly','monthly','yearly']),interval:n=>integer(n)&&n>=1&&n<=366,count:nullable(n=>integer(n)&&n>=1&&n<=1000),until:nullable(date)},['frequency','interval']);return true;});
const attachments = v=>{check(Array.isArray(v)&&v.length<=100);const seen=new Set();for(const a of v){object(a,{id,title:text,kind:one(['file','url','markdown']),content:string},['id','title','kind','content']);check(!seen.has(a.id),'附件标识重复');seen.add(a.id);}return true;};
const recurring = {repeatRule,seriesId:nullable(id),occurrenceDate:nullable(date),attachments,strongReminder:nullable(bool),reminderInterval:nullable(n=>integer(n)&&n>=1&&n<=10080),maxReminders:nullable(n=>integer(n)&&n>=1&&n<=50)};
const reminderRules=v=>{check(Array.isArray(v)&&v.length<=10,'提醒规则最多10项');const seen=new Set();for(const rule of v){object(rule,{leadMinutes:n=>integer(n)&&n<=10080,dueAt:date});check(Object.keys(rule).length===1,'提醒规则必须选择提前分钟或绝对时间');const key='leadMinutes' in rule?'lead:'+rule.leadMinutes:'at:'+Date.parse(rule.dueAt);check(!seen.has(key),'提醒规则重复');seen.add(key);}return true;};
const fields = {
  projects:{...common,parentId:nullable(id),color:integer,deadline:nullable(date),archived:bool,attachments},
  tasks:{...common,...recurring,projectId:nullable(id),parentId:nullable(id),status:one(['todo','doing','waiting','done','cancelled']),priority:one(['low','normal','high','urgent']),difficulty:one(['low','normal','high']),archived:bool,plannedStart:nullable(date),estimateMinutes:integer,actualMinutes:integer,deadline:nullable(date),completedAt:nullable(date),splittable:bool,tags:v=>Array.isArray(v)&&v.length<=100&&v.every(string)},
  events:{...recurring,id,title:text,start:date,end:date,projectId:nullable(id),taskId:nullable(id),color:integer,location:string,notes:string,completed:bool,locked:bool,allDay:bool,deletedAt:nullable(date),actualMinutes:integer,reminderLeadMinutes:nullable(n=>integer(n)&&n<=10080),reminderRules:nullable(reminderRules),tags:v=>Array.isArray(v)&&v.length<=100&&v.every(string)},
  nodes:{id,projectId:id,title:text,description:string,kind:one(['task','condition','delay','milestone','note','link','group']),status:one(['locked','ready','doing','waiting','done','skipped']),taskId:nullable(id),x:Number.isFinite,y:Number.isFinite,anyPredecessor:bool,groupId:nullable(id),targetProjectId:nullable(id),selectedBranchEdgeId:nullable(id),collapsed:bool,completedAt:nullable(date),delayWaiting:bool},
  edges:{id,projectId:id,sourceId:id,targetId:id,label:string,active:bool,delayMinutes:integer,availableAt:nullable(date)},
  captures:{id,text,createdAt:date,processed:bool},
  notices:{id,title:text,body:string,createdAt:date,read:bool,acknowledged:bool,taskId:nullable(id),type:nullable(one(['reminder','calendar_conflict','workflow','ai','system'])),eventId:nullable(id),projectId:nullable(id),nodeId:nullable(id)}
};
export function validateData(data) {
  object(data,{schemaVersion:v=>v===1,...Object.fromEntries(Object.keys(fields).map(k=>[k,Array.isArray])),preferences:v=>v&&typeof v==='object'&&!Array.isArray(v)},Object.keys(emptyData()));
  const maps = {};
  for (const [key,schema] of Object.entries(fields)) {
    check(data[key].length<=10000,'对象数量超限');
    const required = ['id',...(key==='captures'?['text','createdAt']:key==='edges'?['projectId','sourceId','targetId']:key==='notices'?['title','body','createdAt']:['title']),...(key==='events'?['start','end']:key==='nodes'?['projectId']:[])];
    maps[key] = new Map();
    for(const row of data[key]) { object(row,schema,required); check(!maps[key].has(row.id),'标识重复'); maps[key].set(row.id,row); }
  }
  const ref = (v,key) => check(v==null||maps[key].has(v),'关联对象不存在');
  for(const key of ['projects','tasks','events','nodes','edges','notices']) for(const row of data[key]) {
    if('projectId' in row) ref(row.projectId,'projects');
    if('taskId' in row) ref(row.taskId,'tasks');
    if(key==='notices'){ref(row.eventId,'events');ref(row.nodeId,'nodes');}
    if('parentId' in row) ref(row.parentId,key);
    if(key==='nodes'){ref(row.groupId,'nodes');ref(row.targetProjectId,'projects');ref(row.selectedBranchEdgeId,'edges');if(row.groupId)check(maps.nodes.get(row.groupId).kind==='group'&&maps.nodes.get(row.groupId).projectId===row.projectId,'分组项目不匹配');if(row.selectedBranchEdgeId)check(maps.edges.get(row.selectedBranchEdgeId).sourceId===row.id,'分支必须属于当前节点');}
    if(key==='events') check(Date.parse(row.end)>Date.parse(row.start),'结束时间必须晚于开始时间');
    if(key==='edges') { ref(row.sourceId,'nodes'); ref(row.targetId,'nodes'); check(maps.nodes.get(row.sourceId).projectId===row.projectId&&maps.nodes.get(row.targetId).projectId===row.projectId,'连线项目不匹配'); }
  }
  for(const key of ['projects','tasks']) for(const row of data[key]) {
    const seen=new Set(); let next=row;
    while(next) { check(!seen.has(next.id),'父级关系存在循环'); seen.add(next.id); next=maps[key].get(next.parentId); }
  }
  const known={calendarView:one(['月','周','日','时间轴','列表']),overlapStyle:one(['并排','层叠','聚合']),weekStartsMonday:bool,displayName:v=>string(v)&&v.length<=100,themeMode:one(['system','light','dark']),fontScale:v=>Number.isFinite(v)&&v>=0.5&&v<=3,density:one(['compact','comfortable','spacious','紧凑','舒适','宽松']),reminderMinutes:integer,reminderInterval:integer,maxReminders:integer,todayModules:v=>Array.isArray(v)&&v.length<=30&&v.every(string),defaultPriority:one(['low','normal','high','urgent']),defaultDifficulty:v=>string(v)||integer(v),timezone:v=>{try {new Intl.DateTimeFormat('en',{timeZone:v});return typeof v==='string';}catch{return false;}},dateFormat:string,timeFormat:string};
  known.courseReminderLeadMinutes=n=>integer(n)&&n<=10080;
  known.todayModuleOrder=known.todayModules;
  known.todayHiddenModules=known.todayModules;
  const validTimezone=known.timezone;
  known.timezone=v=>v==='system'||validTimezone(v);
  check(Object.keys(data.preferences).length<=100);
  for(const [k,v] of Object.entries(data.preferences)) { check(!/secret|token|password|private.?key|api.?key|webhook|__proto__|constructor|prototype/i.test(k),'敏感设置必须保存在服务器环境变量'); check(known[k]?known[k](v):v===null||bool(v)||string(v)||(typeof v==='number'&&Number.isFinite(v)),`设置 ${k} 无效`); }
  return data;
}
