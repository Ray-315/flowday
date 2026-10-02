import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/data/account_repository.dart';
import 'package:flowday/domain/models.dart';

void main() {
  test(
    'account caches isolate servers and users and retain sync baseline',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'flowday-account-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final first = AccountRepository(
        root,
        Uri.parse('https://one.test/api/v1'),
        'u',
      );
      final otherUser = AccountRepository(
        root,
        Uri.parse('https://one.test/api/v1'),
        'other',
      );
      final otherServer = AccountRepository(
        root,
        Uri.parse('https://two.test/api/v1'),
        'u',
      );
      await first.save(
        FlowData(
          tasks: [Task(id: 't', title: '账号一任务')],
        ),
      );
      await first.saveBaseline(1, 'first');
      await first.saveBaseline(2, 'second');
      expect((await first.load()).tasks.single.title, '账号一任务');
      expect((await otherUser.load()).tasks, isEmpty);
      expect((await otherServer.load()).tasks, isEmpty);
      final reopened = AccountRepository(
        root,
        Uri.parse('https://one.test/api/v1'),
        'u',
      );
      expect(await reopened.loadBaseline(), (version: 2, json: 'second'));
      expect(await otherUser.loadBaseline(), (version: null, json: null));
    },
  );
}
