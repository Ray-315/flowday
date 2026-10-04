import { expect, it, vi } from 'vitest';
import { invoke } from '@tauri-apps/api/core';
vi.mock('@tauri-apps/api/core', () => ({ isTauri: () => true, invoke: vi.fn() }));
import { eligibleEvents, endActivityForOtherScope } from './liveActivityBridge';
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
