import { describe,expect,it } from 'vitest';
import { dayBounds, dayInZone, instantInZone } from './timezone';
describe('timezone date boundaries',()=>{
  it('uses selected timezone rather than computer timezone',()=>{
    expect(dayInZone(new Date('2026-10-03T18:00:00Z'),'Asia/Shanghai')).toBe('2026-10-04');
    expect(instantInZone('2026-10-04T09:00','Asia/Shanghai')).toBe('2026-10-04T01:00:00.000Z');
  });
  it('handles 23 hour spring and 25 hour autumn days',()=>{
    const spring=dayBounds('2026-03-08','America/New_York');
    const autumn=dayBounds('2026-11-01','America/New_York');
    expect(spring.end-spring.start).toBe(23*3600000);
    expect(autumn.end-autumn.start).toBe(25*3600000);
  });
  it('rejects nonexistent wall times during daylight saving transitions',()=>{
    expect(()=>instantInZone('2026-03-08T02:30','America/New_York')).toThrow();
  });
});
