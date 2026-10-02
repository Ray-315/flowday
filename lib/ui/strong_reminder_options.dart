import 'package:flutter/material.dart';
import 'theme.dart';

class StrongReminderOptions extends StatelessWidget {
  const StrongReminderOptions({
    super.key,
    required this.strong,
    required this.interval,
    required this.maximum,
    required this.onStrong,
    required this.onInterval,
    required this.onMaximum,
  });
  final bool? strong;
  final int? interval, maximum;
  final ValueChanged<bool?> onStrong;
  final ValueChanged<int?> onInterval, onMaximum;
  Widget number(
    String label,
    int? value,
    int limit,
    ValueChanged<int?> changed,
  ) => TextFormField(
    initialValue: value?.toString() ?? '',
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    validator: (v) {
      if (v == null || v.trim().isEmpty) return null;
      final n = int.tryParse(v.trim());
      return n == null || n < 1 || n > limit ? '请输入 1–$limit' : null;
    },
    onChanged: (v) =>
        changed(v.trim().isEmpty ? null : int.tryParse(v.trim()) ?? -1),
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      FlowSelect<String>(
        initialValue: strong == null
            ? 'inherit'
            : strong!
            ? 'on'
            : 'off',
        decoration: const InputDecoration(labelText: '强提醒'),
        items: const [
          DropdownMenuItem(value: 'inherit', child: Text('继承默认')),
          DropdownMenuItem(value: 'on', child: Text('开启')),
          DropdownMenuItem(value: 'off', child: Text('关闭')),
        ],
        onChanged: (v) => onStrong(v == 'inherit' ? null : v == 'on'),
      ),
      const SizedBox(height: 16),
      number('强提醒间隔（分钟）', interval, 10080, onInterval),
      const SizedBox(height: 16),
      number('最大提醒次数', maximum, 50, onMaximum),
    ],
  );
}
