import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/ui/app.dart';
import 'package:flowday/domain/models.dart';
import 'package:flowday/domain/store.dart';

void main() {
  testWidgets('render desktop and mobile previews', (tester) async {
    final font = File('assets/fonts/HarmonyOS_Sans_SC_Regular.ttf');
    if (font.existsSync()) {
      final loader = FontLoader('HarmonyOS Sans SC')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              '.tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
            ).readAsBytesSync(),
          ),
        ),
      );
    await icons.load();
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final data = FlowData(
      projects: [
        Project(id: 'p', title: 'LLM 水印论文', description: '大语言模型文本水印的防御方法研究'),
        Project(id: 'c', title: '研究生课程', color: 0xff8d6bef),
        Project(id: 'l', title: '个人生活', color: 0xff20b69c),
      ],
      tasks: [
        Task(
          id: 't1',
          title: '阅读三篇相关论文',
          projectId: 'p',
          priority: Priority.high,
          estimateMinutes: 180,
          deadline: day.add(const Duration(hours: 15)),
        ),
        Task(
          id: 't2',
          title: '整理实验结果',
          projectId: 'p',
          priority: Priority.high,
          estimateMinutes: 120,
          deadline: day.add(const Duration(hours: 18)),
        ),
        Task(
          id: 't3',
          title: '回复导师邮件',
          projectId: 'p',
          estimateMinutes: 30,
          deadline: day.add(const Duration(hours: 20)),
        ),
        Task(
          id: 't4',
          title: '预习下周课程内容',
          projectId: 'c',
          estimateMinutes: 60,
          deadline: day.add(const Duration(hours: 22)),
        ),
      ],
      events: [
        CalendarEvent(
          id: 'e1',
          title: '机器学习理论课',
          projectId: 'c',
          start: day.add(const Duration(hours: 8, minutes: 30)),
          end: day.add(const Duration(hours: 10)),
          location: '教三 301',
        ),
        CalendarEvent(
          id: 'e2',
          title: '实验：鲁棒性测试',
          projectId: 'p',
          start: day.add(const Duration(hours: 10, minutes: 30)),
          end: day.add(const Duration(hours: 12)),
          color: 0xffff7189,
          location: '实验室',
        ),
        CalendarEvent(
          id: 'e3',
          title: '组会',
          projectId: 'p',
          start: day.add(const Duration(hours: 14)),
          end: day.add(const Duration(hours: 16)),
          color: 0xff8d6bef,
          location: '线上会议',
        ),
        CalendarEvent(
          id: 'e4',
          title: '健身',
          projectId: 'l',
          start: day.add(const Duration(hours: 16, minutes: 30)),
          end: day.add(const Duration(hours: 18)),
          color: 0xff20b69c,
          location: '体育馆',
        ),
        CalendarEvent(
          id: 'e5',
          title: '阅读论文',
          projectId: 'p',
          start: day.add(const Duration(hours: 19)),
          end: day.add(const Duration(hours: 20, minutes: 30)),
          color: 0xfff5b544,
        ),
      ],
      nodes: [
        FlowNode(
          id: 'n1',
          projectId: 'p',
          title: '文献阅读',
          status: NodeStatus.doing,
        ),
        FlowNode(id: 'n2', projectId: 'p', title: '方法设计', x: 300),
      ],
    );
    final store = FlowStore(data);
    for (final mode in ['light', 'dark']) {
      store.data.preferences['themeMode'] = mode;
      for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: FlowDayApp(store: store),
          ),
        );
        await tester.pumpAndSettle();
        for (final page
            in size.width > 850
                ? ['today', 'todo', 'calendar', 'workflow']
                : ['today']) {
          if (page != 'today') {
            await tester.tap(find.byKey(Key('nav-$page')));
            await tester.pumpAndSettle();
          }
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final folder = Directory('docs/screenshots');
            folder.createSync(recursive: true);
            File(
              '${folder.path}/${size.width > 850 ? 'desktop' : 'mobile'}-$page-$mode.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
