import {randomBytes,createCipheriv,createDecipheriv} from 'node:crypto';
import {ApiError} from './validation.js';
export function credentialCodec(env){
 const key=()=>{if(!/^[a-fA-F0-9]{64}$/.test(env.INTEGRATION_ENCRYPTION_KEY??''))throw new ApiError(503,'ENCRYPTION_NOT_CONFIGURED','集成加密密钥尚未配置');return Buffer.from(env.INTEGRATION_ENCRYPTION_KEY,'hex');};
 return {seal(value){const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key(),iv),data=Buffer.concat([cipher.update(JSON.stringify(value),'utf8'),cipher.final()]);return Buffer.concat([iv,cipher.getAuthTag(),data]).toString('base64');},open(value){const bytes=Buffer.from(value,'base64'),cipher=createDecipheriv('aes-256-gcm',key(),bytes.subarray(0,12));cipher.setAuthTag(bytes.subarray(12,28));return JSON.parse(Buffer.concat([cipher.update(bytes.subarray(28)),cipher.final()]).toString('utf8'));}};
}
