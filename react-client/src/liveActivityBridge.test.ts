import { expect, it, vi } from 'vitest';
import { invoke } from '@tauri-apps/api/core';
vi.mock('@tauri-apps/api/core', () => ({ isTauri: () => true, invoke: vi.fn() }));
import { eligibleEvents, endActivityForOtherScope, nextActivityEvent, scheduleActivity } from './liveActivityBridge';
const now = Date.parse('2026-10-04T12:00:00Z');
const event = { id: 'e', title: '论文', color: 0, start: '2026-10-04T11:30:00Z', end: '2026-10-04T12:30:00Z' };
it('offers only live, unfinished events within the ActivityKit lifetime', () => {
  expect(eligibleEvents([
    event, { ...event, id: 'deleted', deletedAt: '2026-10-04T11:00:00Z' },
    { ...event, id: 'done', completed: true }, { ...event, id: 'all-day', allDay: true },
    { ...event, id: 'future', start: '2026-10-04T12:01:00Z' },
    { ...event, id: 'ended', end: '2026-10-04T12:00:00Z' },
    { ...event, id: 'too-long', end: '2026-10-05T12:00:00Z' },
  ], now).map(e => e.id)).toEqual(['e']);
});

it('preserves the same account activity and ends it when switching accounts', async () => {
  const call = vi.mocked(invoke);
  call.mockResolvedValue({ supported: true, enabled: true, active: { scope: 'account-a' } });
  await endActivityForOtherScope('account-a');
  expect(call).toHaveBeenCalledTimes(1);
  call.mockClear();
  await endActivityForOtherScope('account-b');
  expect(call.mock.calls.map(args => args[0])).toEqual(['plugin:live-activity|status', 'plugin:live-activity|end']);
});

it('chooses the earliest future unfinished timed event and ignores malformed or cancelled entries', () => {
  const future = { ...event, start: '2026-10-04T12:20:00Z', end: '2026-10-04T13:00:00Z' };
  const earlier = { ...future, id: 'earlier', start: '2026-10-04T12:10:00Z' };
  expect(nextActivityEvent([future, earlier, { ...earlier, completed: true }, { ...earlier, deletedAt: 'now' }, { ...earlier, allDay: true }, { ...earlier, start: 'invalid' }, event], now)?.id).toBe('earlier');
  expect(nextActivityEvent([event], now)).toBeUndefined();
});
it('cancels the native reservation when automatic reminders are disabled', async () => {
  const call = vi.mocked(invoke); call.mockClear(); call.mockResolvedValue({ supported: true, enabled: true, active: null });
  await scheduleActivity([event], 'scope', { enabled: false, minutes: 15 });
  expect(call).toHaveBeenCalledWith('plugin:live-activity|schedule', { data: { scope: 'scope', minutes: 15, event: null } });
});
it('clears a pending reservation when switching accounts', async () => {
  const call = vi.mocked(invoke); call.mockClear();
  call.mockResolvedValue({ supported: true, enabled: true, active: null, scheduled: { scope: 'previous' } });
  await endActivityForOtherScope('new');
  expect(call.mock.calls.map(args => args[0])).toEqual(['plugin:live-activity|status', 'plugin:live-activity|end']);
});
