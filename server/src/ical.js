import ICAL from 'ical.js';
import {ApiError,check} from './validation.js';
const fields=['title','start','end','allDay','location','notes','repeatRule'];
export const eventFields=event=>event?Object.fromEntries([...fields.map(k=>[k,['start','end'].includes(k)?new Date(event[k]).toISOString():event[k]??(k==='allDay'?false:k==='location'||k==='notes'?'':null)]),['deleted',!!event.deletedAt]]):null;
export const sameEvent=(a,b)=>JSON.stringify(eventFields(a))===JSON.stringify(eventFields(b));
function instant(time,zone='UTC'){
 if(time.isDate)return new Date(Date.UTC(time.year,time.month-1,time.day)).toISOString();
 if(time.zone.tzid!=='floating')return time.toJSDate().toISOString();
 const wall=Date.UTC(time.year,time.month-1,time.day,time.hour,time.minute,time.second),format=new Intl.DateTimeFormat('en-US',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'});let utc=wall;
 for(let n=0;n<3;n++){const p=Object.fromEntries(format.formatToParts(new Date(utc)).map(v=>[v.type,v.value]));utc=wall-(Date.UTC(+p.year,+p.month-1,+p.day,+p.hour,+p.minute,+p.second)-utc);}return new Date(utc).toISOString();
}
export function readCalendar(data,{now=Date.now(),timezone='UTC',wanted=[],keepSeries=false}={}){
 check(typeof data==='string'&&data.length<=1024*1024,'日历对象过大');const root=new ICAL.Component(ICAL.parse(data)),components=root.getAllSubcomponents('vevent'),result=[];
 const add=(item,start,end,key,uid)=>{if(item.component.getFirstPropertyValue('status')==='CANCELLED')return;const startIso=instant(start,item.component.getFirstProperty('dtstart')?.getParameter('tzid')??timezone),endIso=instant(end,item.component.getFirstProperty('dtend')?.getParameter('tzid')??timezone);check(Date.parse(endIso)>Date.parse(startIso),'外部日程结束时间无效');result.push({key,uid,event:{title:item.summary||'Untitled',start:startIso,end:endIso,allDay:start.isDate,location:item.location??'',notes:item.description??'',repeatRule:null}});};
 const masters=components.filter(c=>!c.hasProperty('recurrence-id'));
 for(const component of masters){const event=new ICAL.Event(component),uid=event.uid;check(typeof uid==='string'&&uid.length<=512,'外部UID无效');
  const series=keepSeries===true||(Array.isArray(keepSeries)&&keepSeries.includes(uid));
  if(!event.isRecurring()||series){add(event,event.startDate,event.endDate,'',uid);if(series&&component.hasProperty('rrule')){const rule=component.getFirstPropertyValue('rrule');check(['DAILY','WEEKLY','MONTHLY','YEARLY'].includes(rule.freq)&&Object.keys(rule.parts).length===0,'外部重复规则已变化，需要重新导入');result.at(-1).event.repeatRule={frequency:rule.freq.toLowerCase(),interval:rule.interval||1,count:rule.count||null,until:rule.until?instant(rule.until,timezone):null};}continue;}
  for(const exception of components.filter(c=>c.getFirstPropertyValue('uid')===uid&&c.hasProperty('recurrence-id')))event.relateException(new ICAL.Event(exception));
  const iterator=event.iterator();let count=0,occurrence;const end=now+366*86400000,start=now-30*86400000;
  while((occurrence=iterator.next())){if(++count>20000)throw new ApiError(422,'CALDAV_RECURRENCE_LIMIT','外部重复日程超出展开上限');const at=Date.parse(instant(occurrence,component.getFirstProperty('dtstart')?.getParameter('tzid')??timezone)),key=occurrence.toString();if(at>end&&!wanted.includes(key))break;const detail=event.getOccurrenceDetails(occurrence);if(at>=start||wanted.includes(key))add(detail.item,detail.startDate,detail.endDate,key,uid);}
 }
 for(const c of components.filter(c=>c.hasProperty('recurrence-id')&&!masters.some(m=>m.getFirstPropertyValue('uid')===c.getFirstPropertyValue('uid')))){const e=new ICAL.Event(c);add(e,e.startDate,e.endDate,e.recurrenceId.toString(),e.uid);}
 check(result.length<=2000,'单个外部日历对象展开过多');return result;
}
export function writeCalendar(event,{original=null,uid,key='',now=Date.now()}={}){
 const root=original?new ICAL.Component(ICAL.parse(original)):new ICAL.Component(['vcalendar',[],[]]);
 if(!original){root.updatePropertyWithValue('version','2.0');root.updatePropertyWithValue('prodid','-//Flowday//Calendar V1//EN');}
 const components=root.getAllSubcomponents('vevent'),master=components.find(c=>c.getFirstPropertyValue('uid')===uid&&!c.hasProperty('recurrence-id'));let component;
 if(key){
  check(master,'外部重复日程主对象不存在');component=components.find(c=>c.getFirstPropertyValue('uid')===uid&&c.getFirstPropertyValue('recurrence-id')?.toString()===key);
  const recurrence=ICAL.Time.fromString(key);recurrence.zone=new ICAL.Event(master).startDate.zone;
  if(event.deletedAt){if(component)root.removeSubcomponent(component);const property=new ICAL.Property('exdate');property.setValue(recurrence);if(recurrence.zone.tzid&&!['UTC','floating'].includes(recurrence.zone.tzid))property.setParameter('tzid',recurrence.zone.tzid);master.addProperty(property);return root.toString();}
  for(const property of master.getAllProperties('exdate')){const values=property.getValues().filter(v=>v.toString()!==key);if(!values.length)master.removeProperty(property);else property.setValues(values);}
  if(!component){component=new ICAL.Component(JSON.parse(JSON.stringify(master.toJSON())));for(const name of ['rrule','rdate','exdate','recurrence-id'])component.removeAllProperties(name);const property=new ICAL.Property('recurrence-id');property.setValue(recurrence);if(recurrence.zone.tzid&&!['UTC','floating'].includes(recurrence.zone.tzid))property.setParameter('tzid',recurrence.zone.tzid);component.addProperty(property);root.addSubcomponent(component);}
 }else {component=master??new ICAL.Component('vevent');if(!master)root.addSubcomponent(component);}
 component.updatePropertyWithValue('uid',uid);component.updatePropertyWithValue('summary',event.title);component.updatePropertyWithValue('location',event.location??'');component.updatePropertyWithValue('description',event.notes??'');component.updatePropertyWithValue('dtstamp',ICAL.Time.fromJSDate(new Date(now),true));
 for(const [name,value] of [['dtstart',event.start],['dtend',event.end]]){component.removeAllProperties(name);component.updatePropertyWithValue(name,event.allDay?ICAL.Time.fromDateString(value.slice(0,10)):ICAL.Time.fromJSDate(new Date(value),true));}
 component.removeAllProperties('status');
 if(!key){component.removeAllProperties('rrule');if(event.repeatRule){const rule=event.repeatRule,parts=['FREQ='+rule.frequency.toUpperCase(),'INTERVAL='+rule.interval];if(rule.count)parts.push('COUNT='+rule.count);if(rule.until)parts.push('UNTIL='+ICAL.Time.fromJSDate(new Date(rule.until),true).toICALString());component.updatePropertyWithValue('rrule',ICAL.Recur.fromString(parts.join(';')));}}
 return root.toString();
}
