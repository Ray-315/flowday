import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync,readdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {createApp} from './helpers/verified_app.js';
test('daily database snapshot is readable, includes users, and does not repeat',async t=>{const dir=mkdtempSync(join(tmpdir(),'flowday-snapshot-'));const f=await createApp({databasePath:join(dir,'live.sqlite'),worker:false,env:{SNAPSHOT_DIR:join(dir,'snapshots')}});t.after(async()=>{await f.app.close();rmSync(dir,{recursive:true,force:true});});await f.app.inject({method:'POST',url:'/api/v1/auth/register',payload:{email:'snapshot@example.com',password:'long-password-123',displayName:'A'}});await f.runWorker();const files=readdirSync(join(dir,'snapshots'));assert.equal(files.length,1);const db=new DatabaseSync(join(dir,'snapshots',files[0]));assert.equal(db.prepare('SELECT count(*) AS count FROM users').get().count,1);db.close();await f.runWorker();assert.equal(readdirSync(join(dir,'snapshots')).length,1);});
