import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';

void main() {
  test(
    'delay refresh enters waiting then ready without redundant notifications',
    () {
      final anchor = DateTime(2026, 10, 1, 9);
      final store = FlowStore(
        FlowData(
          projects: [Project(id: 'p', title: '项目')],
          nodes: [
            FlowNode(
              id: 'a',
              projectId: 'p',
              title: '前置',
              status: NodeStatus.done,
              completedAt: anchor,
            ),
            FlowNode(id: 'b', projectId: 'p', title: '延迟'),
          ],
          edges: [
            FlowEdge(
              id: 'e',
              projectId: 'p',
              sourceId: 'a',
              targetId: 'b',
              delayMinutes: 30,
            ),
          ],
        ),
      );
      var notifications = 0;
      store.addListener(() => notifications++);
      store.refreshWorkflow(now: anchor);
      expect(store.data.nodes.last.status, NodeStatus.waiting);
      expect(store.data.nodes.last.delayWaiting, isTrue);
      expect(notifications, 1);
      store.refreshWorkflow(now: anchor.add(const Duration(minutes: 10)));
      expect(notifications, 1);
      store.refreshWorkflow(now: anchor.add(const Duration(minutes: 30)));
      expect(store.data.nodes.last.status, NodeStatus.ready);
      expect(notifications, 2);
    },
  );
  test(
    'repeat instances have independent completion and month dates clamp',
    () {
      final store = FlowStore(FlowData());
      store.addTask(
        Task(
          id: 't',
          title: '复习',
          plannedStart: DateTime(2026, 1, 31),
          difficulty: Difficulty.high,
          repeatRule: RepeatRule(frequency: RepeatFrequency.monthly, count: 3),
        ),
      );
      expect(store.tasks.map((x) => x.plannedStart!.day), [31, 28, 31]);
      store.setTaskStatus('t', TaskStatus.done);
      expect(
        store.tasks.skip(1).every((x) => x.status == TaskStatus.todo),
        isTrue,
      );
      final imported = FlowData.fromJson(store.data.toJson());
      expect(imported.tasks.first.difficulty, Difficulty.high);
      expect(imported.tasks.first.repeatRule!.count, 3);
    },
  );

  test('single and future event edits preserve past completion', () {
    final store = FlowStore(FlowData());
    store.addEvent(
      CalendarEvent(
        id: 'e',
        title: '学习',
        start: DateTime(2026, 10, 1, 9),
        end: DateTime(2026, 10, 1, 10),
        repeatRule: RepeatRule(frequency: RepeatFrequency.daily, count: 3),
      ),
    );
    store.completeEvent('e');
    final second = CalendarEvent.fromJson(store.events[1].toJson())
      ..title = '调整';
    store.updateEvent(second);
    expect(store.events.map((x) => x.title), ['学习', '调整', '学习']);
    final changed = CalendarEvent.fromJson(second.toJson())
      ..start = DateTime(2026, 10, 2, 11)
      ..end = DateTime(2026, 10, 2, 12);
    store.updateEvent(changed, scope: RepeatScope.thisAndFuture);
    expect(store.events.last.start, DateTime(2026, 10, 3, 11));
    expect(store.events.first.completed, isTrue);
  });

  test('changing future repeat frequency replaces only future instances', () {
    final store = FlowStore(FlowData());
    store.addTask(
      Task(
        id: 't',
        title: '复习',
        plannedStart: DateTime(2026, 10, 1),
        repeatRule: RepeatRule(frequency: RepeatFrequency.daily, count: 3),
      ),
    );
    store.setTaskStatus('t', TaskStatus.done);
    final changed = Task.fromJson(store.tasks[1].toJson())
      ..repeatRule = RepeatRule(frequency: RepeatFrequency.weekly, count: 2);
    store.updateTask(changed, scope: RepeatScope.thisAndFuture);
    expect(store.tasks.map((x) => x.plannedStart), [
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 2),
      DateTime(2026, 10, 9),
    ]);
    expect(store.tasks.first.status, TaskStatus.done);
    store.materializeRecurring(until: DateTime(2027));
    expect(store.tasks.length, 3);
  });

  test('condition branch and delay gate downstream independently', () {
    final anchor = DateTime.now();
    final store = FlowStore(
      FlowData(
        projects: [Project(id: 'p', title: '项目')],
        nodes: [
          FlowNode(
            id: 'c',
            projectId: 'p',
            title: '条件',
            kind: NodeKind.condition,
          ),
          FlowNode(id: 'a', projectId: 'p', title: 'A'),
          FlowNode(id: 'b', projectId: 'p', title: 'B'),
        ],
        edges: [
          FlowEdge(
            id: 'ca',
            projectId: 'p',
            sourceId: 'c',
            targetId: 'a',
            delayMinutes: 30,
          ),
          FlowEdge(id: 'cb', projectId: 'p', sourceId: 'c', targetId: 'b'),
        ],
      ),
    );
    store.selectBranch('c', 'ca');
    store.refreshWorkflow(now: anchor.add(const Duration(minutes: 31)));
    expect(store.data.nodes[1].status, NodeStatus.ready);
    expect(store.data.nodes[2].status, NodeStatus.locked);
    store.selectBranch('c', 'cb');
    expect(store.data.nodes[1].status, NodeStatus.locked);
    expect(store.data.nodes[2].status, NodeStatus.ready);
  });

  test(
    'project trash hides descendants and purges without broken references',
    () {
      final store = FlowStore(
        FlowData(
          projects: [
            Project(id: 'p', title: '项目'),
            Project(id: 'child', title: '子项目', parentId: 'p'),
          ],
          tasks: [Task(id: 't', title: '任务', projectId: 'child')],
          events: [
            CalendarEvent(
              id: 'e',
              title: '日程',
              projectId: 'child',
              start: DateTime(2026),
              end: DateTime(2026, 1, 1, 1),
            ),
          ],
        ),
      );
      store.deleteProject('p');
      expect(store.tasks, isEmpty);
      expect(store.events, isEmpty);
      store.restoreProject('p');
      expect(store.tasks.length, 1);
      store.deleteProject('p');
      store.project('p')!.deletedAt = DateTime(2026, 1, 1);
      store.purgeTrash(now: DateTime(2026, 2, 1));
      expect(store.project('p'), isNull);
      expect(store.project('child')!.parentId, isNull);
      store.data.validate();
    },
  );

  test(
    'attachment metadata and nested groups survive round trip and movement',
    () {
      final store = FlowStore(
        FlowData(
          projects: [
            Project(
              id: 'p',
              title: '项目',
              attachments: [
                Attachment(
                  id: 'a',
                  title: '笔记',
                  kind: AttachmentKind.markdown,
                  content: '# 结果',
                ),
              ],
            ),
          ],
          nodes: [
            FlowNode(
              id: 'g',
              projectId: 'p',
              title: '阶段',
              kind: NodeKind.group,
              collapsed: true,
            ),
            FlowNode(
              id: 'n',
              projectId: 'p',
              title: '任务',
              groupId: 'g',
              x: 10,
              y: 20,
            ),
          ],
        ),
      );
      store.moveGroup('g', 5, 6);
      final imported = FlowData.fromJson(store.data.toJson());
      expect(imported.nodes.last.x, 15);
      expect(imported.nodes.last.y, 26);
      expect(imported.nodes.first.collapsed, isTrue);
      expect(imported.projects.first.attachments.single.content, '# 结果');
    },
  );

  test('actual block time edits recalculate linked task total', () {
    final store = FlowStore(
      FlowData(
        tasks: [Task(id: 't', title: '任务')],
        events: [
          CalendarEvent(
            id: 'e',
            title: '时间块',
            taskId: 't',
            start: DateTime(2026),
            end: DateTime(2026, 1, 1, 1),
            completed: true,
            actualMinutes: 60,
          ),
        ],
      ),
    );
    store.setEventActualMinutes('e', 45);
    expect(store.tasks.single.actualMinutes, 45);
    expect(() => store.setEventActualMinutes('e', -1), throwsFormatException);
    expect(store.tasks.single.actualMinutes, 45);
  });
}
