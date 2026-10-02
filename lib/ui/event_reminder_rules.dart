import 'package:flutter/material.dart';
import 'theme.dart';

class EventReminderRules extends StatefulWidget {
  const EventReminderRules({
    super.key,
    required this.initialRules,
    required this.onChanged,
    required this.pickDate,
  });
  final List<Map<String, dynamic>>? initialRules;
  final ValueChanged<List<Map<String, dynamic>>?> onChanged;
  final Future<DateTime?> Function(DateTime) pickDate;
  @override
  State<EventReminderRules> createState() => _EventReminderRulesState();
}

class _EventReminderRulesState extends State<EventReminderRules> {
  late List<Map<String, dynamic>>? rules = widget.initialRules
      ?.map((r) => Map<String, dynamic>.from(r))
      .toList();
  void update() {
    setState(() {});
    widget.onChanged(rules?.map((r) => Map<String, dynamic>.from(r)).toList());
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      FlowSelect<String>(
        key: ValueKey(
          rules == null
              ? 'inherit'
              : rules!.isEmpty
              ? 'off'
              : 'custom',
        ),
        initialValue: rules == null
            ? 'inherit'
            : rules!.isEmpty
            ? 'off'
            : 'custom',
        decoration: const InputDecoration(labelText: '提醒规则'),
        items: const [
          DropdownMenuItem(value: 'inherit', child: Text('继承默认')),
          DropdownMenuItem(value: 'off', child: Text('关闭')),
          DropdownMenuItem(value: 'custom', child: Text('自定义')),
        ],
        onChanged: (value) {
          if (value ==
              (rules == null
                  ? 'inherit'
                  : rules!.isEmpty
                  ? 'off'
                  : 'custom')) {
            return;
          }
          rules = value == 'inherit'
              ? null
              : value == 'off'
              ? []
              : [
                  {'leadMinutes': 15},
                ];
          update();
        },
      ),
      if (rules != null && rules!.isNotEmpty) ...[
        for (var i = 0; i < rules!.length; i++)
          Row(
            key: ObjectKey(rules![i]),
            children: [
              Expanded(
                child: rules![i].containsKey('leadMinutes')
                    ? TextFormField(
                        initialValue: '${rules![i]['leadMinutes']}',
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '提前分钟数'),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          return n == null || n < 0 || n > 10080
                              ? '请输入 0–10080 分钟'
                              : null;
                        },
                        onChanged: (v) {
                          rules![i]['leadMinutes'] = int.tryParse(v) ?? -1;
                          widget.onChanged(
                            rules!
                                .map((r) => Map<String, dynamic>.from(r))
                                .toList(),
                          );
                        },
                      )
                    : OutlinedButton(
                        onPressed: () => chooseDate(i),
                        child: Text(
                          '${dateText(DateTime.parse(rules![i]['dueAt'] as String).toLocal())} ${clockText(DateTime.parse(rules![i]['dueAt'] as String).toLocal())}',
                        ),
                      ),
              ),
              IconButton(
                onPressed: () async {
                  if (rules![i].containsKey('leadMinutes')) {
                    await chooseDate(i);
                  } else {
                    rules![i] = {'leadMinutes': 15};
                    update();
                  }
                },
                icon: const Icon(Icons.swap_horiz),
              ),
              IconButton(
                onPressed: () {
                  rules!.removeAt(i);
                  update();
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        TextButton(
          onPressed: rules!.length >= 10
              ? null
              : () {
                  rules!.add({'leadMinutes': 15});
                  update();
                },
          child: const Text('添加提醒'),
        ),
      ],
    ],
  );
  Future<void> chooseDate(int index) async {
    final row = rules![index];
    final date = await widget.pickDate(
      DateTime.tryParse(row['dueAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
    if (date != null &&
        mounted &&
        rules != null &&
        index < rules!.length &&
        identical(rules![index], row)) {
      rules![index] = {'dueAt': date.toUtc().toIso8601String()};
      update();
    }
  }
}
