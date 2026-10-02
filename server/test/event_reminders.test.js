import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {createApp} from './helpers/verified_app.js';
import {emptyData} from '../src/validation.js';
async function fixture(t) {
  let time=Date.parse('2026-09-30T10:00:00Z');
  const ctx=await createApp({databasePath:':memory:',worker:false,env:{},now:()=>time});
  t.after(()=>ctx.app.close());
  const r=await ctx.app.inject({method:'POST',url:'/api/v1/auth/register',payload:{email:'event@example.com',password:'password-12345',displayName:'Name'}});
  const token=r.json().token;
  const call=(method,url,body)=>ctx.app.inject({method,url:'/api/v1'+url,payload:body,headers:{authorization:'Bearer '+token}});
  const get=async()=>(await call('GET','/workspace')).json();
  const put=async data=>{const w=await get();const response=await call('PUT','/workspace',{baseVersion:w.version,data});assert.equal(response.statusCode,200,response.body);};
  const reminders=async()=>(await call('GET','/reminders')).json().reminders;
  return {...ctx,call,get,put,reminders,advance:ms=>{time+=ms;}};
}
const event=(id='e')=>({id,title:'Meeting',start:'2026-09-30T11:00:00Z',end:'2026-09-30T12:00:00Z'});
test('new event uses default lead time and one ordinary reminder',async t=>{
  const f=await fixture(t),data=emptyData();data.events=[event()];await f.put(data);
  const [r]=await f.reminders();assert.equal(r.eventId,'e');assert.equal(r.dueAt,'2026-09-30T10:45:00.000Z');assert.equal(r.maxReminders,1);assert.equal(r.strong,false);
  f.advance(45*60000);await f.runWorker();assert.equal((await f.get()).data.notices.length,1);
  await f.put((await f.get()).data);f.advance(5*60000);await f.runWorker();
  assert.equal((await f.get()).data.notices.length,1);assert.equal((await f.reminders())[0].id,r.id);
});
test('custom strong reminder defaults repeat, ACK stops and unchanged writes keep progress',async t=>{
  const f=await fixture(t),data=emptyData();data.events=[event()];data.preferences={reminderMinutes:30,reminderInterval:2,maxReminders:3,strongReminder:true};await f.put(data);
  const [r]=await f.reminders();assert.equal(r.dueAt,'2026-09-30T10:30:00.000Z');assert.equal(r.intervalMinutes,2);assert.equal(r.maxReminders,3);assert.equal(r.strong,true);
  f.advance(30*60000);await f.runWorker();let w=await f.get();w.data.events[0].title='Renamed';w.data.preferences.themeMode='dark';await f.put(w.data);
  assert.equal((await f.reminders())[0].sentCount,1);assert.equal((await f.reminders())[0].id,r.id);assert.equal((await f.reminders())[0].title,'Renamed');
  f.advance(2*60000);await f.runWorker();assert.equal((await f.get()).data.notices.length,2);
  await f.call('POST',`/reminders/${r.id}/ack`,{});await f.put((await f.get()).data);f.advance(2*60000);await f.runWorker();assert.equal((await f.get()).data.notices.length,2);
});
test('schedule and preference changes replace one event reminder while preserving manual reminders',async t=>{
  const f=await fixture(t),data=emptyData();data.events=[event()];data.tasks=[{id:'t',title:'Task'}];await f.put(data);
  const manual=(await f.call('POST','/reminders',{taskId:'t',title:'Manual',dueAt:'2026-09-30T10:55:00Z'})).json().reminder;
  const first=(await f.reminders()).find(r=>r.eventId==='e');data.events[0].start='2026-09-30T11:30:00Z';await f.put(data);
  let rows=await f.reminders();assert.equal(rows.length,2);assert.ok(rows.some(r=>r.id===manual.id));assert.equal(rows.find(r=>r.eventId==='e').dueAt,'2026-09-30T11:15:00.000Z');assert.notEqual(rows.find(r=>r.eventId==='e').id,first.id);
  data.preferences.reminderMinutes=5;await f.put(data);rows=await f.reminders();assert.equal(rows.length,2);assert.equal(rows.find(r=>r.eventId==='e').dueAt,'2026-09-30T11:25:00.000Z');
});
test('deleted, completed and completed-task events stop without affecting other events',async t=>{
  const f=await fixture(t),data=emptyData();data.tasks=[{id:'t',title:'Task'}];data.events=[event('deleted'),event('completed'),{...event('task'),taskId:'t'},event('keep')];await f.put(data);
  data.events[0].deletedAt='2026-09-30T10:01:00Z';data.events[1].completed=true;data.tasks[0].status='done';await f.put(data);
  assert.deepEqual((await f.reminders()).map(r=>r.eventId),['keep']);f.advance(45*60000);await f.runWorker();assert.equal((await f.get()).data.notices.length,1);
});
test('past events are ignored and missed lead time does not requeue on subsequent sync',async t=>{
  const f=await fixture(t),data=emptyData();data.events=[{...event('past'),start:'2026-09-30T08:00:00Z',end:'2026-09-30T09:00:00Z'},{...event('soon'),start:'2026-09-30T10:05:00Z'}];await f.put(data);
  assert.equal((await f.reminders()).length,1);assert.equal((await f.reminders())[0].dueAt,'2026-09-30T10:00:00.000Z');await f.runWorker();await f.put((await f.get()).data);await f.runWorker();assert.equal((await f.get()).data.notices.length,1);
});
test('independent event rules retain progress and absolute times across replans',async t=>{
  const f=await fixture(t),data=emptyData();data.events=[{...event(),reminderRules:[{leadMinutes:30},{dueAt:'2026-09-30T10:50:00Z'},{leadMinutes:5}]}];await f.put(data);
  let rows=await f.reminders();assert.equal(rows.length,3);const absolute=rows.find(r=>r.ruleKey.startsWith('at:')),relative=rows.find(r=>r.ruleKey==='lead:30');assert.equal(relative.dueAt,'2026-09-30T10:30:00.000Z');
  f.advance(30*60000);await f.runWorker();assert.equal((await f.reminders()).find(r=>r.id===relative.id).sentCount,1);
  data.events[0].reminderRules.reverse();await f.put(data);assert.equal((await f.reminders()).find(r=>r.id===relative.id).sentCount,1);
  data.events[0].start='2026-09-30T11:30:00Z';await f.put(data);rows=await f.reminders();assert.equal(rows.length,3);assert.equal(rows.find(r=>r.ruleKey.startsWith('at:')).id,absolute.id);assert.equal(rows.find(r=>r.ruleKey==='lead:30').dueAt,'2026-09-30T11:00:00.000Z');
  data.events[0].reminderRules=[];await f.put(data);assert.equal((await f.reminders()).length,0);
});
test('rules reject malformed and duplicate entries and notifications carry destination ids',async t=>{
 const f=await fixture(t),data=emptyData();data.projects=[{id:'p',title:'Project'}];data.tasks=[{id:'t',title:'Task',projectId:'p'}];data.events=[{...event(),projectId:'p',taskId:'t',reminderRules:[{leadMinutes:0}]}];
 for(const rules of [[{leadMinutes:5,dueAt:'2026-09-30T10:50:00Z'}],[{leadMinutes:-1}],[{leadMinutes:5},{leadMinutes:5}],Array.from({length:11},(_,i)=>({leadMinutes:i}))]){data.events[0].reminderRules=rules;const r=await f.call('PUT','/workspace',{baseVersion:0,data});assert.equal(r.statusCode,400,r.body);}
 data.events[0].reminderRules=[{leadMinutes:0}];await f.put(data);f.advance(60*60000);await f.runWorker();const n=(await f.get()).data.notices[0];assert.equal(n.type,'reminder');assert.equal(n.eventId,'e');assert.equal(n.projectId,'p');assert.equal(n.taskId,'t');assert.equal(n.nodeId,null);
});
test('null rules inherit event lead override and manual associated reminders survive rule changes',async t=>{const f=await fixture(t),data=emptyData();data.events=[{...event(),reminderRules:null,reminderLeadMinutes:25}];data.preferences.courseReminderLeadMinutes=5;await f.put(data);let rows=await f.reminders();assert.equal(rows[0].dueAt,'2026-09-30T10:35:00.000Z');const uid=f.db.prepare('SELECT id FROM users').get().id;f.db.prepare('INSERT INTO reminders(id,user_id,event_id,due,interval_ms,max_count,strong,title,channel) VALUES(?,?,?,?,?,?,?,?,?)').run('independent',uid,'e',Date.parse('2026-09-30T10:40:00Z'),60000,1,0,'Independent','in_app');data.events[0].reminderRules=[{leadMinutes:10}];await f.put(data);rows=await f.reminders();assert.equal(rows.length,2);assert.ok(rows.some(r=>r.id==='independent'&&r.ruleKey===null));data.events[0].reminderRules=[];await f.put(data);assert.deepEqual((await f.reminders()).map(r=>r.id),['independent']);});
test('event overrides task overrides global strong settings and manual task defaults follow task',async t=>{const f=await fixture(t),data=emptyData();data.preferences={strongReminder:false,reminderInterval:5,maxReminders:3};data.tasks=[{id:'t',title:'Task',strongReminder:true,reminderInterval:2,maxReminders:4}];data.events=[{...event('inherit'),taskId:'t'},{...event('override'),taskId:'t',strongReminder:false,reminderInterval:1,maxReminders:2}];await f.put(data);let rows=await f.reminders();assert.equal(rows.find(r=>r.eventId==='inherit').maxReminders,4);assert.equal(rows.find(r=>r.eventId==='inherit').intervalMinutes,2);assert.equal(rows.find(r=>r.eventId==='override').maxReminders,1);assert.equal(rows.find(r=>r.eventId==='override').strong,false);const manual=await f.call('POST','/reminders',{taskId:'t',title:'Manual',dueAt:'2026-09-30T10:50:00Z'});assert.equal(manual.statusCode,200,manual.body);assert.equal(manual.json().reminder.maxReminders,4);assert.equal(manual.json().reminder.intervalMinutes,2);assert.equal(manual.json().reminder.strong,true);data.tasks[0].maxReminders=51;assert.equal((await f.call('PUT','/workspace',{baseVersion:(await f.get()).version,data})).statusCode,400);});
test('deadline reminder persists once, ACK ends strong chain and completion removes pending deadline',async t=>{const f=await fixture(t),data=emptyData();data.tasks=[{id:'t',title:'Deadline task',deadline:'2026-09-30T10:05:00Z',strongReminder:true,reminderInterval:1,maxReminders:2},{id:'later',title:'Later',deadline:'2026-09-30T11:00:00Z'}];await f.put(data);const initial=(await f.reminders()).find(r=>r.taskId==='t');assert.equal(initial.ruleKey,'deadline');f.advance(5*60000);await f.runWorker();assert.equal((await f.get()).data.notices.length,1);assert.equal((await f.get()).data.notices[0].taskId,'t');await f.call('POST',`/reminders/${initial.id}/ack`,{});f.advance(60000);await f.runWorker();assert.equal((await f.get()).data.notices.length,1);const w=await f.get();w.data.tasks[1].status='done';await f.put(w.data);assert.ok(!(await f.reminders()).some(r=>r.taskId==='later'));f.advance(86400000);await f.runWorker();assert.equal((await f.get()).data.notices.length,1);assert.equal((await f.reminders()).find(r=>r.taskId==='t').id,initial.id);});
test('overdue ordinary task sends once and strong task stops at maximum across days',async t=>{const f=await fixture(t),data=emptyData();data.tasks=[{id:'ordinary',title:'Ordinary',deadline:'2026-09-30T09:00:00Z',strongReminder:null,reminderInterval:null,maxReminders:null},{id:'strong',title:'Strong',deadline:'2026-09-30T09:00:00Z',strongReminder:true,reminderInterval:1,maxReminders:2}];await f.put(data);await f.runWorker();f.advance(60000);await f.runWorker();f.advance(86400000);await f.runWorker();await f.put((await f.get()).data);await f.runWorker();const notices=(await f.get()).data.notices;assert.equal(notices.filter(n=>n.taskId==='ordinary').length,1);assert.equal(notices.filter(n=>n.taskId==='strong').length,2);const rows=await f.reminders();assert.equal(rows.find(r=>r.taskId==='strong').sentCount,2);assert.equal(rows.find(r=>r.taskId==='ordinary').sentCount,1);});
test('old database gains event association without altering manual reminders',async()=>{
  const dir=mkdtempSync(join(tmpdir(),'flowday-event-migration-')),path=join(dir,'data.sqlite');let ctx;
  try {
    const db=new DatabaseSync(path);
    db.exec('CREATE TABLE reminders(id TEXT PRIMARY KEY,user_id TEXT NOT NULL,task_id TEXT,due INTEGER NOT NULL,interval_ms INTEGER NOT NULL,max_count INTEGER NOT NULL,sent INTEGER NOT NULL DEFAULT 0,acknowledged INTEGER NOT NULL DEFAULT 0,strong INTEGER NOT NULL,title TEXT NOT NULL,channel TEXT NOT NULL,last_error TEXT)');
    db.prepare('INSERT INTO reminders(id,user_id,due,interval_ms,max_count,strong,title,channel) VALUES(?,?,?,?,?,?,?,?)').run('manual','u',1,60000,3,1,'Existing','in_app');db.close();
    ctx=await createApp({databasePath:path,worker:false,env:{}});const row=ctx.db.prepare('SELECT * FROM reminders').get();assert.equal(row.id,'manual');assert.equal(row.event_id,null);assert.equal(row.max_count,3);await ctx.app.close();ctx=null;
    ctx=await createApp({databasePath:path,worker:false,env:{}});assert.equal(ctx.db.prepare('SELECT COUNT(*) AS n FROM reminders').get().n,1);
  } finally {if(ctx)await ctx.app.close();rmSync(dir,{recursive:true,force:true});}
});
