import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flowday/data/repository.dart';
import 'package:flowday/domain/models.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('flowday-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  test(
    'save and reload preserves data and backup recovers corrupted primary',
    () async {
      final repository = JsonRepository(directory);
      expect((await repository.load()).tasks, isEmpty);
      await repository.save(
        FlowData(
          tasks: [Task(id: 'a', title: 'First')],
        ),
      );
      await repository.save(
        FlowData(
          tasks: [Task(id: 'a', title: 'Second')],
        ),
      );
      expect((await repository.load()).tasks.single.title, 'Second');
      await File('${directory.path}/flowday.json').writeAsString('broken');
      expect((await repository.load()).tasks.single.title, 'First');
    },
  );
  test('invalid data cannot replace valid saved data', () async {
    final repository = JsonRepository(directory);
    await repository.save(
      FlowData(
        tasks: [Task(id: 'a', title: 'Keep')],
      ),
    );
    await expectLater(
      repository.save(
        FlowData(
          tasks: [Task(id: 'a', title: '')],
        ),
      ),
      throwsFormatException,
    );
    expect((await repository.load()).tasks.single.title, 'Keep');
  });
  test('backup exports independently readable snapshot', () async {
    final repository = JsonRepository(directory);
    final file = await repository.backup(FlowData());
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), contains('schemaVersion'));
  });
  test(
    'unrecoverable corruption is reported instead of loading empty data',
    () async {
      await File('${directory.path}/flowday.json').writeAsString('broken');
      await expectLater(
        JsonRepository(directory).load(),
        throwsFormatException,
      );
    },
  );
}
