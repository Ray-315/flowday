import { createApp } from './app.js';
const {app}=await createApp();
try { await app.listen({host:process.env.HOST??'127.0.0.1',port:Number(process.env.PORT??3108)});console.log('Flowday server listening'); }
catch { console.error('Server could not start');process.exit(1); }
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,async()=>{await app.close();process.exit(0);});
