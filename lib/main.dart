import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'data/repository.dart';
import 'domain/store.dart';
import 'ui/bootstrap.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final base = await getApplicationSupportDirectory();
    final repository = JsonRepository(Directory('${base.path}/FlowDay'));
    final data = await repository.load();
    runApp(
      FlowBootstrap(
        directory: repository.directory,
        localStore: FlowStore(data, save: repository.save),
      ),
    );
  } catch (error) {
    runApp(
      MaterialApp(
        theme: flowTheme(),
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '无法读取本地数据',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SelectableText('$error'),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: main, child: const Text('重试')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
