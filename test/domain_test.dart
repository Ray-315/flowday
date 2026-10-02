import 'dart:convert';
import 'dart:async' show Completer;

import 'package:flutter_test/flutter_test.dart';

import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';

void main() {
  test(
    'a flush queued during import cannot overwrite the imported file',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      var diskId = 'old';
      final s = FlowStore(
        FlowData(
          tasks: [Task(id: 'old', title: 'Old')],
        ),
        save: (data) async {
          if (data.tasks.first.id == 'new') {
            started.complete();
            await release.future;
          }
          diskId = data.tasks.first.id;
        },
      );
      final imported = s.importJson(
        FlowStore(
          FlowData(
            tasks: [Task(id: 'new', title: 'New')],
          ),
        ).exportJson(),
      );
      await started.future;
      final flush = s.persist();
      release.complete();
      await imported;
      await flush;
      expect(diskId, 'new');
      expect(s.tasks.single.id, 'new');
    },
  );
  test('failed import retains state and later saves still work', () async {
    var fail = true;
    final saved = <String>[];
    final s = FlowStore(
      FlowData(
        tasks: [Task(id: 'old', title: 'Old')],
      ),
      save: (data) async {
        if (fail) throw StateError('disk full');
        saved.add(data.tasks.first.id);
      },
    );
    final incoming = FlowStore(
      FlowData(
        tasks: [Task(id: 'new', title: 'New')],
      ),
    ).exportJson();
    await expectLater(s.importJson(incoming), throwsStateError);
    expect(s.tasks.single.id, 'old');
    fail = false;
    await s.persist();
    expect(saved, ['old']);
    expect(s.error, isNull);
  });
  test(
    'import serializes saves and preserves edits made during import',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      final saved = <List<String>>[];
      final s = FlowStore(
        FlowData(
          tasks: [Task(id: 'old', title: 'Old')],
        ),
        save: (data) async {
          if (data.tasks.first.id == 'new') {
            started.complete();
            await release.future;
          }
          saved.add(data.tasks.map((x) => x.id).toList());
        },
      );
      final incoming = FlowStore(
        FlowData(
          tasks: [Task(id: 'new', title: 'New')],
        ),
      ).exportJson();
      final imported = s.importJson(incoming);
      final rejected = expectLater(imported, throwsStateError);
      await started.future;
      s.addTask(Task(id: 'edit', title: 'Concurrent edit'));
      release.complete();
      await rejected;
      await s.persist();
      expect(s.tasks.map((x) => x.id), ['old', 'edit']);
      expect(saved.last, ['old', 'edit']);
    },
  );
  test(
    'known preferences reject invalid imports without replacing state',
    () async {
      final invalid = <Map<String, dynamic>>[
        {'calendarView': 3},
        {'calendarView': 'year'},
        {'displayName': 3},
        {'displayName': 'x' * 101},
        {'weekStartsMonday': 'true'},
        {'overlapStyle': 'stack'},
      ];
      final s = FlowStore(
        FlowData(
          tasks: [Task(id: 'old', title: 'Old')],
        ),
      );
      for (final preferences in invalid) {
        final incoming = FlowData(preferences: preferences).toJson();
        await expectLater(
          s.importJson(jsonEncode(incoming)),
          throwsFormatException,
        );
        expect(s.tasks.single.id, 'old');
      }
    },
  );
  test('deleted and restored completed blocks recalculate actual time', () {
    final s = FlowStore(
      FlowData(
        tasks: [Task(id: 't', title: 'T')],
        events: [
          CalendarEvent(
            id: 'a',
            title: 'A',
            taskId: 't',
            start: DateTime(2026),
            end: DateTime(2026, 1, 1, 1),
          ),
          CalendarEvent(
            id: 'b',
            title: 'B',
            taskId: 't',
            start: DateTime(2026),
            end: DateTime(2026, 1, 1, 1),
          ),
        ],
      ),
    );
    s.completeEvent('a');
    s.deleteEvent('a');
    expect(s.tasks.single.actualMinutes, 0);
    s.completeEvent('b');
    s.restoreEvent('a');
    expect(s.tasks.single.actualMinutes, 120);
  });
  test('invalid tag types are rejected before importing state', () async {
    final s = FlowStore(
      FlowData(
        tasks: [Task(id: 't', title: 'Keep')],
      ),
    );
    final incoming = s.data.toJson();
    (incoming['tasks'] as List).first['tags'] = [42];
    await expectLater(
      s.importJson(jsonEncode(incoming)),
      throwsFormatException,
    );
    expect(s.tasks.single.tags, isEmpty);
  });
  test(
    'creating completed tasks records time and linked nodes inherit status',
    () {
      final s = FlowStore(
        FlowData(
          projects: [Project(id: 'p', title: 'P')],
        ),
      );
      s.addTask(Task(id: 't', title: 'Done', status: TaskStatus.done));
      expect(s.tasks.single.completedAt, isNotNull);
      s.addNode(
        FlowNode(id: 'n', projectId: 'p', title: 'Linked', taskId: 't'),
      );
      expect(s.data.nodes.single.status, NodeStatus.done);
    },
  );
  CalendarEvent block(String id) => CalendarEvent(
    id: id,
    title: id,
    taskId: 't',
    start: DateTime(2026, 9, 29, 9),
    end: DateTime(2026, 9, 29, 10),
  );
  test('one block completes task and linked node exactly once', () {
    final s = FlowStore(
      FlowData(
        projects: [Project(id: 'p', title: 'P')],
        tasks: [Task(id: 't', title: 'T')],
        events: [block('e')],
        nodes: [FlowNode(id: 'n', projectId: 'p', title: 'N', taskId: 't')],
      ),
    );
    s.completeEvent('e');
    s.completeEvent('e');
    expect(s.tasks.single.status, TaskStatus.done);
    expect(s.tasks.single.actualMinutes, 60);
    expect(s.data.nodes.single.status, NodeStatus.done);
  });
  test('multiple blocks accumulate without completing task', () {
    final s = FlowStore(
      FlowData(
        tasks: [Task(id: 't', title: 'T')],
        events: [block('a'), block('b')],
      ),
    );
    s.completeEvent('a');
    s.completeEvent('b');
    expect(s.tasks.single.actualMinutes, 120);
    expect(s.tasks.single.status, TaskStatus.todo);
  });
  test('AND and OR use skipped predecessors and allow manual loops', () {
    final s = FlowStore(
      FlowData(
        projects: [Project(id: 'p', title: 'P')],
      ),
    );
    for (final id in ['a', 'b', 'and', 'or']) {
      s.addNode(
        FlowNode(id: id, projectId: 'p', title: id, anyPredecessor: id == 'or'),
      );
    }
    for (final target in ['and', 'or']) {
      for (final source in ['a', 'b']) {
        s.addEdge(
          FlowEdge(
            id: '$source-$target',
            projectId: 'p',
            sourceId: source,
            targetId: target,
          ),
        );
      }
    }
    s.setNodeStatus('a', NodeStatus.skipped);
    expect(s.data.nodes[2].status, NodeStatus.locked);
    expect(s.data.nodes[3].status, NodeStatus.ready);
    s.setNodeStatus('b', NodeStatus.done);
    expect(s.data.nodes[2].status, NodeStatus.ready);
    s.addEdge(
      FlowEdge(id: 'loop', projectId: 'p', sourceId: 'and', targetId: 'a'),
    );
    expect(s.data.nodes.first.status, NodeStatus.skipped);
  });
  test('project moves reject hierarchy cycles without mutation', () {
    final s = FlowStore(
      FlowData(
        projects: [
          Project(id: 'a', title: 'A'),
          Project(id: 'b', title: 'B', parentId: 'a'),
        ],
      ),
    );
    expect(() => s.moveProject('a', 'b'), throwsFormatException);
    expect(s.project('a')!.parentId, isNull);
  });
  test('invalid import retains existing state', () async {
    final s = FlowStore(
      FlowData(
        tasks: [Task(id: 't', title: 'Keep')],
      ),
    );
    final bad = s.data.toJson();
    (bad['tasks'] as List).first['projectId'] = 'missing';
    await expectLater(s.importJson(jsonEncode(bad)), throwsFormatException);
    expect(s.tasks.single.title, 'Keep');
    await expectLater(s.importJson('{}'), throwsFormatException);
  });
  test('deleted and cancelled tasks excluded from progress', () {
    final s = FlowStore(
      FlowData(
        projects: [Project(id: 'p', title: 'P')],
        tasks: [
          Task(id: 'a', title: 'A', projectId: 'p', status: TaskStatus.done),
          Task(
            id: 'b',
            title: 'B',
            projectId: 'p',
            status: TaskStatus.cancelled,
          ),
        ],
      ),
    );
    expect(s.progress('p'), 1);
    s.deleteTask('a');
    expect(s.progress('p'), 0);
    s.restoreTask('a');
    expect(s.progress('p'), 1);
  });
  test('save queue snapshots state and survives errors', () async {
    final snapshots = <int>[];
    var active = 0;
    final s = FlowStore(
      FlowData(),
      save: (data) async {
        active++;
        expect(active, 1);
        await Future<void>.delayed(const Duration(milliseconds: 2));
        snapshots.add(data.tasks.length);
        active--;
        if (snapshots.length == 1) throw StateError('disk');
      },
    );
    s.addTask(Task(id: 'a', title: 'A'));
    s.addTask(Task(id: 'b', title: 'B'));
    await s.persist();
    expect(snapshots, [1, 2, 2]);
    expect(s.error, isNull);
  });
  test('rejects blank titles and invalid event ranges', () {
    final s = FlowStore(FlowData());
    expect(() => s.addTask(Task(id: 'a', title: ' ')), throwsFormatException);
    expect(
      () => s.addEvent(
        CalendarEvent(
          id: 'e',
          title: 'E',
          start: DateTime(2026),
          end: DateTime(2025),
        ),
      ),
      throwsFormatException,
    );
  });
  test('round trip preserves every collection and optional field', () async {
    final data = FlowData(
      projects: [
        Project(
          id: 'p',
          title: '项目',
          description: '说明',
          deadline: DateTime(2026, 10),
        ),
      ],
      tasks: [
        Task(
          id: 't',
          title: '任务',
          projectId: 'p',
          tags: ['标签'],
          priority: Priority.urgent,
        ),
      ],
      events: [block('e')],
      nodes: [FlowNode(id: 'n', projectId: 'p', title: '节点', taskId: 't')],
      captures: [Capture(id: 'c', text: '想法', createdAt: DateTime(2026))],
      notices: [
        AppNotice(
          id: 'a',
          title: '提醒',
          body: '内容',
          createdAt: DateTime(2026),
          taskId: 't',
        ),
      ],
      preferences: {'weekStart': 1},
    );
    final store = FlowStore(data);
    final restored = FlowStore(FlowData());
    await restored.importJson(store.exportJson());
    expect(restored.exportJson(), store.exportJson());
  });
  test('archived ancestors hide descendant tasks', () {
    final s = FlowStore(
      FlowData(
        projects: [
          Project(id: 'p', title: 'P', archived: true),
          Project(id: 'child', title: 'Child', parentId: 'p'),
        ],
        tasks: [Task(id: 't', title: 'T', projectId: 'child')],
      ),
    );
    expect(s.tasks, isEmpty);
    expect(s.data.tasks, hasLength(1));
  });
  test('missing edge endpoints and duplicate ids leave state unchanged', () {
    final s = FlowStore(
      FlowData(
        projects: [Project(id: 'p', title: 'P')],
      ),
    );
    expect(
      () => s.addEdge(
        FlowEdge(
          id: 'e',
          projectId: 'p',
          sourceId: 'missing',
          targetId: 'missing',
        ),
      ),
      throwsFormatException,
    );
    expect(s.data.edges, isEmpty);
    expect(
      () => s.addProject(Project(id: 'p', title: 'Duplicate')),
      throwsFormatException,
    );
    expect(s.projects, hasLength(1));
  });
  test('node completion updates task and reopening updates linked node', () {
    final s = FlowStore(
      FlowData(
        projects: [Project(id: 'p', title: 'P')],
        tasks: [Task(id: 't', title: 'T')],
        nodes: [FlowNode(id: 'n', projectId: 'p', title: 'N', taskId: 't')],
      ),
    );
    s.setNodeStatus('n', NodeStatus.done);
    expect(s.tasks.single.completedAt, isNotNull);
    s.setTaskStatus('t', TaskStatus.todo);
    expect(s.data.nodes.single.status, NodeStatus.ready);
    expect(s.tasks.single.completedAt, isNull);
  });
  test('editing task status records completion time', () {
    final s = FlowStore(
      FlowData(
        tasks: [Task(id: 't', title: 'T')],
      ),
    );
    s.updateTask(Task(id: 't', title: 'Edited', status: TaskStatus.done));
    expect(s.tasks.single.completedAt, isNotNull);
  });
  test('layout terminates with graph cycles and places each node', () {
    final s = FlowStore(
      FlowData(
        projects: [Project(id: 'p', title: 'P')],
        nodes: [
          FlowNode(id: 'a', projectId: 'p', title: 'A'),
          FlowNode(id: 'b', projectId: 'p', title: 'B'),
        ],
        edges: [
          FlowEdge(id: 'ab', projectId: 'p', sourceId: 'a', targetId: 'b'),
          FlowEdge(id: 'ba', projectId: 'p', sourceId: 'b', targetId: 'a'),
        ],
      ),
    );
    s.autoLayout('p');
    expect(s.data.nodes.first.x, isNot(s.data.nodes.last.x));
  });
}
