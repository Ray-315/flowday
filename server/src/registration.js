import {randomInt, randomUUID, createHmac, timingSafeEqual} from 'node:crypto';
import {ApiError, object} from './validation.js';

const emailValid=v=>typeof v==='string'&&v.length<=254&&/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v.trim());
const codeValid=v=>typeof v==='string'&&/^\d{6}$/.test(v);

function microsoftMailer(env, fetcher) {
  const {MAIL_FROM, MICROSOFT_TENANT_ID, MICROSOFT_CLIENT_ID, MICROSOFT_CLIENT_SECRET}=env;
  if(!emailValid(MAIL_FROM)||!MICROSOFT_TENANT_ID||!MICROSOFT_CLIENT_ID||!MICROSOFT_CLIENT_SECRET)return null;
  let token,expires=0;
  return async ({email,code})=>{
    if(!token||expires<=Date.now()){
      const response=await fetcher(`https://login.microsoftonline.com/${encodeURIComponent(MICROSOFT_TENANT_ID)}/oauth2/v2.0/token`,{
        method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),headers:{'Content-Type':'application/x-www-form-urlencoded'},
        body:new URLSearchParams({client_id:MICROSOFT_CLIENT_ID,client_secret:MICROSOFT_CLIENT_SECRET,scope:'https://graph.microsoft.com/.default',grant_type:'client_credentials'}).toString()
      });
      if(!response.ok)throw new Error('Mail authorization failed');
      const data=await response.json();
      if(typeof data.access_token!=='string'||!data.access_token)throw new Error('Invalid mail authorization');
      token=data.access_token;expires=Date.now()+Math.max(0,(Number(data.expires_in)||0)-60)*1000;
    }
    const response=await fetcher(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(MAIL_FROM.trim())}/sendMail`,{
      method:'POST',redirect:'error',signal:AbortSignal.timeout(10000),headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
      body:JSON.stringify({message:{subject:'FlowDay 注册验证码',body:{contentType:'Text',content:`你的 FlowDay 注册验证码是：${code}。验证码在 10 分钟内有效。`},toRecipients:[{emailAddress:{address:email}}]},saveToSentItems:false})
    });
    if(response.status===401){token=null;expires=0;}
    if(response.status!==202)throw new Error('Mail delivery failed');
  };
}

export function registerRegistration(app,{db,env,now,tx,sendRegistrationEmail,mailFetch}) {
  db.exec(`CREATE TABLE IF NOT EXISTS registration_codes(email TEXT PRIMARY KEY,digest TEXT NOT NULL,nonce TEXT NOT NULL,created INTEGER NOT NULL,expires INTEGER NOT NULL,attempts INTEGER NOT NULL,state TEXT NOT NULL,window_start INTEGER NOT NULL,sends INTEGER NOT NULL)`);
  const secret=env.ACTION_SIGNING_KEY;
  const send=sendRegistrationEmail??microsoftMailer(env,mailFetch??globalThis.fetch);
  const digest=(email,nonce,code)=>createHmac('sha256',secret).update(JSON.stringify([email,nonce,code])).digest('hex');
  const matches=(row,email,code)=>typeof secret==='string'&&secret.length>=24&&row&&row.state==='ready'&&row.expires>now()&&row.attempts<5&&timingSafeEqual(Buffer.from(row.digest,'hex'),Buffer.from(digest(email,row.nonce,code),'hex'));
  const invalid=()=>new ApiError(400,'INVALID_REGISTRATION_CODE','验证码无效或已过期，请重新获取');
  app.post('/api/v1/auth/registration-code',{config:{rateLimit:{max:30,timeWindow:'15 minutes'}}},async req=>{
    object(req.body,{email:emailValid},['email']);
    if(!send||typeof secret!=='string'||secret.length<24)throw new ApiError(503,'MAIL_NOT_CONFIGURED','注册邮件服务尚未配置');
    const email=req.body.email.trim().toLowerCase();
    if(db.prepare('SELECT id FROM users WHERE email=?').get(email))throw new ApiError(409,'EMAIL_EXISTS','此邮箱已注册');
    const code=randomInt(0,1000000).toString().padStart(6,'0'),nonce=randomUUID();
    tx(()=>{
      db.prepare('DELETE FROM registration_codes WHERE window_start<=? AND expires<=?').run(now()-3600000,now());
      const row=db.prepare('SELECT * FROM registration_codes WHERE email=?').get(email);
      if(row&&row.created>now()-60000)throw new ApiError(429,'CODE_COOLDOWN','请稍后再获取验证码');
      const sameWindow=row&&row.window_start>now()-3600000;
      if(sameWindow&&row.sends>=5)throw new ApiError(429,'CODE_SEND_LIMIT','验证码发送次数过多，请稍后重试');
      db.prepare('INSERT OR REPLACE INTO registration_codes VALUES(?,?,?,?,?,0,?,?,?)').run(email,digest(email,nonce,code),nonce,now(),now()+600000,'pending',sameWindow?row.window_start:now(),sameWindow?row.sends+1:1);
    });
    try {await send({email,code});}
    catch {db.prepare("UPDATE registration_codes SET state='failed' WHERE email=? AND nonce=?").run(email,nonce);throw new ApiError(502,'MAIL_DELIVERY_FAILED','验证码发送失败，请稍后重试');}
    db.prepare("UPDATE registration_codes SET state='ready' WHERE email=? AND nonce=? AND state='pending'").run(email,nonce);
    return {sent:true,retryAfterSeconds:60};
  });
  return {
    emailValid,codeValid,
    verify(email,code){
      const row=db.prepare('SELECT * FROM registration_codes WHERE email=?').get(email);
      if(!matches(row,email,code)){
        if(row)db.prepare('UPDATE registration_codes SET attempts=attempts+1 WHERE email=? AND nonce=? AND attempts<5').run(email,row.nonce);
        throw invalid();
      }
      return row.nonce;
    },
    consume(email,code,nonce){
      const row=db.prepare('SELECT * FROM registration_codes WHERE email=?').get(email);
      if(row?.nonce!==nonce||!matches(row,email,code))throw invalid();
      db.prepare('DELETE FROM registration_codes WHERE email=?').run(email);
    }
  };
}
