import assert from 'node:assert/strict';
import {createApp as createProductionApp} from '../../src/app.js';

// Existing domain tests provision accounts through the real verification route.
export async function createApp(options={}) {
  const codes=new Map();
  const env={...options.env,ACTION_SIGNING_KEY:options.env?.ACTION_SIGNING_KEY??'synthetic-registration-test-key-24'};
  const f=await createProductionApp({...options,env,sendRegistrationEmail:async({email,code})=>{codes.set(email,code);}});
  const inject=f.app.inject.bind(f.app);
  f.app.inject=async request=>{
    if(request.method==='POST'&&request.url==='/api/v1/auth/register'&&request.payload&&!request.payload.verificationCode){
      const email=request.payload.email.trim().toLowerCase();
      const sent=await inject({method:'POST',url:'/api/v1/auth/registration-code',payload:{email}});
      assert.equal(sent.statusCode,200,sent.body);
      request={...request,payload:{...request.payload,verificationCode:codes.get(email)}};
    }
    return inject(request);
  };
  return f;
}
