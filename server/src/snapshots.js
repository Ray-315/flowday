import {backup} from 'node:sqlite';
import {mkdirSync,existsSync,renameSync,rmSync} from 'node:fs';
import {join,resolve} from 'node:path';
export function registerSnapshots({app,db,auth,env,now}){
 db.exec('CREATE TABLE IF NOT EXISTS snapshot_status(id INTEGER PRIMARY KEY CHECK(id=1),created INTEGER,last_error TEXT)');
 app.get('/api/v1/backups/status',{preHandler:auth},async()=>{const row=db.prepare('SELECT created,last_error FROM snapshot_status WHERE id=1').get();return {databaseSnapshot:{enabled:!!env.SNAPSHOT_DIR,lastSuccessAt:row?.created?new Date(row.created).toISOString():null,lastError:row?.last_error??null}};});
 return async()=>{
  if(!env.SNAPSHOT_DIR)return;const directory=resolve(env.SNAPSHOT_DIR),name='flowday-'+new Date(now()).toISOString().slice(0,10)+'.sqlite',target=join(directory,name),temp=target+'.partial';
  if(existsSync(target))return;
  try{mkdirSync(directory,{recursive:true,mode:0o700});await backup(db,temp);renameSync(temp,target);db.prepare('INSERT INTO snapshot_status VALUES(1,?,NULL) ON CONFLICT(id) DO UPDATE SET created=excluded.created,last_error=NULL').run(now());}
  catch{rmSync(temp,{force:true});db.prepare("INSERT INTO snapshot_status VALUES(1,NULL,'SNAPSHOT_FAILED') ON CONFLICT(id) DO UPDATE SET last_error='SNAPSHOT_FAILED'").run();}
 };
}
