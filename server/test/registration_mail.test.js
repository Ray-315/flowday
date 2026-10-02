import test from 'node:test';
import assert from 'node:assert/strict';
import {createApp} from '../src/app.js';
test('Microsoft mail uses application OAuth and never returns provider secrets',async t=>{
  const calls=[];const env={MAIL_FROM:'flowday-noreply@mtrx.pro',MICROSOFT_TENANT_ID:'test-tenant',MICROSOFT_CLIENT_ID:'test-client',MICROSOFT_CLIENT_SECRET:'synthetic-secret',ACTION_SIGNING_KEY:'synthetic-key-at-least-24-characters'};
  const f=await createApp({databasePath:':memory:',worker:false,env,mailFetch:async(url,options)=>{calls.push({url,options});return url.includes('login.microsoftonline.com')?{ok:true,json:async()=>({access_token:'synthetic-token',expires_in:3600})}:{ok:true,status:202};}});t.after(()=>f.app.close());
  const r=await f.app.inject({method:'POST',url:'/api/v1/auth/registration-code',payload:{email:'recipient@example.com'}});
  assert.equal(r.statusCode,200,r.body); assert.equal(calls.length,2);
  assert.equal(calls[0].url,'https://login.microsoftonline.com/test-tenant/oauth2/v2.0/token');
  assert.equal(new URLSearchParams(calls[0].options.body).get('scope'),'https://graph.microsoft.com/.default');
  assert.equal(calls[1].url,'https://graph.microsoft.com/v1.0/users/flowday-noreply%40mtrx.pro/sendMail');
  const message=JSON.parse(calls[1].options.body).message;assert.equal(message.toRecipients[0].emailAddress.address,'recipient@example.com');assert.match(message.body.content,/\d{6}/);
  assert.equal(r.body.includes('synthetic-'),false);
});
test('provider rejection is sanitized and never activates the emailed code',async t=>{
  const env={MAIL_FROM:'flowday-noreply@mtrx.pro',MICROSOFT_TENANT_ID:'test-tenant',MICROSOFT_CLIENT_ID:'test-client',MICROSOFT_CLIENT_SECRET:'synthetic-secret',ACTION_SIGNING_KEY:'synthetic-key-at-least-24-characters'};
  const f=await createApp({databasePath:':memory:',worker:false,env,mailFetch:async()=>({ok:false,status:401,json:async()=>({error:'secret-provider-detail'})})});t.after(()=>f.app.close());
  const r=await f.app.inject({method:'POST',url:'/api/v1/auth/registration-code',payload:{email:'a@example.com'}});
  assert.equal(r.statusCode,502);assert.equal(r.body.includes('secret'),false);
  assert.equal(f.db.prepare('SELECT state FROM registration_codes').get().state,'failed');
});
