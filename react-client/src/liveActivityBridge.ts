import { invoke, isTauri } from '@tauri-apps/api/core';
import type { CalendarEvent } from './workspace';
export type ActiveActivity = { title: string; start: number; end: number; scope: string; eventId: string | null };
export type ActivityStatus = { supported: boolean; enabled: boolean; active: ActiveActivity | null };
export const unavailable: ActivityStatus = { supported: false, enabled: false, active: null };
export function activityCall(command: 'status' | 'start' | 'end', data?: Omit<ActiveActivity, 'eventId'> & { eventId?: string | null }): Promise<ActivityStatus> {
  return isTauri() ? invoke(`plugin:live-activity|${command}`, data ? { data } : {}) : Promise.resolve(unavailable);
}
export function eligibleEvents(events: CalendarEvent[], now: number) {
  return events.filter(e => !e.deletedAt && !e.completed && !e.allDay &&
    Date.parse(e.start) <= now && Date.parse(e.end) > now && Date.parse(e.end) - now <= 8 * 3600000);
}
export async function endActivityForOtherScope(scope: string) {
  const status = await activityCall('status');
  if (status.active && status.active.scope !== scope) await activityCall('end');
}
