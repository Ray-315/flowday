import { invoke, isTauri } from '@tauri-apps/api/core';
import type { CalendarEvent } from './workspace';
export type ActiveActivity = { title: string; start: number; end: number; scope: string; eventId: string | null; upcoming?: boolean };
export type ActivityStatus = { supported: boolean; enabled: boolean; active: ActiveActivity | null; scheduled?: ActiveActivity | null; autoScheduling?: boolean };
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
  if ((status.active && status.active.scope !== scope) || (status.scheduled && status.scheduled.scope !== scope)) await activityCall('end');
}

export type AutoActivitySettings = { enabled: boolean; minutes: number };
export function readAutoActivitySettings(scope: string): AutoActivitySettings {
  try {
    const value = JSON.parse(localStorage.getItem(`flowday.live-activity.auto:${scope}`) || '{}');
    return { enabled: value.enabled === true, minutes: Number.isInteger(value.minutes) && value.minutes >= 1 && value.minutes <= 120 ? value.minutes : 10 };
  } catch { return { enabled: false, minutes: 10 }; }
}
export function nextActivityEvent(events: CalendarEvent[], now: number) {
  return events.filter(e => !e.deletedAt && !e.completed && !e.allDay && Number.isFinite(Date.parse(e.start)) &&
    Date.parse(e.start) > now + 5000 && Date.parse(e.end) > Date.parse(e.start))
    .sort((a, b) => Date.parse(a.start) - Date.parse(b.start) || a.id.localeCompare(b.id))[0];
}
export function scheduleActivity(events: CalendarEvent[], scope: string, settings: AutoActivitySettings): Promise<ActivityStatus> {
  const event = settings.enabled ? nextActivityEvent(events, Date.now()) : undefined;
  return invoke('plugin:live-activity|schedule', { data: { scope, minutes: settings.minutes,
    event: event ? { eventId: event.id, title: event.title.slice(0,120), start: Date.parse(event.start) } : null } });
}
