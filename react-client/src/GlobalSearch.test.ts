import { expect, it } from 'vitest';
import { emptyWorkspace } from './workspace';
import { globalSearchResults } from './GlobalSearch';
it('searches descriptions tags workflow and inline/cloud attachments without deleted records', () => {
  const data = emptyWorkspace();
  data.projects = [{ id: 'p', title: '项目', description: '数学', color: 0xff000000 }];
  data.tasks = [
    {
      id: 't',
      title: '作业',
      description: '数学',
      status: 'todo',
      priority: 'normal',
      projectId: 'p',
      attachments: [{ id: 'a', title: '数学讲义', kind: 'markdown', content: '练习' }],
    },
    { id: 'deleted', title: '数学', status: 'todo', priority: 'normal', deletedAt: '2026-10-05T00:00Z' },
  ];
  data.nodes = [{ id: 'n', title: '数学节点', projectId: 'p' }];
  const results = globalSearchResults(data, '数学', [
    { id: 'cloud', name: '数学文件', ownerType: 'task', ownerId: 't' },
  ]);
  expect(results.map((item) => item.kind)).toEqual(['task', 'attachment', 'project', 'node', 'attachment']);
  expect(globalSearchResults(data, '')).toEqual([]);
});
