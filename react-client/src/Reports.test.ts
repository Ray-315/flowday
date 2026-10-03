import { expect, it } from 'vitest';
import { emptyWorkspace } from './workspace';
import { reportStatistics } from './Reports';
it('counts clipped event effort without counting linked task effort twice', () => {
  const data = emptyWorkspace();
  data.tasks = [
    {
      id: 't',
      title: '任务',
      status: 'done',
      priority: 'normal',
      completedAt: '2026-10-05T10:00Z',
      estimateMinutes: 120,
      actualMinutes: 90,
    },
  ];
  data.events = [
    {
      id: 'e',
      title: '任务',
      taskId: 't',
      start: '2026-10-04T23:00Z',
      end: '2026-10-05T01:00Z',
      actualMinutes: 60,
      completed: true,
      color: 0xff000000,
    },
  ];
  expect(reportStatistics(data, '2026-10-05T00:00Z', '2026-10-06T00:00Z')).toMatchObject({
    done: 1,
    actual: 60,
    estimated: 120,
    completion: 100,
  });
});
