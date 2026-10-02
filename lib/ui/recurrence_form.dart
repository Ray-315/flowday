import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'theme.dart';

class RecurrenceForm extends StatefulWidget {
  const RecurrenceForm({super.key, this.initialRule, required this.onChanged});
  final RepeatRule? initialRule;
  final ValueChanged<RepeatRule?> onChanged;
  @override
  State<RecurrenceForm> createState() => _RecurrenceFormState();
}

class _RecurrenceFormState extends State<RecurrenceForm> {
  RepeatFrequency? frequency;
  late final TextEditingController interval, count;
  DateTime? until;
  @override
  void initState() {
    super.initState();
    frequency = widget.initialRule?.frequency;
    interval = TextEditingController(
      text: '${widget.initialRule?.interval ?? 1}',
    );
    count = TextEditingController(
      text: widget.initialRule?.count?.toString() ?? '',
    );
    until = widget.initialRule?.until;
  }

  void emit() => widget.onChanged(
    frequency == null
        ? null
        : RepeatRule(
            frequency: frequency!,
            interval: int.tryParse(interval.text) ?? 1,
            count: int.tryParse(count.text),
            until: until,
          ),
  );
  @override
  void dispose() {
    interval.dispose();
    count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowSelect<RepeatFrequency>(
        key: const Key('repeat-frequency'),
        initialValue: frequency,
        decoration: const InputDecoration(labelText: '重复'),
        items: [
          const DropdownMenuItem<RepeatFrequency>(
            value: null,
            child: Text('不重复'),
          ),
          ...RepeatFrequency.values.map(
            (x) => DropdownMenuItem(
              value: x,
              child: Text(const ['每天', '每周', '每月', '每年'][x.index]),
            ),
          ),
        ],
        onChanged: (value) {
          setState(() => frequency = value);
          emit();
        },
      ),
      if (frequency != null) ...[
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const Key('repeat-interval'),
                controller: interval,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '重复间隔'),
                validator: (value) {
                  final number = int.tryParse(value ?? '');
                  return number == null || number < 1 || number > 366
                      ? '请输入 1 至 366 的整数'
                      : null;
                },
                onChanged: (_) => emit(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: const Key('repeat-count'),
                controller: count,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '重复次数'),
                validator: (value) {
                  if (value == null || value.isEmpty) return null;
                  final number = int.tryParse(value);
                  return number == null || number < 1 || number > 1000
                      ? '请输入 1 至 1000 的整数'
                      : null;
                },
                onChanged: (_) => emit(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: until ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (date != null) {
              setState(
                () => until = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  23,
                  59,
                  59,
                  999,
                  999,
                ),
              );
              emit();
            }
          },
          child: Text(until == null ? '设置重复截止日期' : '重复至 ${dateText(until!)}'),
        ),
        if (until != null)
          TextButton(
            onPressed: () {
              setState(() => until = null);
              emit();
            },
            child: const Text('清除重复截止日期'),
          ),
      ],
    ],
  );
}

Future<RepeatScope?> chooseRepeatScope(BuildContext context, String title) =>
    showDialog<RepeatScope>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, RepeatScope.thisOnly),
            child: const Text('仅本次'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, RepeatScope.thisAndFuture),
            child: const Text('本次及以后'),
          ),
        ],
      ),
    );
