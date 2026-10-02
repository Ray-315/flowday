import test from 'node:test';
import assert from 'node:assert/strict';
import {createApp} from './helpers/verified_app.js';
async function fixture(t) {
  const ctx=await createApp({databasePath:':memory:',worker:false,env:{}});
  t.after(()=>ctx.app.close());
  const call=(method,url,body,token)=>ctx.app.inject({method,url:'/api/v1'+url,payload:body,headers:token?{authorization:'Bearer '+token}:{}});
  const register=async(email)=>(await call('POST','/auth/register',{email,password:'password-12345',displayName:'Name'})).json();
  return {...ctx,call,register};
}
test('profile and session operations are authenticated and scoped to owner',async t=>{
  const f=await fixture(t),a=await f.register('a@example.com'),b=await f.register('b@example.com');
  assert.equal((await f.call('PUT','/auth/profile',{displayName:'Changed'})).statusCode,401);
  assert.equal((await f.call('PUT','/auth/profile',{displayName:'Changed',userId:b.user.id},a.token)).statusCode,400);
  assert.equal((await f.call('PUT','/auth/profile',{displayName:' Changed '},a.token)).json().user.displayName,'Changed');
  assert.equal((await f.call('GET','/auth/me',undefined,b.token)).json().user.displayName,'Name');
  const other=(await f.call('POST','/auth/login',{email:'a@example.com',password:'password-12345'})).json();
  const sessions=(await f.call('GET','/auth/sessions',undefined,a.token)).json().sessions;
  assert.equal(sessions.length,2);assert.equal(sessions.filter(s=>s.current).length,1);
  assert.ok(sessions.every(s=>!('token_hash' in s)&&!('token' in s)));
  await f.call('POST','/auth/sessions/revoke-others',undefined,a.token);
  assert.equal((await f.call('GET','/auth/me',undefined,other.token)).statusCode,401);
  assert.equal((await f.call('GET','/auth/me',undefined,b.token)).statusCode,200);
});
test('password change validates old password and revokes other sessions only',async t=>{
  const f=await fixture(t),a=await f.register('a@example.com'),b=await f.register('b@example.com');
  const other=(await f.call('POST','/auth/login',{email:'a@example.com',password:'password-12345'})).json();
  assert.equal((await f.call('POST','/auth/password',{currentPassword:'wrong',newPassword:'password-67890'},a.token)).statusCode,401);
  assert.equal((await f.call('POST','/auth/password',{currentPassword:'password-12345',newPassword:'short'},a.token)).statusCode,400);
  assert.equal((await f.call('POST','/auth/password',{currentPassword:'password-12345',newPassword:'password-67890'},a.token)).statusCode,200);
  assert.equal((await f.call('GET','/auth/me',undefined,a.token)).statusCode,200);
  assert.equal((await f.call('GET','/auth/me',undefined,other.token)).statusCode,401);
  assert.equal((await f.call('GET','/auth/me',undefined,b.token)).statusCode,200);
  assert.equal((await f.call('POST','/auth/login',{email:'a@example.com',password:'password-12345'})).statusCode,401);
  assert.equal((await f.call('POST','/auth/login',{email:'a@example.com',password:'password-67890'})).statusCode,200);
});
test('account deletion requires password and confirmation then deletes owned records atomically',async t=>{
  const f=await fixture(t),a=await f.register('a@example.com'),b=await f.register('b@example.com');
  await f.call('POST','/backups',{},a.token);
  await f.call('POST','/reminders',{dueAt:new Date().toISOString(),title:'Private'},a.token);
  f.db.prepare('INSERT INTO previews VALUES(?,?,?,?,NULL)').run('preview',a.user.id,Date.now()+10000,'{}');
  assert.equal((await f.call('POST','/auth/delete',{password:'password-12345',confirmation:'DELETE'})).statusCode,401);
  assert.equal((await f.call('POST','/auth/delete',{password:'wrong',confirmation:'DELETE'},a.token)).statusCode,401);
  assert.equal((await f.call('POST','/auth/delete',{password:'password-12345'},a.token)).statusCode,400);
  assert.equal((await f.call('POST','/auth/delete',{password:'password-12345',confirmation:'DELETE'},a.token)).statusCode,204);
  for(const table of ['sessions','workspaces','reminders','backups','previews','audit']) assert.equal(f.db.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE user_id=?`).get(a.user.id).n,0);
  assert.equal((await f.call('GET','/auth/me',undefined,a.token)).statusCode,401);
  assert.equal((await f.call('GET','/workspace',undefined,b.token)).statusCode,200);
});
test('all account management routes reject invalid sessions',async t=>{
  const f=await fixture(t);
  for(const [method,path,body] of [
    ['PUT','/auth/profile',{displayName:'Name'}],
    ['POST','/auth/password',{currentPassword:'password-12345',newPassword:'password-67890'}],
    ['GET','/auth/sessions',undefined],
    ['POST','/auth/sessions/revoke-others',undefined],
    ['POST','/auth/delete',{password:'password-12345',confirmation:'DELETE'}],
  ]) assert.equal((await f.call(method,path,body,'a'.repeat(64))).statusCode,401,path);
});
test('account deletion rolls back all data when any deletion fails',async t=>{
  const f=await fixture(t),a=await f.register('a@example.com');
  await f.call('POST','/backups',{},a.token);
  f.db.exec("CREATE TRIGGER reject_user_delete BEFORE DELETE ON users BEGIN SELECT RAISE(ABORT, 'test failure'); END");
  assert.equal((await f.call('POST','/auth/delete',{password:'password-12345',confirmation:'DELETE'},a.token)).statusCode,500);
  assert.equal((await f.call('GET','/auth/me',undefined,a.token)).statusCode,200);
  assert.equal((await f.call('GET','/workspace',undefined,a.token)).statusCode,200);
  assert.equal((await f.call('GET','/backups',undefined,a.token)).json().backups.length,1);
});
