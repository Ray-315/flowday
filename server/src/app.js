import Fastify from 'fastify';
import { registerAi } from './ai_routes.js';
import { registerIntegrations } from './integrations.js';
import { registerData } from './data_routes.js';
import { registerAttachments } from './attachments.js';
import { registerSnapshots } from './snapshots.js';
import { registerCalDav } from './caldav.js';
import { registerRegistration } from './registration.js';
import rateLimit from '@fastify/rate-limit';
import cors from '@fastify/cors';
import { DatabaseSync } from 'node:sqlite';
import { randomBytes, randomUUID, scrypt as scryptCb, timingSafeEqual, createHash } from 'node:crypto';
import { promisify } from 'node:util';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { ApiError, check, emptyData, validateData, object, date } from './validation.js';
const scrypt=promisify(scryptCb), hash=v=>createHash('sha256').update(v).digest('hex');
const integer=v=>Number.isSafeInteger(v)&&v>=0;
const nonempty=v=>typeof v==='string'&&v.trim().length>0&&v.length<=2000;
export async function createApp(options={}) {
  const now=options.now??Date.now, env=options.env??process.env;
  const path=options.databasePath??env.DATABASE_PATH??'./data/flowday.sqlite';
  if(path!==':memory:') mkdirSync(dirname(path),{recursive:true});
  const db=new DatabaseSync(path);
  db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;
    CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,email TEXT UNIQUE NOT NULL,name TEXT NOT NULL,salt TEXT NOT NULL,password TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS workspaces(user_id TEXT PRIMARY KEY REFERENCES users(id),version INTEGER NOT NULL,data TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS reminders(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),task_id TEXT,due INTEGER NOT NULL,interval_ms INTEGER NOT NULL,max_count INTEGER NOT NULL,sent INTEGER NOT NULL DEFAULT 0,acknowledged INTEGER NOT NULL DEFAULT 0,strong INTEGER NOT NULL,title TEXT NOT NULL,channel TEXT NOT NULL,last_error TEXT);
    CREATE TABLE IF NOT EXISTS backups(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),created INTEGER NOT NULL,reason TEXT NOT NULL,version INTEGER NOT NULL,data TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS backups_user ON backups(user_id,created);
    CREATE TABLE IF NOT EXISTS audit(id TEXT PRIMARY KEY,user_id TEXT NOT NULL,action TEXT NOT NULL,created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS previews(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),expires INTEGER NOT NULL,intent TEXT NOT NULL,applied_version INTEGER);
  `);
  if(!db.prepare('PRAGMA table_info(reminders)').all().some(column=>column.name==='event_id'))db.exec('ALTER TABLE reminders ADD COLUMN event_id TEXT');
  if(!db.prepare('PRAGMA table_info(reminders)').all().some(column=>column.name==='rule_key')){db.exec('ALTER TABLE reminders ADD COLUMN rule_key TEXT');db.exec("UPDATE reminders SET rule_key='default' WHERE event_id IS NOT NULL");}
  db.exec('DROP INDEX IF EXISTS reminders_event; CREATE UNIQUE INDEX IF NOT EXISTS reminders_event_rule ON reminders(user_id,event_id,rule_key) WHERE event_id IS NOT NULL AND rule_key IS NOT NULL; CREATE UNIQUE INDEX IF NOT EXISTS reminders_task_rule ON reminders(user_id,task_id,rule_key) WHERE event_id IS NULL AND task_id IS NOT NULL AND rule_key IS NOT NULL');
  const app=Fastify({logger:false,bodyLimit:2*1024*1024,trustProxy:false});
  await app.register(rateLimit,{global:true,max:300,timeWindow:'1 minute'});
  await app.register(cors,{origin:env.CORS_ORIGIN?env.CORS_ORIGIN.split(','):false,methods:['GET','POST','PUT'],allowedHeaders:['Authorization','Content-Type']});
  const tx=fn=>{db.exec('BEGIN IMMEDIATE');try{const result=fn();db.exec('COMMIT');return result;}catch(e){db.exec('ROLLBACK');throw e;}};
  const audit=(uid,action)=>db.prepare('INSERT INTO audit VALUES(?,?,?,?)').run(randomUUID(),uid,action,now());
  const workspace=uid=>{const row=db.prepare('SELECT version,data FROM workspaces WHERE user_id=?').get(uid);return {version:row.version,data:JSON.parse(row.data)};};
  const reminderConfig=data=>{
    const p=data.preferences,lead=p.reminderMinutes??15,interval=p.reminderInterval??5,count=p.maxReminders??3,strong=p.strongReminder??false;
    check(integer(lead)&&lead<=10080,'提前提醒时间无效');
    check(integer(interval)&&interval>=1&&interval<=10080,'提醒间隔无效');
    check(integer(count)&&count>=1&&count<=100,'提醒次数无效');
    check(typeof strong==='boolean','强提醒设置无效');
    return {lead,interval,count,strong};
  };
  const effectiveReminderConfig=(data,task,event)=>{const c=reminderConfig(data);return {...c,strong:event?.strongReminder??task?.strongReminder??c.strong,interval:event?.reminderInterval??task?.reminderInterval??c.interval,count:Math.min(50,event?.maxReminders??task?.maxReminders??c.count)};};
  const reconcileEventReminders=(uid,before,after)=>{
    const config=reminderConfig(after),previous=reminderConfig(before);
    const rules=(event,c)=>event.reminderRules==null?[{key:'default',due:Date.parse(event.start)-(event.reminderLeadMinutes??c.lead)*60000}]:event.reminderRules.map(rule=>'leadMinutes' in rule?{key:'lead:'+rule.leadMinutes,due:Date.parse(event.start)-rule.leadMinutes*60000}:{key:'at:'+Date.parse(rule.dueAt),due:Date.parse(rule.dueAt)});
    const oldEvents=new Map(before.events.map(event=>[event.id,event]));
    const events=new Map(after.events.map(event=>[event.id,event]));
    const tasks=new Map(after.tasks.map(task=>[task.id,task]));
    const oldTasks=new Map(before.tasks.map(task=>[task.id,task]));
    const activeTask=(id,map)=>!id||(map.has(id)&&!map.get(id).deletedAt&&!['done','cancelled'].includes(map.get(id).status));
    const active=event=>event&&!event.deletedAt&&!event.completed&&Date.parse(event.end)>now()&&activeTask(event.taskId,tasks);
    const existing=new Map(db.prepare('SELECT * FROM reminders WHERE user_id=? AND event_id IS NOT NULL AND rule_key IS NOT NULL').all(uid).map(row=>[row.event_id+'|'+row.rule_key,row]));
    for(const row of existing.values()){
      const event=events.get(row.event_id);
      if(!active(event)||!rules(event,config).some(rule=>rule.key===row.rule_key))db.prepare('DELETE FROM reminders WHERE id=?').run(row.id);
    }
    for(const event of after.events){
      if(!active(event)||Date.parse(event.start)<=now())continue;
      const old=oldEvents.get(event.id),oldRules=old?rules(old,previous):[];
      const effective=effectiveReminderConfig(after,tasks.get(event.taskId),event),oldEffective=effectiveReminderConfig(before,oldTasks.get(old?.taskId),old);
      const settingsChanged=effective.interval!==oldEffective.interval||effective.count!==oldEffective.count||effective.strong!==oldEffective.strong;
      for(const rule of rules(event,config)){
       const row=existing.get(event.id+'|'+rule.key),oldRule=oldRules.find(r=>r.key===rule.key);
       const scheduleChanged=!old||!oldRule||oldRule.due!==rule.due||!!old.completed!==!!event.completed||!!old.deletedAt!==!!event.deletedAt||activeTask(old.taskId,oldTasks)!==activeTask(event.taskId,tasks);
       if(!scheduleChanged&&!settingsChanged){
        if(row)db.prepare('UPDATE reminders SET title=?,task_id=? WHERE id=?').run(event.title,event.taskId??null,row.id);
        continue;
       }
       if(row)db.prepare('DELETE FROM reminders WHERE id=?').run(row.id);
       const due=Math.max(now(),rule.due);
       db.prepare('INSERT INTO reminders(id,user_id,event_id,rule_key,task_id,due,interval_ms,max_count,strong,title,channel) VALUES(?,?,?,?,?,?,?,?,?,?,?)').run(randomUUID(),uid,event.id,rule.key,event.taskId??null,due,effective.interval*60000,effective.strong?effective.count:1,effective.strong?1:0,event.title,integrations.configured(uid)?'feishu':'in_app');
      }
    }
  };
  const reconcileTaskDeadlines=(uid,before,after)=>{
    const active=task=>task&&task.deadline&&!task.deletedAt&&!['done','cancelled'].includes(task.status);
    const oldTasks=new Map(before.tasks.map(t=>[t.id,t])),tasks=new Map(after.tasks.map(t=>[t.id,t]));
    const existing=new Map(db.prepare("SELECT * FROM reminders WHERE user_id=? AND event_id IS NULL AND rule_key='deadline'").all(uid).map(r=>[r.task_id,r]));
    for(const row of existing.values())if(!active(tasks.get(row.task_id)))db.prepare('DELETE FROM reminders WHERE id=?').run(row.id);
    for(const task of after.tasks){
      if(!active(task))continue;
      const row=existing.get(task.id),old=oldTasks.get(task.id),c=effectiveReminderConfig(after,task),previous=effectiveReminderConfig(before,old);
      const changed=!row||!active(old)||Date.parse(old.deadline)!==Date.parse(task.deadline)||c.strong!==previous.strong||c.interval!==previous.interval||c.count!==previous.count;
      if(!changed){db.prepare('UPDATE reminders SET title=? WHERE id=?').run(task.title,row.id);continue;}
      if(row)db.prepare('DELETE FROM reminders WHERE id=?').run(row.id);
      db.prepare('INSERT INTO reminders(id,user_id,task_id,rule_key,due,interval_ms,max_count,strong,title,channel) VALUES(?,?,?,?,?,?,?,?,?,?)').run(randomUUID(),uid,task.id,'deadline',Math.max(now(),Date.parse(task.deadline)),c.interval*60000,c.strong?c.count:1,Number(c.strong),task.title,integrations.configured(uid)?'feishu':'in_app');
    }
  };
  const cas=(uid,base,data)=>{validateData(data);const before=workspace(uid).data; const result=db.prepare('UPDATE workspaces SET version=version+1,data=? WHERE user_id=? AND version=?').run(JSON.stringify(data),uid,base);if(!result.changes) throw new ApiError(409,'VERSION_CONFLICT','工作区已更新，请重新读取',{currentVersion:workspace(uid).version});reconcileEventReminders(uid,before,data);reconcileTaskDeadlines(uid,before,data);return base+1;};
  const backup=(uid,reason)=>{const w=workspace(uid),id=randomUUID();db.prepare('INSERT INTO backups VALUES(?,?,?,?,?,?)').run(id,uid,now(),reason,w.version,JSON.stringify(w.data));attachments.snapshot(id,uid);return {id,createdAt:new Date(now()).toISOString(),version:w.version,reason};};
  const auth=async request=>{const bearer=request.headers.authorization; if(typeof bearer!=='string'||!/^Bearer [a-f0-9]{64}$/.test(bearer)) throw new ApiError(401,'UNAUTHORIZED','请登录');const row=db.prepare('SELECT user_id FROM sessions WHERE token_hash=? AND expires>?').get(hash(bearer.slice(7)),now());if(!row)throw new ApiError(401,'UNAUTHORIZED','会话已失效');request.uid=row.user_id;};
  const user=uid=>{const row=db.prepare('SELECT id,email,name FROM users WHERE id=?').get(uid);return {id:row.id,email:row.email,displayName:row.name};};
  const session=uid=>{const token=randomBytes(32).toString('hex');db.prepare('INSERT INTO sessions VALUES(?,?,?)').run(hash(token),uid,now()+30*86400000);return {token,user:user(uid)};};
  app.setErrorHandler((error,request,reply)=>{const status=error.status??(error.statusCode>=400&&error.statusCode<500?error.statusCode:500); reply.code(status).send({error:{code:error.code&&error instanceof ApiError?error.code:status===429?'RATE_LIMITED':status===500?'INTERNAL_ERROR':'BAD_REQUEST',message:status===500?'服务器暂时无法处理请求':error instanceof ApiError?error.message:'请求无效'},...(error.extra??{})});});
  app.get('/health',async()=>{db.prepare('SELECT 1').get();return {status:'ok'};});
  const registration=registerRegistration(app,{db,env,now,tx,sendRegistrationEmail:options.sendRegistrationEmail,mailFetch:options.mailFetch});
  app.post('/api/v1/auth/register',{config:{rateLimit:{max:10,timeWindow:'15 minutes'}}},async(req,reply)=>{
    object(req.body,{email:registration.emailValid,password:v=>typeof v==='string'&&v.length>=10&&v.length<=256,displayName:v=>typeof v==='string'&&v.trim().length>0&&v.length<=100,verificationCode:registration.codeValid},['email','password','displayName','verificationCode']);
    const {password,displayName,verificationCode}=req.body,email=req.body.email.trim().toLowerCase(),nonce=registration.verify(email,verificationCode),salt=randomBytes(16).toString('hex'),digest=(await scrypt(password,salt,64)).toString('hex'),uid=randomUUID();
    const result=tx(()=>{if(db.prepare('SELECT id FROM users WHERE email=?').get(email))throw new ApiError(409,'EMAIL_EXISTS','此邮箱已注册');registration.consume(email,verificationCode,nonce);db.prepare('INSERT INTO users VALUES(?,?,?,?,?)').run(uid,email,displayName.trim(),salt,digest);db.prepare('INSERT INTO workspaces VALUES(?,0,?)').run(uid,JSON.stringify(emptyData()));audit(uid,'register');return session(uid);});return reply.code(201).send(result);
  });
  app.post('/api/v1/auth/login',{config:{rateLimit:{max:15,timeWindow:'15 minutes'}}},async req=>{object(req.body,{email:v=>typeof v==='string'&&v.length<=254,password:v=>typeof v==='string'&&v.length<=256},['email','password']);const row=db.prepare('SELECT * FROM users WHERE email=?').get(req.body.email.trim().toLowerCase());const digest=await scrypt(req.body.password,row?.salt??'flowday-nonexistent-user',64);if(!row||!timingSafeEqual(digest,Buffer.from(row.password,'hex')))throw new ApiError(401,'INVALID_CREDENTIALS','邮箱或密码不正确');return session(row.id);});
  app.get('/api/v1/auth/me',{preHandler:auth},async req=>({user:user(req.uid)}));
  app.put('/api/v1/auth/profile',{preHandler:auth},async req=>{
    object(req.body,{displayName:v=>typeof v==='string'&&v.trim().length>0&&v.length<=100},['displayName']);
    db.prepare('UPDATE users SET name=? WHERE id=?').run(req.body.displayName.trim(),req.uid);
    return {user:user(req.uid)};
  });
  const verifyPassword=async(uid,password)=>{
    const row=db.prepare('SELECT salt,password FROM users WHERE id=?').get(uid);
    const digest=await scrypt(password,row?.salt??'flowday-deleted-user',64);
    if(!row||!timingSafeEqual(digest,Buffer.from(row.password,'hex')))throw new ApiError(401,'INVALID_PASSWORD','当前密码不正确');
    return row.password;
  };
  const sensitive={preHandler:auth,config:{rateLimit:{max:10,timeWindow:'15 minutes'}}};
  app.post('/api/v1/auth/password',sensitive,async req=>{
    object(req.body,{currentPassword:v=>typeof v==='string'&&v.length<=256,newPassword:v=>typeof v==='string'&&v.length>=10&&v.length<=256},['currentPassword','newPassword']);
    const oldDigest=await verifyPassword(req.uid,req.body.currentPassword),salt=randomBytes(16).toString('hex'),digest=(await scrypt(req.body.newPassword,salt,64)).toString('hex');
    return tx(()=>{
      const result=db.prepare('UPDATE users SET salt=?,password=? WHERE id=? AND password=?').run(salt,digest,req.uid,oldDigest);
      if(!result.changes)throw new ApiError(409,'ACCOUNT_CHANGED','账号已更新，请重新登录');
      db.prepare('DELETE FROM sessions WHERE user_id=? AND token_hash<>?').run(req.uid,hash(req.headers.authorization.slice(7)));
      audit(req.uid,'password.change');return {changed:true};
    });
  });
  app.get('/api/v1/auth/sessions',{preHandler:auth},async req=>({sessions:db.prepare('SELECT token_hash,expires FROM sessions WHERE user_id=? AND expires>? ORDER BY expires DESC').all(req.uid,now()).map(r=>({current:r.token_hash===hash(req.headers.authorization.slice(7)),expiresAt:new Date(r.expires).toISOString()}))}));
  app.post('/api/v1/auth/sessions/revoke-others',{preHandler:auth},async req=>({revoked:db.prepare('DELETE FROM sessions WHERE user_id=? AND token_hash<>?').run(req.uid,hash(req.headers.authorization.slice(7))).changes}));
  app.post('/api/v1/auth/delete',sensitive,async(req,reply)=>{
    object(req.body,{password:v=>typeof v==='string'&&v.length<=256,confirmation:v=>v==='DELETE'},['password','confirmation']);
    const verified=await verifyPassword(req.uid,req.body.password);
    tx(()=>{
      const row=db.prepare('SELECT password FROM users WHERE id=?').get(req.uid);
      if(!row||row.password!==verified)throw new ApiError(409,'ACCOUNT_CHANGED','账号已更新，请重新登录');
      for(const table of ['sessions','workspaces','reminders','backups','previews','audit','audit_changes','integrations','reminder_actions','attachments','calendar_mappings','calendar_connections'])db.prepare(`DELETE FROM ${table} WHERE user_id=?`).run(req.uid);
      db.prepare('DELETE FROM users WHERE id=?').run(req.uid);
    });return reply.code(204).send();
  });
  app.post('/api/v1/auth/logout',{preHandler:auth},async(req,reply)=>{db.prepare('DELETE FROM sessions WHERE token_hash=?').run(hash(req.headers.authorization.slice(7)));return reply.code(204).send();});
  app.get('/api/v1/workspace',{preHandler:auth},async req=>workspace(req.uid));
  app.put('/api/v1/workspace',{preHandler:auth},async req=>{object(req.body,{baseVersion:integer,data:v=>!!v},['baseVersion','data']);return tx(()=>{const version=cas(req.uid,req.body.baseVersion,req.body.data);audit(req.uid,'workspace.update');return {version};});});
  app.get('/api/v1/backups',{preHandler:auth},async req=>({backups:db.prepare('SELECT id,created,reason,version FROM backups WHERE user_id=? ORDER BY created DESC LIMIT 100').all(req.uid).map(r=>({id:r.id,createdAt:new Date(r.created).toISOString(),reason:r.reason,version:r.version}))}));
  app.post('/api/v1/backups',{preHandler:auth},async req=>tx(()=>backup(req.uid,'manual')));
  app.post('/api/v1/backups/:id/restore',{preHandler:auth},async req=>{object(req.body,{baseVersion:integer},['baseVersion']);return tx(()=>{const row=db.prepare('SELECT data FROM backups WHERE id=? AND user_id=?').get(req.params.id,req.uid);if(!row)throw new ApiError(404,'NOT_FOUND','备份不存在');const protectionBackup=backup(req.uid,'before_restore');const version=cas(req.uid,req.body.baseVersion,JSON.parse(row.data));attachments.restore(req.params.id,req.uid);audit(req.uid,'backup.restore');return {version,protectionBackup};});});
  const reminderRow=r=>({id:r.id,taskId:r.task_id,eventId:r.event_id,ruleKey:r.rule_key,dueAt:new Date(r.due).toISOString(),intervalMinutes:r.interval_ms/60000,maxReminders:r.max_count,sentCount:r.sent,acknowledged:!!r.acknowledged,strong:!!r.strong,title:r.title,channel:r.channel,lastError:r.last_error});
  app.get('/api/v1/reminders',{preHandler:auth},async req=>({reminders:db.prepare('SELECT * FROM reminders WHERE user_id=? ORDER BY due').all(req.uid).map(reminderRow)}));
  app.post('/api/v1/reminders',{preHandler:auth},async req=>{object(req.body,{taskId:v=>v===null||nonempty(v),dueAt:date,intervalMinutes:v=>integer(v)&&v>=1&&v<=10080,maxReminders:v=>integer(v)&&v>=1&&v<=100,strong:v=>typeof v==='boolean',title:nonempty,channel:v=>['in_app','feishu'].includes(v)},['dueAt','title']);const b=req.body;if(b.channel==='feishu'&&!integrations.configured(req.uid))throw new ApiError(503,'FEISHU_NOT_CONFIGURED','飞书提醒尚未配置');const data=workspace(req.uid).data,task=b.taskId?data.tasks.find(t=>t.id===b.taskId):null;if(b.taskId)check(task,'任务不存在');const c=task?effectiveReminderConfig(data,task):{interval:5,count:3,strong:true},strong=b.strong??c.strong;const id=randomUUID();db.prepare('INSERT INTO reminders(id,user_id,task_id,due,interval_ms,max_count,strong,title,channel) VALUES(?,?,?,?,?,?,?,?,?)').run(id,req.uid,b.taskId??null,Date.parse(b.dueAt),(b.intervalMinutes??c.interval)*60000,strong?(b.maxReminders??c.count):1,Number(strong),b.title,b.channel??'in_app');return {reminder:reminderRow(db.prepare('SELECT * FROM reminders WHERE id=?').get(id))};});
  app.post('/api/v1/reminders/:id/ack',{preHandler:auth},async req=>{const result=db.prepare('UPDATE reminders SET acknowledged=1 WHERE id=? AND user_id=?').run(req.params.id,req.uid);if(!result.changes)throw new ApiError(404,'NOT_FOUND','提醒不存在');return {acknowledged:true};});
  const calendars=registerCalDav({app,db,auth,env,now,workspace,tx,cas,audit,fetcher:options.caldavFetch??fetch});
  const maybeSnapshot=registerSnapshots({app,db,auth,env,now});
  const attachments=registerAttachments({app,db,auth,now,workspace,audit,tx,cas,backup});
  const integrations=registerIntegrations({app,db,auth,env,now,tx,workspace,cas,audit,fetcher:options.fetch??fetch});
  registerData({app,db,auth,workspace});
  registerAi({app,db,auth,now,env,workspace,tx,cas,audit,fetcher:options.fetch??fetch});
  let working=false;
  async function runWorker() {
    if(working)return;working=true;
    try {
      tx(()=>{for(const row of db.prepare('SELECT user_id FROM workspaces').all()){const data=workspace(row.user_id).data;reconcileTaskDeadlines(row.user_id,data,data);}});
      const due=db.prepare('SELECT * FROM reminders WHERE due<=? AND sent<max_count AND (strong=0 OR acknowledged=0)').all(now());
      for(const r of due){
        const delivered=tx(()=>{if(!db.prepare('SELECT id FROM reminders WHERE id=?').get(r.id))return false;const w=workspace(r.user_id);const task=r.task_id?w.data.tasks.find(t=>t.id===r.task_id):null;const event=r.event_id?w.data.events.find(e=>e.id===r.event_id):null;if((r.task_id&&(!task||task.deletedAt||task.status==='done'||task.status==='cancelled'))||(r.event_id&&(!event||event.deletedAt||event.completed||Date.parse(event.end)<=now()))){db.prepare('UPDATE reminders SET sent=max_count WHERE id=?').run(r.id);return false;}
          w.data.notices.push({id:randomUUID(),title:r.title,body:'计划提醒',createdAt:new Date(now()).toISOString(),read:false,acknowledged:false,type:'reminder',taskId:r.task_id,eventId:r.event_id,projectId:event?.projectId??task?.projectId??null,nodeId:null});cas(r.user_id,w.version,w.data);db.prepare('UPDATE reminders SET sent=sent+1,due=?,last_error=NULL WHERE id=?').run(now()+r.interval_ms,r.id);return true;
        });
        if(delivered&&r.channel==='feishu'){try{await integrations.deliver(r);}catch{db.prepare('UPDATE reminders SET last_error=? WHERE id=?').run('FEISHU_DELIVERY_FAILED',r.id);}}
      }
      tx(()=>{for(const row of db.prepare('SELECT user_id FROM workspaces').all()){
        const last=db.prepare('SELECT MAX(created) AS created FROM backups WHERE user_id=? AND reason=?').get(row.user_id,'daily');
        if(last.created===null||last.created<=now()-86400000){
          backup(row.user_id,'daily');
          const w=workspace(row.user_id),d=w.data,old=v=>v.deletedAt&&Date.parse(v.deletedAt)<now()-30*86400000;
          const reminderTasks=new Set(db.prepare('SELECT task_id FROM reminders WHERE user_id=?').all(row.user_id).map(r=>r.task_id));
          const before=JSON.stringify(d);
          d.events=d.events.filter(e=>!old(e)||d.notices.some(n=>n.eventId===e.id));
          d.tasks=d.tasks.filter(task=>!old(task)||reminderTasks.has(task.id)||d.tasks.some(t=>t.parentId===task.id)||[...d.events,...d.nodes,...d.notices].some(v=>v.taskId===task.id));
          d.projects=d.projects.filter(p=>!old(p)||d.projects.some(v=>v.parentId===p.id)||[...d.tasks,...d.events,...d.nodes,...d.edges,...d.notices].some(v=>v.projectId===p.id));
          if(JSON.stringify(d)!==before){cas(row.user_id,w.version,d);audit(row.user_id,'trash.purge');}
        }
      }attachments.purge();db.prepare('DELETE FROM reminder_actions WHERE expires<=?').run(now());db.prepare('DELETE FROM sessions WHERE expires<=?').run(now());db.prepare('DELETE FROM previews WHERE expires<=? AND applied_version IS NULL').run(now());});
      await calendars.runWorker();
      await maybeSnapshot();
    }finally{working=false;}
  }
  let timer;
  if(options.worker!==false){timer=setInterval(()=>runWorker().catch(()=>{process.stderr.write('Reminder worker failed\n');}),15000);timer.unref();}
  app.addHook('onClose',async()=>{clearInterval(timer);while(working)await new Promise(resolve=>setTimeout(resolve,10));db.close();});
  return {app,db,runWorker};
}
