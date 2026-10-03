import type { Workspace } from './workspace';
export function zoneFor(data:Workspace):string{
  const zone=typeof data.preferences.timezone==='string'&&data.preferences.timezone!=='system'?data.preferences.timezone:Intl.DateTimeFormat().resolvedOptions().timeZone;
  try {new Intl.DateTimeFormat('en',{timeZone:zone});return zone;}catch{return 'UTC';}
}
function parts(date:Date,zone:string){
  const list=new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(date);
  return Object.fromEntries(list.map(part=>[part.type,part.value]));
}
export function dayInZone(date:Date,zone:string){const value=parts(date,zone);return `${value.year}-${value.month}-${value.day}`;}
export function inputInZone(iso:string,zone:string){const value=parts(new Date(iso),zone);return `${value.year}-${value.month}-${value.day}T${value.hour}:${value.minute}`;}
export function instantInZone(wall:string,zone:string):string{
  if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?$/.test(wall))throw new Error('日期时间无效');
  const target=Date.parse(`${wall.length===16?wall+':00':wall}Z`);
  if(!Number.isFinite(target))throw new Error('日期时间无效');
  let guess=target;
  for(let index=0;index<5;index++){
    const value=parts(new Date(guess),zone);
    const shown=Date.parse(`${value.year}-${value.month}-${value.day}T${value.hour}:${value.minute}:${value.second}Z`);
    const offset=target-shown;if(offset===0)return new Date(guess).toISOString();guess+=offset;
  }
  throw new Error('该时间在所选时区不存在，请调整时间');
}
export function dayBounds(day:string,zone:string){
  const tomorrow=new Date(`${day}T12:00:00Z`);tomorrow.setUTCDate(tomorrow.getUTCDate()+1);
  return {start:Date.parse(instantInZone(`${day}T00:00`,zone)),end:Date.parse(instantInZone(`${tomorrow.toISOString().slice(0,10)}T00:00`,zone))};
}
