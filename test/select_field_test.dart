import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowday/ui/theme.dart';

void main() {
  testWidgets(
    'select opens with keyboard, preserves nullable value and dismisses outside',
    (tester) async {
      String? value;
      await tester.pumpWidget(
        MaterialApp(
          theme: flowTheme(brightness: Brightness.dark),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                child: FlowSelect<String>(
                  initialValue: null,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('无项目')),
                    DropdownMenuItem(
                      value: 'p',
                      child: Text('一个较长的项目名称用于检验菜单宽度'),
                    ),
                  ],
                  onChanged: (v) => value = v,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNWidgets(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      await tester.tap(find.text('无项目'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('一个较长的项目名称用于检验菜单宽度'));
      await tester.pumpAndSettle();
      expect(value, 'p');
      await tester.tap(find.text('一个较长的项目名称用于检验菜单宽度'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'select validation, parent changes and larger text remain usable',
    (tester) async {
      final form = GlobalKey<FormState>();
      Widget page(String? value) => MaterialApp(
        theme: flowTheme(),
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: w!,
        ),
        home: Scaffold(
          body: Form(
            key: form,
            child: Align(
              alignment: Alignment.bottomRight,
              child: SizedBox(
                width: 180,
                child: FlowSelect<String>(
                  initialValue: value,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('无项目')),
                    DropdownMenuItem(value: 'p', child: Text('项目')),
                  ],
                  onChanged: (_) {},
                  validator: (v) => v == null ? '请选择项目' : null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(null));
      expect(form.currentState!.validate(), false);
      await tester.pump();
      expect(find.text('请选择项目'), findsOneWidget);
      await tester.pumpWidget(page('p'));
      await tester.pump();
      expect(form.currentState!.validate(), true);
      await tester.tap(find.text('项目'));
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemButton), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
  test('dark theme text and controls retain contrast', () {
    final t = flowTheme(brightness: Brightness.dark);
    double ratio(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
    }

    expect(
      ratio(t.colorScheme.onSurface, t.colorScheme.surface),
      greaterThan(7),
    );
    expect(
      ratio(t.colorScheme.onSurfaceVariant, t.colorScheme.surface),
      greaterThan(4.5),
    );
    expect(
      ratio(t.colorScheme.primary, t.colorScheme.surface),
      greaterThan(4.5),
    );
  });
}
