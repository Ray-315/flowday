import test from 'node:test';
import assert from 'node:assert/strict';
import {createApp} from '../src/app.js';

async function fixture(t, options={}) {
  let time=Date.now(); const messages=[];
  const f=await createApp({databasePath:':memory:',worker:false,env:{ACTION_SIGNING_KEY:'test-key-for-registration-at-least-24'},now:()=>time,sendRegistrationEmail:async message=>{messages.push(message);},...options});
  t.after(()=>f.app.close());
  const call=(path,payload)=>f.app.inject({method:'POST',url:'/api/v1/auth/'+path,payload});
  const register=(email='a@example.com',verificationCode)=>call('register',{email,password:'password-12345',displayName:'A',...(verificationCode===undefined?{}:{verificationCode})});
  return {...f,messages,call,register,advance:ms=>{time+=ms;}};
}
test('registration requires a delivered email code, normalizes email and consumes it once',async t=>{
  const f=await fixture(t); assert.equal((await f.register()).statusCode,400);
  const r=await f.call('registration-code',{email:' A@example.com '}); assert.equal(r.statusCode,200,r.body);
  assert.equal(f.messages[0].email,'a@example.com'); assert.match(f.messages[0].code,/^\d{6}$/);
  assert.equal(r.body.includes(f.messages[0].code),false);
  const row=f.db.prepare('SELECT * FROM registration_codes').get(); assert.equal(Object.values(row).includes(f.messages[0].code),false);
  assert.equal((await f.register('a@example.com',f.messages[0].code)).statusCode,201);
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM registration_codes').get().n,0);
});
test('codes are bound to email and expire after ten minutes',async t=>{
  const f=await fixture(t); await f.call('registration-code',{email:'a@example.com'});
  assert.equal((await f.register('b@example.com',f.messages[0].code)).statusCode,400);
  f.advance(600001); assert.equal((await f.register('a@example.com',f.messages[0].code)).statusCode,400);
  assert.equal(f.db.prepare('SELECT COUNT(*) AS n FROM users').get().n,0);
});
test('resend cooldown and five-attempt limit invalidate old codes',async t=>{
  const f=await fixture(t); await f.call('registration-code',{email:'a@example.com'});
  assert.equal((await f.call('registration-code',{email:'a@example.com'})).statusCode,429);
  const code=f.messages[0].code,wrong=code==='000000'?'111111':'000000';
  for(let i=0;i<5;i++)assert.equal((await f.register('a@example.com',wrong)).statusCode,400);
  assert.equal((await f.register('a@example.com',code)).statusCode,400);
  f.advance(60000); await f.call('registration-code',{email:'a@example.com'});
  assert.equal((await f.register('a@example.com',f.messages[1].code)).statusCode,201);
});
test('mail failure and missing configuration never allow registration',async t=>{
  const f=await fixture(t,{sendRegistrationEmail:async()=>{throw new Error('private credential');}});
  const r=await f.call('registration-code',{email:'a@example.com'}); assert.equal(r.statusCode,502); assert.equal(r.body.includes('private credential'),false);
  assert.equal((await f.register('a@example.com','123456')).statusCode,400);
  const g=await fixture(t,{env:{},sendRegistrationEmail:undefined});
  assert.equal((await g.call('registration-code',{email:'a@example.com'})).statusCode,503);
  assert.equal((await g.register()).statusCode,400);
});
test('concurrent registration cannot consume one code twice',async t=>{
  const f=await fixture(t); await f.call('registration-code',{email:'a@example.com'});
  const responses=await Promise.all([f.register('a@example.com',f.messages[0].code),f.register('a@example.com',f.messages[0].code)]);
  assert.equal(responses.filter(r=>r.statusCode===201).length,1);
});
test('email hourly limit survives cooldown and concurrent requests only send once',async t=>{
  const f=await fixture(t);
  const results=await Promise.all([f.call('registration-code',{email:'a@example.com'}),f.call('registration-code',{email:'a@example.com'})]);
  assert.deepEqual(results.map(r=>r.statusCode).sort(),[200,429]);assert.equal(f.messages.length,1);
  for(let i=0;i<4;i++){f.advance(60000);assert.equal((await f.call('registration-code',{email:'a@example.com'})).statusCode,200);}
  f.advance(60000);assert.equal((await f.call('registration-code',{email:'a@example.com'})).statusCode,429);
  f.advance(3600000);assert.equal((await f.call('registration-code',{email:'a@example.com'})).statusCode,200);
});
