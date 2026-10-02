import 'package:flutter/material.dart';
import '../data/sync_controller.dart';
import 'theme.dart';
import 'editors.dart';

Future<void> showAiPanel(
  BuildContext context,
  SyncController sync, {
  String text = '',
  List<String>? taskIds,
}) => openEditor(context, AiPanel(sync: sync, text: text, taskIds: taskIds));

class AiPanel extends StatefulWidget {
  const AiPanel({super.key, required this.sync, this.text = '', this.taskIds});
  final SyncController sync;
  final String text;
  final List<String>? taskIds;
  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<AiPanel> {
  late final input = TextEditingController(text: widget.text);
  Map<String, dynamic>? preview;
  List<Map<String, dynamic>> audit = [];
  String? candidate;
  final selected = <int>{};
  String? error;
  bool busy = false, replan = false;
  final excluded = <Map<String, String>>[];
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> propose({bool schedule = false}) => run(() async {
    await widget.sync.sync();
    if (widget.sync.error != null ||
        widget.sync.conflict ||
        widget.sync.localDirty) {
      throw StateError(widget.sync.error ?? '请先处理同步冲突');
    }
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, now.hour + 1);
    final result = await widget.sync.api.feature(
      widget.sync.session.token,
      'POST',
      schedule ? '/ai/schedule' : '/ai/preview',
      data: schedule
          ? {
              'taskIds':
                  widget.taskIds ??
                  widget.sync.store.tasks
                      .where(
                        (t) =>
                            t.status.name != 'done' &&
                            t.status.name != 'cancelled' &&
                            t.parentId == null,
                      )
                      .map((t) => t.id)
                      .toList(),
              'start': start.toUtc().toIso8601String(),
              'end': start
                  .add(const Duration(days: 7))
                  .toUtc()
                  .toIso8601String(),
              'timezone': requestTimezone,
              'replan': replan,
              'excluded': excluded,
            }
          : {'text': input.text.trim(), 'timezone': requestTimezone},
    );
    if (!mounted) return;
    setState(() {
      preview = result;
      candidate = null;
      selected.clear();
    });
    choose((result['candidates'] as List?)?.firstOrNull as Map?);
  });

  void choose(Map? plan) {
    final intent = plan?['intent'] as Map? ?? preview?['intent'] as Map?;
    setState(() {
      candidate = plan?['id'] as String?;
      selected
        ..clear()
        ..addAll(
          List.generate((intent?['actions'] as List? ?? []).length, (i) => i),
        );
    });
  }

  Map? get plan => (preview?['candidates'] as List? ?? [])
      .cast<Map>()
      .where((p) => p['id'] == candidate)
      .firstOrNull;
  String get requestTimezone {
    final configured = widget.sync.store.data.preferences['timezone'];
    if (configured != null && configured != 'system') {
      return configured as String;
    }
    final minutes = DateTime.now().timeZoneOffset.inMinutes;
    if (minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return hours == 0
          ? 'UTC'
          : 'Etc/GMT${hours > 0 ? '-' : '+'}${hours.abs()}';
    }
    return switch (minutes) {
      330 => 'Asia/Kolkata',
      345 => 'Asia/Kathmandu',
      570 => 'Australia/Darwin',
      _ => 'UTC',
    };
  }

  List get actions =>
      ((plan?['intent'] ?? preview?['intent']) as Map?)?['actions'] as List? ??
      [];

  Future<void> apply() => run(() async {
    final approved = await confirm(
      context,
      '确认变更',
      '应用已选择的 ${selected.length} 项操作？',
    );
    if (!approved) return;
    await widget.sync.remoteMutation((version) async {
      await widget.sync.api.feature(
        widget.sync.session.token,
        'POST',
        '/ai/apply',
        data: {
          'previewId': preview!['previewId'],
          'baseVersion': version,
          if (candidate != null) 'candidateId': candidate,
          'actionIndexes': selected.toList()..sort(),
        },
      );
    });
    if (mounted) setState(() => preview = null);
  });

