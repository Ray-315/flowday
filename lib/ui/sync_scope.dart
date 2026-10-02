import 'package:flutter/material.dart';
import '../data/sync_controller.dart';

class SyncScope extends InheritedWidget {
  const SyncScope({super.key, required this.sync, required super.child});
  final SyncController? sync;
  static SyncController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyncScope>()?.sync;
  @override
  bool updateShouldNotify(SyncScope oldWidget) => oldWidget.sync != sync;
}
