import {randomUUID} from 'node:crypto';
import {ApiError,check,object,date,validateData} from './validation.js';
const text=v=>typeof v==='string'&&v.length>0&&v.length<=2000;
const base64=v=>typeof v==='string'&&v.length<=1400000&&/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(v);
const media=v=>typeof v==='string'&&/^[\w.+-]+\/[\w.+-]+$/.test(v);
const url=v=>{try{return typeof v==='string'&&['https:','http:'].includes(new URL(v).protocol);}catch{return false;}};
const nullable=fn=>v=>v===null||fn(v);
export function registerAttachments({app,db,auth,now,workspace,audit,tx,cas,backup}){
 db.exec(`CREATE TABLE IF NOT EXISTS attachments(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),owner_type TEXT NOT NULL,owner_id TEXT NOT NULL,kind TEXT NOT NULL,name TEXT NOT NULL,media_type TEXT,content BLOB,url TEXT,markdown TEXT,created INTEGER NOT NULL,deleted INTEGER);
 CREATE TABLE IF NOT EXISTS backup_files(backup_id TEXT PRIMARY KEY REFERENCES backups(id) ON DELETE CASCADE,user_id TEXT NOT NULL REFERENCES users(id),data TEXT NOT NULL);`);
 const metadata=r=>({id:r.id,ownerType:r.owner_type,ownerId:r.owner_id,kind:r.kind,name:r.name,mediaType:r.media_type,size:r.content?.length??0,url:r.url,markdown:r.markdown,createdAt:new Date(r.created).toISOString(),deletedAt:r.deleted?new Date(r.deleted).toISOString():null});
 const rows=uid=>db.prepare('SELECT * FROM attachments WHERE user_id=?').all(uid);
 const archived=uid=>rows(uid).map(r=>({...metadata(r),contentBase64:r.content?Buffer.from(r.content).toString('base64'):null}));
 const owner=(uid,type,id)=>{const key={task:'tasks',project:'projects'}[type];check(key&&workspace(uid).data[key].some(v=>v.id===id&&!v.deletedAt),'附件所属对象不存在');};
 app.get('/api/v1/attachments',{preHandler:auth},async req=>({attachments:rows(req.uid).filter(r=>!r.deleted).map(metadata)}));
 app.post('/api/v1/attachments',{preHandler:auth},async(req,reply)=>{
  object(req.body,{ownerType:v=>['task','project'].includes(v),ownerId:text,kind:v=>['file','url','markdown'].includes(v),name:v=>text(v)&&v.length<=200,mediaType:v=>typeof v==='string'&&/^[\w.+-]+\/[\w.+-]+$/.test(v),contentBase64:v=>typeof v==='string'&&v.length<=1400000&&/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(v),url:v=>{try{return ['https:','http:'].includes(new URL(v).protocol);}catch{return false;}},markdown:v=>typeof v==='string'&&v.length<=100000},['ownerType','ownerId','kind','name']);const b=req.body;owner(req.uid,b.ownerType,b.ownerId);const content=b.kind==='file'?Buffer.from(b.contentBase64??'','base64'):null;
  check(b.kind!=='file'||(b.contentBase64!==undefined&&b.mediaType!==undefined&&content.length<=1024*1024),'文件最大1MiB');check(b.kind!=='url'||b.url!==undefined);check(b.kind!=='markdown'||b.markdown!==undefined);
  const used=db.prepare('SELECT COALESCE(SUM(LENGTH(content)),0) AS size FROM attachments WHERE user_id=?').get(req.uid).size;check(used+(content?.length??0)<=100*1024*1024,'附件容量已达100MiB');const id=randomUUID();db.prepare('INSERT INTO attachments VALUES(?,?,?,?,?,?,?,?,?,?,?,NULL)').run(id,req.uid,b.ownerType,b.ownerId,b.kind,b.name,b.mediaType??null,content,b.kind==='url'?b.url:null,b.kind==='markdown'?b.markdown:null,now());audit(req.uid,'attachment.create');return reply.code(201).send({attachment:metadata(db.prepare('SELECT * FROM attachments WHERE id=?').get(id))});
 });
 const get=(uid,id)=>{const row=db.prepare('SELECT * FROM attachments WHERE id=? AND user_id=? AND deleted IS NULL').get(id,uid);if(!row)throw new ApiError(404,'NOT_FOUND','附件不存在');return row;};
 app.get('/api/v1/attachments/:id/download',{preHandler:auth},async(req,reply)=>{const row=get(req.uid,req.params.id);check(row.kind==='file','附件不是文件');return reply.type(row.media_type).header('X-Content-Type-Options','nosniff').header('Cache-Control','private, no-store').header('Content-Disposition',"attachment; filename*=UTF-8''"+encodeURIComponent(row.name)).send(Buffer.from(row.content));});
 app.post('/api/v1/attachments/:id/delete',{preHandler:auth},async req=>{get(req.uid,req.params.id);db.prepare('UPDATE attachments SET deleted=? WHERE id=?').run(now(),req.params.id);audit(req.uid,'attachment.delete');return {deleted:true};});
 app.post('/api/v1/attachments/:id/restore',{preHandler:auth},async req=>{const row=db.prepare('SELECT * FROM attachments WHERE id=? AND user_id=?').get(req.params.id,req.uid);if(!row)throw new ApiError(404,'NOT_FOUND','附件不存在');owner(req.uid,row.owner_type,row.owner_id);db.prepare('UPDATE attachments SET deleted=NULL WHERE id=?').run(row.id);return {restored:true};});
 app.get('/api/v1/export/archive',{preHandler:auth},async(req,reply)=>reply.header('Content-Disposition','attachment; filename="flowday-archive.json"').send({schemaVersion:1,workspace:workspace(req.uid).data,attachments:archived(req.uid)}));
 const replace=(uid,files)=>{db.prepare('DELETE FROM attachments WHERE user_id=?').run(uid);for(const f of files)db.prepare('INSERT INTO attachments VALUES(?,?,?,?,?,?,?,?,?,?,?,?)').run(f.id,uid,f.ownerType,f.ownerId,f.kind,f.name,f.mediaType,f.contentBase64===null?null:Buffer.from(f.contentBase64,'base64'),f.url,f.markdown,Date.parse(f.createdAt),f.deletedAt===null?null:Date.parse(f.deletedAt));};
 app.post('/api/v1/import/archive',{preHandler:auth,bodyLimit:150*1024*1024,config:{rateLimit:{max:10,timeWindow:'15 minutes'}}},async req=>{
  object(req.body,{baseVersion:v=>Number.isSafeInteger(v)&&v>=0,archive:v=>v&&typeof v==='object'&&!Array.isArray(v)},['baseVersion','archive']);
  const {baseVersion,archive}=req.body;
  object(archive,{schemaVersion:v=>v===1,workspace:v=>v&&typeof v==='object',attachments:Array.isArray},['schemaVersion','workspace','attachments']);
  validateData(archive.workspace);check(Buffer.byteLength(JSON.stringify(archive.workspace))<=2*1024*1024,'工作区最大2MiB');
  const seen=new Set();let used=0;
  for(const f of archive.attachments){
   object(f,{id:text,ownerType:v=>['task','project'].includes(v),ownerId:text,kind:v=>['file','url','markdown'].includes(v),name:v=>text(v)&&v.length<=200,mediaType:nullable(media),size:v=>Number.isSafeInteger(v)&&v>=0,url:nullable(url),markdown:nullable(v=>typeof v==='string'&&v.length<=100000),createdAt:date,deletedAt:nullable(date),contentBase64:nullable(base64)},['id','ownerType','ownerId','kind','name','mediaType','size','url','markdown','createdAt','deletedAt','contentBase64']);
   check(!seen.has(f.id),'附件标识重复');seen.add(f.id);
   check(archive.workspace[f.ownerType==='task'?'tasks':'projects'].some(v=>v.id===f.ownerId),'附件所属对象不存在');
   const content=f.contentBase64===null?null:Buffer.from(f.contentBase64,'base64');
   check(f.size===(content?.length??0),'附件大小不符');
   if(f.kind==='file')check(content!==null&&content.length<=1024*1024&&content.toString('base64')===f.contentBase64&&f.mediaType!==null&&f.url===null&&f.markdown===null,'文件格式无效或超过1MiB');
   else check(content===null&&f.size===0&&(f.kind==='url'?f.url!==null&&f.markdown===null:f.markdown!==null&&f.url===null),'附件格式无效');
   used+=f.size;check(used<=100*1024*1024,'附件容量已达100MiB');
  }
  return tx(()=>{
   for(const id of seen){const existing=db.prepare('SELECT user_id FROM attachments WHERE id=?').get(id);check(!existing||existing.user_id===req.uid,'附件标识不可用');}
   const protectionBackup=backup(req.uid,'before_import_archive');
   const version=cas(req.uid,baseVersion,archive.workspace);replace(req.uid,archive.attachments);audit(req.uid,'archive.import');
   return {version,protectionBackup,importedAttachments:archive.attachments.length};
  });
 });
 const snapshot=(id,uid)=>db.prepare('INSERT INTO backup_files VALUES(?,?,?)').run(id,uid,JSON.stringify(archived(uid)));
 const restore=(id,uid)=>{const row=db.prepare('SELECT data FROM backup_files WHERE backup_id=? AND user_id=?').get(id,uid);if(row)replace(uid,JSON.parse(row.data));};
 return {snapshot,restore,purge:()=>db.prepare('DELETE FROM attachments WHERE deleted IS NOT NULL AND deleted<?').run(now()-30*86400000)};
}
