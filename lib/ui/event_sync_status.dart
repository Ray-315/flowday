import 'package:flutter/material.dart';
import '../data/sync_controller.dart';
import 'theme.dart';

class EventSyncStatus extends StatefulWidget {
  const EventSyncStatus({super.key, required this.sync, required this.eventId});
  final SyncController sync;
  final String eventId;
  @override
  State<EventSyncStatus> createState() => _EventSyncStatusState();
}

class _EventSyncStatusState extends State<EventSyncStatus> {
  Map<String, dynamic>? record;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(EventSyncStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sync != widget.sync || oldWidget.eventId != widget.eventId) {
      record = null;
      error = null;
      load();
    }
  }

  Future<void> load() async {
    final request = ++generation;
    try {
      final data = await widget.sync.api.feature(
        widget.sync.session.token,
        'GET',
        '/integrations/apple',
      );
      final found = (data['records'] as List? ?? [])
          .cast<Map>()
          .where((r) => r['eventId'] == widget.eventId)
          .firstOrNull;
      if (mounted && generation == request) {
        setState(() {
          record = found == null ? null : Map<String, dynamic>.from(found);
          error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == request) {
        setState(() => error = 'Apple 日历状态读取失败');
      }
    }
  }

  @override
  void dispose() {
    ++generation;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) return TextButton(onPressed: load, child: Text(error!));
    final value = record;
    if (value == null) return const SizedBox.shrink();
    final source = value['source'] == 'apple'
        ? 'Apple 日历'
        : value['source'] == 'local'
        ? 'FlowDay'
        : '${value['source']}';
    final status = switch (value['status']) {
      'synced' => '已同步',
      'pending' => '待同步',
      'conflict' => '同步冲突',
      _ => '${value['status']}',
    };
    final date = DateTime.tryParse(
      value['lastSyncAt'] as String? ?? '',
    )?.toLocal();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('$source · $status'),
      subtitle: date == null
          ? null
          : Text('上次同步 ${dateText(date)} ${clockText(date)}'),
      trailing: IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
    );
  }
}