  Future<void> history() => run(() async {
    final result = await widget.sync.api.feature(
      widget.sync.session.token,
      'GET',
      '/audit',
    );
    if (mounted) {
      setState(
        () => audit = (result['records'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
    }
  });

  Future<void> excludeDay() async {
    final now = displayTime(DateTime.now());
    final day = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
    );
    if (day == null || !mounted) return;
    setState(
      () => excluded.add({
        'start': displayDate(
          day.year,
          day.month,
          day.day,
        ).toUtc().toIso8601String(),
        'end': displayDate(
          day.year,
          day.month,
          day.day + 1,
        ).toUtc().toIso8601String(),
      }),
    );
  }

  String describeDiff(int index) {
    final differences = plan?['diff'] as List? ?? [];
    if (index >= differences.length) return '';
    final diff = differences[index] as Map;
    final before = diff['before'] as Map?;
    final after = diff['after'] as Map?;
    if (before == null || after == null) return '';
    const names = {
      'title': '标题',
      'start': '开始',
      'end': '结束',
      'deadline': '截止',
      'status': '状态',
      'projectId': '项目',
      'dueAt': '提醒时间',
      'intervalMinutes': '提醒间隔',
      'maxReminders': '提醒次数',
    };
    return names.entries
        .where((e) => before[e.key] != after[e.key])
        .map(
          (e) => '${e.value}：${before[e.key] ?? '无'} → ${after[e.key] ?? '无'}',
        )
        .join('\n');
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 12, 14),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '智能安排',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
      const Divider(),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: input,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: '安排内容'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: busy ? null : () => propose(),
                  child: const Text('解析预览'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => propose(schedule: true),
                  child: const Text('安排本周'),
                ),
                TextButton(
                  onPressed: busy ? null : history,
                  child: const Text('操作记录'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => openEditor(
                          context,
                          TaskEditor(
                            store: widget.sync.store,
                            initialTitle: input.text.trim(),
                          ),
                        ),
                  child: const Text('手动创建任务'),
                ),
                TextButton(
                  onPressed: busy ? null : excludeDay,
                  child: const Text('排除日期'),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('重新安排未完成任务'),
              value: replan,
              onChanged: busy ? null : (v) => setState(() => replan = v),
            ),
            for (final entry in excluded.indexed)
              ListTile(
                title: Text(dateText(DateTime.parse(entry.$2['start']!))),
                trailing: IconButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => excluded.removeAt(entry.$1)),
                  icon: const Icon(Icons.close),
                ),
              ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (preview != null) ...[
              const SizedBox(height: 20),
              RadioGroup<String>(
                groupValue: candidate,
                onChanged: (v) {
                  if (busy) return;
                  choose(
                    (preview!['candidates'] as List? ?? [])
                        .cast<Map>()
                        .where((p) => p['id'] == v)
                        .firstOrNull,
                  );
                },
                child: Column(
                  children: [
                    for (final p
                        in (preview!['candidates'] as List? ?? []).cast<Map>())
                      ListTile(
                        title: Text('${p['label'] ?? p['name'] ?? '方案'}'),
                        leading: Radio<String>(value: '${p['id']}'),
                        onTap: busy ? null : () => choose(p),
                      ),
                  ],
                ),
              ),
              for (final indexed in actions.indexed)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${(indexed.$2 as Map)['title'] ?? (indexed.$2 as Map)['id'] ?? ''}',
                  ),
                  subtitle: Text(
                    [
                      describe(indexed.$2 as Map),
                      describeDiff(indexed.$1),
                    ].where((s) => s.isNotEmpty).join('\n'),
                  ),
                  value: selected.contains(indexed.$1),
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          if (v!) {
                            selected.add(indexed.$1);
                          } else {
                            selected.remove(indexed.$1);
                          }
                        }),
                ),
              FilledButton(
                onPressed: busy || selected.isEmpty ? null : apply,
                child: const Text('确认应用'),
              ),
            ],
            for (final item in audit)
              ListTile(
                title: Text('${item['action'] ?? item['type'] ?? ''}'),
                subtitle: Text('${item['createdAt'] ?? ''}'),
                trailing: item['reversible'] != true
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.undo),
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                if (!await confirm(
                                  context,
                                  '撤销操作',
                                  '恢复此次操作前的数据？',
                                )) {
                                  return;
                                }
                                await widget.sync.remoteMutation((
                                  version,
                                ) async {
                                  await widget.sync.api.feature(
                                    widget.sync.session.token,
                                    'POST',
                                    '/audit/${Uri.encodeComponent(item['id'] as String)}/undo',
                                    data: {'baseVersion': version},
                                  );
                                });
                              }),
                      ),
              ),
          ],
        ),
      ),
    ],
  );
  String describe(Map a) {
    final kind = switch (a['type']) {
      'todo' => '创建任务',
      'event' => '创建日程',
      'todo_update' => '修改任务',
      'event_update' => '修改日程',
      'event_delete' => '删除日程',
      'todo_delete' => '删除任务',
      'reminder' => '创建提醒',
      'reminder_update' => '修改提醒',
      _ => '变更',
    };
    return [
      kind,
      if (a['start'] != null) '${a['start']} → ${a['end']}',
      if (a['status'] != null) '${a['status']}',
      if (a['dueAt'] != null) '${a['dueAt']}',
    ].join('\n');
  }
}
