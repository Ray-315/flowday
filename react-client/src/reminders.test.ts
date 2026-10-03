import { describe,expect,it } from 'vitest';
import { dueReminders } from './reminders';
import { emptyWorkspace } from './workspace';
describe('local reminders',()=>{
  const start='2026-10-03T09:00:00Z';
  const data={...emptyWorkspace(),events:[{id:'e',title:'上课',start,end:'2026-10-03T10:00:00Z',color:0xff237bff}],preferences:{reminderMinutes:10}};
  it('fires lead time once without resetting on unrelated changes',()=>{
    const due=dueReminders(data,{},new Date('2026-10-03T08:50:00Z'));
    expect(due).toHaveLength(1);
    expect(dueReminders({...data,preferences:{...data.preferences,themeMode:'dark'}},{[due[0].key]:{sentCount:1,lastSent:'2026-10-03T08:50:00Z'}},new Date('2026-10-03T08:51:00Z'))).toHaveLength(0);
  });
  it('honors independent reminder rules and completion',()=>{
    expect(dueReminders({...data,events:[{...data.events[0],reminderRules:[]}]},{},new Date(start))).toHaveLength(0);
    expect(dueReminders({...data,events:[{...data.events[0],completed:true}]},{},new Date(start))).toHaveLength(0);
  });
  it('strong reminders stop after acknowledgment or max count',()=>{
    const strong={...data,preferences:{reminderMinutes:10,strongReminder:true,reminderInterval:5,maxReminders:3}};
    const first=dueReminders(strong,{},new Date('2026-10-03T08:50:00Z'))[0];
    expect(dueReminders(strong,{[first.key]:{sentCount:1,lastSent:'2026-10-03T08:50:00Z'}},new Date('2026-10-03T08:55:00Z'))).toHaveLength(1);
    expect(dueReminders(strong,{[first.key]:{sentCount:1,lastSent:'2026-10-03T08:50:00Z',acknowledged:true}},new Date(start))).toHaveLength(0);
    expect(dueReminders(strong,{[first.key]:{sentCount:3,lastSent:'2026-10-03T08:50:00Z'}},new Date(start))).toHaveLength(0);
  });
  it('preserves the Flutter maximum of one hundred strong reminder deliveries',()=>{
    const strong={...data,preferences:{reminderMinutes:10,strongReminder:true,reminderInterval:1,maxReminders:100}};
    const first=dueReminders(strong,{},new Date('2026-10-03T08:50:00Z'))[0];
    expect(first.maximum).toBe(100);
    expect(dueReminders(strong,{[first.key]:{sentCount:75,lastSent:'2026-10-03T08:50:00Z'}},new Date('2026-10-03T09:00:00Z'))).toHaveLength(1);
  });
});
