import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/backup_service.dart';
import 'package:flowday/data/repository.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';

class EditingBackupService extends BackupService {
  EditingBackupService(super.directory, this.store);
  final FlowStore store;
  @override
  Future<File> create(FlowData data, {String kind = 'manual'}) async {
    final file = await super.create(data, kind: kind);
    store.data.tasks.add(Task(id: 'new', title: 'Concurrent edit'));
    store.changed();
    return file;
  }
}

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('flow-backup-'),
  );
  tearDown(() async => directory.delete(recursive: true));
  test('backups stay in their account directory', () async {
    final a = BackupService(Directory('${directory.path}/a'));
    final b = BackupService(Directory('${directory.path}/b'));
    await a.create(FlowData());
    expect(await a.list(), hasLength(1));
    expect(await b.list(), isEmpty);
  });
  test('invalid restore leaves current data and backups unchanged', () async {
    final service = BackupService(directory);
    final store = FlowStore(
      FlowData(
        tasks: [Task(id: 't', title: 'Keep')],
      ),
    );
    await expectLater(
      service.restore(store, '{"schemaVersion":9}'),
      throwsFormatException,
    );
    expect(store.tasks.single.title, 'Keep');
    expect(await service.list(), isEmpty);
    store.dispose();
  });
  test('restore first protects current data', () async {
    final service = BackupService(directory);
    final store = FlowStore(
      FlowData(
        tasks: [Task(id: 't', title: 'Keep')],
      ),
    );
    await service.restore(store, FlowStore(FlowData()).exportJson());
    expect(store.tasks, isEmpty);
    expect(
      await (await service.list()).single.readAsString(),
      contains('Keep'),
    );
    store.dispose();
  });
  test('automatic backup runs once per calendar day', () async {
    final service = BackupService(directory);
    final data = FlowData();
    await service.daily(data, now: DateTime(2026, 9, 29, 8));
    await service.daily(data, now: DateTime(2026, 9, 29, 20));
    expect(await service.list(), hasLength(1));
    await service.daily(data, now: DateTime(2026, 9, 30));
    expect(await service.list(), hasLength(2));
  });
  test('repository honors automatic backup disabled', () async {
    await JsonRepository(
      directory,
    ).save(FlowData(preferences: {'automaticBackup': false}));
    expect(await BackupService(directory).list(), isEmpty);
    await JsonRepository(directory).save(FlowData());
    expect(await BackupService(directory).list(), hasLength(1));
  });
  test('cleanup soft deletes and keeps task references valid', () async {
    final store = FlowStore(
      FlowData(
        tasks: [Task(id: 't', title: 'Done', status: TaskStatus.done)],
        events: [
          CalendarEvent(
            id: 'e',
            title: 'Past',
            taskId: 't',
            start: DateTime(2020),
            end: DateTime(2020, 1, 2),
          ),
        ],
      ),
    );
    await BackupService(
      directory,
    ).cleanup(store, completedTasks: true, pastEvents: true);
    expect(store.data.tasks.single.deletedAt, isNotNull);
    expect(store.data.events.single.deletedAt, isNotNull);
    expect(store.data.events.single.taskId, 't');
    store.data.validate();
    store.dispose();
  });
  test('clear protects original and preserves preferences', () async {
    final store = FlowStore(
      FlowData(
        tasks: [Task(id: 't', title: 'Keep')],
        preferences: {'displayName': 'Ray'},
      ),
    );
    final service = BackupService(directory);
    await service.clear(store);
    expect(store.tasks, isEmpty);
    expect(store.data.preferences['displayName'], 'Ray');
    expect(await service.list(), hasLength(1));
    store.dispose();
  });
  test('cleanup recalculates task time from remaining events', () async {
    final store = FlowStore(
      FlowData(
        tasks: [Task(id: 't', title: 'Task', actualMinutes: 90)],
        events: [
          CalendarEvent(
            id: 'past',
            title: 'Past',
            taskId: 't',
            start: DateTime(2020),
            end: DateTime(2020, 1, 2),
            completed: true,
            actualMinutes: 60,
          ),
          CalendarEvent(
            id: 'future',
            title: 'Future',
            taskId: 't',
            start: DateTime(2100),
            end: DateTime(2100, 1, 2),
            completed: true,
            actualMinutes: 30,
          ),
        ],
      ),
    );
    await BackupService(
      directory,
    ).cleanup(store, completedTasks: false, pastEvents: true);
    expect(store.data.tasks.single.actualMinutes, 30);
    expect(store.events.single.id, 'future');
    store.dispose();
  });
  test('cleanup preserves unfinished child and its parent link', () async {
    final store = FlowStore(
      FlowData(
        tasks: [
          Task(id: 'p', title: 'Parent', status: TaskStatus.done),
          Task(id: 'c', title: 'Child', parentId: 'p'),
        ],
      ),
    );
    await BackupService(
      directory,
    ).cleanup(store, completedTasks: true, pastEvents: false);
    expect(store.data.tasks.first.deletedAt, isNotNull);
    expect(store.data.tasks.last.deletedAt, isNull);
    expect(store.data.tasks.last.parentId, 'p');
    store.data.validate();
    store.dispose();
  });
  for (final operation in ['restore', 'cleanup', 'clear']) {
    test('$operation aborts if data changes while backup is written', () async {
      final store = FlowStore(
        FlowData(
          tasks: [Task(id: 't', title: 'Original', status: TaskStatus.done)],
        ),
      );
      final service = EditingBackupService(directory, store);
      final future = switch (operation) {
        'restore' => service.restore(store, FlowStore(FlowData()).exportJson()),
        'cleanup' => service.cleanup(
          store,
          completedTasks: true,
          pastEvents: true,
        ),
        _ => service.clear(store),
      };
      await expectLater(future, throwsA(isA<StateError>()));
      expect(store.tasks.map((task) => task.title), [
        'Original',
        'Concurrent edit',
      ]);
      store.dispose();
    });
  }
}
