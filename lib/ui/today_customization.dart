import 'package:flutter/material.dart';
import '../domain/store.dart';

const todayModules = <String, String>{
  'capture': '快速输入',
  'timeline': '今日日程',
  'todo': '今日任务',
  'calendar': '日历',
  'overview': '本日概览',
  'workflow': '工作流当前节点',
  'overdue': '逾期',
  'pressure': '本周压力',
  'notices': '通知摘要',
};
const defaultTodayHidden = ['workflow', 'overdue', 'pressure', 'notices'];

List<String> todayModuleOrder(FlowStore store) {
  final values = store.data.preferences['todayModuleOrder'];
  final order = values is List
      ? values
            .whereType<String>()
            .where(todayModules.containsKey)
            .toSet()
            .toList()
      : todayModules.keys.toList();
  return [...order, ...todayModules.keys.where((x) => !order.contains(x))];
}

Set<String> todayHiddenModules(FlowStore store) {
  final values = store.data.preferences['todayHiddenModules'];
  return values is List
      ? values.whereType<String>().where(todayModules.containsKey).toSet()
      : defaultTodayHidden.toSet();
}

Future<void> showTodayCustomization(BuildContext context, FlowStore store) =>
    showDialog<void>(
      context: context,
      builder: (context) => _TodayCustomization(store: store),
    );

class _TodayCustomization extends StatefulWidget {
  const _TodayCustomization({required this.store});
  final FlowStore store;
  @override
  State<_TodayCustomization> createState() => _TodayCustomizationState();
}

class _TodayCustomizationState extends State<_TodayCustomization> {
  late List<String> order;
  late Set<String> hidden;
  @override
  void initState() {
    super.initState();
    order = todayModuleOrder(widget.store);
    hidden = todayHiddenModules(widget.store);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('自定义 Today'),
    content: SizedBox(
      width: 420,
      height: 480,
      child: ReorderableListView.builder(
        itemCount: order.length,
        onReorderItem: (oldIndex, newIndex) => setState(() {
          final item = order.removeAt(oldIndex);
          order.insert(newIndex, item);
        }),
        itemBuilder: (context, index) {
          final id = order[index];
          return ListTile(
            key: ValueKey('today-module-$id'),
            contentPadding: const EdgeInsets.only(right: 32),
            leading: Checkbox(
              key: ValueKey('today-module-toggle-$id'),
              value: !hidden.contains(id),
              onChanged: (value) =>
                  setState(() => value! ? hidden.remove(id) : hidden.add(id)),
            ),
            title: Text(todayModules[id]!),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          widget.store.data.preferences['todayModuleOrder'] = List<String>.from(
            order,
          );
          widget.store.data.preferences['todayHiddenModules'] = hidden.toList();
          widget.store.changed();
          Navigator.pop(context);
        },
        child: const Text('保存'),
      ),
    ],
  );
}
