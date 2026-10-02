import 'package:flutter/material.dart';
import '../data/sync_controller.dart';
import 'theme.dart';

class ReminderQueue extends StatefulWidget {
  const ReminderQueue({super.key, required this.controller});
  final SyncController controller;
  @override
  State<ReminderQueue> createState() => _ReminderQueueState();
}

class _ReminderQueueState extends State<ReminderQueue> {
  List<Map<String, dynamic>>? items;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({String? acknowledge}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final c = widget.controller;
      if (acknowledge != null) {
        await c.api.ackReminder(c.session.token, acknowledge);
      }
      final data = await c.api.listReminders(c.session.token);
      if (mounted) setState(() => items = data);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> act(Map<String, dynamic> item, String action) async {
    final c = widget.controller;
    var minutes = 5;
    if (action.startsWith('snooze:')) {
      final selection = action.substring(7);
      action = 'snooze';
      if (selection == 'tomorrow' || selection == 'later') {
        final now = displayTime(DateTime.now());
        var target = selection == 'tomorrow'
            ? displayDate(now.year, now.month, now.day + 1, 9)
            : displayDate(now.year, now.month, now.day, 20);
        if (!target.isAfter(now)) target = now.add(const Duration(hours: 2));
        minutes = target.difference(now).inMinutes;
      } else if (selection == 'custom') {
        final input = TextEditingController(text: '15');
        final value = await showDialog<int>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('稍后提醒'),
            content: TextField(
              controller: input,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '分钟'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final amount = int.tryParse(input.text);
                  if (amount != null && amount >= 1 && amount <= 10080) {
                    Navigator.pop(context, amount);
                  }
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );
        input.dispose();
        if (value == null) return;
        minutes = value;
      } else {
        minutes = int.parse(selection);
      }
    }
    final event = c.store.events
        .where((e) => e.id == item['eventId'])
        .firstOrNull;
    if (!mounted) return;
    if (action == 'postpone' &&
        !await confirm(
          context,
          '延后日程',
          event == null
              ? '将关联日程延后 10 分钟？'
              : '${dateText(event.start)} ${clockText(event.start)}–${clockText(event.end)} → ${dateText(event.start.add(const Duration(minutes: 10)))} ${clockText(event.start.add(const Duration(minutes: 10)))}–${clockText(event.end.add(const Duration(minutes: 10)))}',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await c.remoteMutation((_) async {
        final issued = await c.api.feature(
          c.session.token,
          'POST',
          '/reminders/${item['id']}/actions',
          data: {
            'action': action,
            if (action == 'snooze') 'minutes': minutes,
            if (action == 'postpone') 'minutes': 10,
          },
        );
        await c.api.feature(
          c.session.token,
          'POST',
          '/reminder-actions',
          data: {'token': issued['token']},
        );
      });
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('日程提醒'),
    content: SizedBox(
      width: 520,
      height: 380,
      child: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final item in items ?? <Map<String, dynamic>>[])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item['title'] as String),
                    subtitle: Text(
                      '${dateText(DateTime.parse(item['dueAt'] as String).toLocal())} ${clockText(DateTime.parse(item['dueAt'] as String).toLocal())}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: busy || item['acknowledged'] == true
                              ? null
                              : () => load(acknowledge: item['id'] as String),
                          child: Text(
                            item['acknowledged'] == true ? '已确认' : '确认',
                          ),
                        ),
                        PopupMenuButton<String>(
                          enabled: !busy,
                          onSelected: (action) => act(item, action),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'snooze:5',
                              child: Text('稍后 5 分钟'),
                            ),
                            for (final option in const [
                              ('10', '10 分钟'),
                              ('30', '30 分钟'),
                              ('60', '1 小时'),
                              ('later', '今天晚些时候'),
                              ('tomorrow', '明天'),
                              ('custom', '自定义'),
                            ])
                              PopupMenuItem(
                                value: 'snooze:${option.$1}',
                                child: Text(option.$2),
                              ),
                            if (item['eventId'] != null)
                              const PopupMenuItem(
                                value: 'postpone',
                                child: Text('延后日程 10 分钟'),
                              ),
                            if (item['taskId'] != null) ...[
                              const PopupMenuItem(
                                value: 'start',
                                child: Text('开始任务'),
                              ),
                              const PopupMenuItem(
                                value: 'complete',
                                child: Text('完成任务'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => load(),
        child: const Text('刷新'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
