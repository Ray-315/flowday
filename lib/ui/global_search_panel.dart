import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/sync_controller.dart';
import '../domain/models.dart';
import '../domain/store.dart';

enum GlobalSearchKind { task, event, project, node, attachment }

class GlobalSearchResult {
  const GlobalSearchResult(this.kind, this.title, this.value);
  final GlobalSearchKind kind;
  final String title;
  final Object value;
}

List<GlobalSearchResult> globalSearchResults(
  FlowStore store,
  String query, {
  List<Map<String, dynamic>> cloudAttachments = const [],
}) {
  final term = query.trim().toLowerCase();
  if (term.isEmpty) return [];
  bool matches(String text) => text.toLowerCase().contains(term);
  final results = <GlobalSearchResult>[];
  final tasks = store.tasks, events = store.events, projects = store.projects;
  results.addAll(
    tasks
        .where(
          (t) => matches('${t.title} ${t.description} ${t.tags.join(' ')}'),
        )
        .take(15)
        .map((t) => GlobalSearchResult(GlobalSearchKind.task, t.title, t)),
  );
  results.addAll(
    events
        .where((e) => matches('${e.title} ${e.notes}'))
        .take(15)
        .map((e) => GlobalSearchResult(GlobalSearchKind.event, e.title, e)),
  );
  results.addAll(
    projects
        .where((p) => matches('${p.title} ${p.description}'))
        .take(15)
        .map((p) => GlobalSearchResult(GlobalSearchKind.project, p.title, p)),
  );
  final visibleProjects = projects
      .where((p) => !p.archived)
      .map((p) => p.id)
      .toSet();
  results.addAll(
    store.data.nodes
        .where(
          (n) =>
              visibleProjects.contains(n.projectId) &&
              matches('${n.title} ${n.description}'),
        )
        .take(15)
        .map((n) => GlobalSearchResult(GlobalSearchKind.node, n.title, n)),
  );
  final attachments = <Map<String, dynamic>>[];
  void addLocal(String type, String owner, List<Attachment> values) {
    for (final a in values) {
      attachments.add({
        'id': a.id,
        'name': a.title,
        'kind': a.kind.name,
        'markdown': a.kind == AttachmentKind.markdown ? a.content : '',
        'url': a.kind == AttachmentKind.url ? a.content : '',
        'ownerType': type,
        'ownerId': owner,
        'local': true,
      });
    }
  }

  for (final t in tasks) {
    addLocal('task', t.id, t.attachments);
  }
  for (final e in events) {
    addLocal('event', e.id, e.attachments);
  }
  for (final p in projects) {
    addLocal('project', p.id, p.attachments);
  }
  final ownerIds = {
    'task': tasks.map((t) => t.id).toSet(),
    'event': events.map((e) => e.id).toSet(),
    'project': projects.map((p) => p.id).toSet(),
  };
  attachments.addAll(
    cloudAttachments.where(
      (a) =>
          a['deletedAt'] == null &&
          (ownerIds[a['ownerType']]?.contains(a['ownerId']) ?? false),
    ),
  );
  final seen = <String>{};
  results.addAll(
    attachments
        .where(
          (a) =>
              matches(
                '${a['name'] ?? ''} ${a['markdown'] ?? ''} ${a['url'] ?? ''}',
              ) &&
              seen.add('${a['ownerType']}:${a['ownerId']}:${a['id']}'),
        )
        .take(15)
        .map(
          (a) => GlobalSearchResult(
            GlobalSearchKind.attachment,
            a['name'] as String? ?? '',
            a,
          ),
        ),
  );
  return results;
}

class GlobalSearchPanel extends StatefulWidget {
  const GlobalSearchPanel({
    super.key,
    required this.store,
    this.sync,
    required this.onTask,
    required this.onEvent,
    required this.onProject,
    required this.onNode,
    required this.onAttachment,
    this.onCreateTask,
    this.onNaturalLanguage,
    this.closeOnActivate = true,
  });
  final FlowStore store;
  final SyncController? sync;
  final ValueChanged<Task> onTask;
  final ValueChanged<CalendarEvent> onEvent;
  final ValueChanged<Project> onProject;
  final ValueChanged<FlowNode> onNode;
  final ValueChanged<Map<String, dynamic>> onAttachment;
  final ValueChanged<String>? onCreateTask, onNaturalLanguage;
  final bool closeOnActivate;
  @override
  State<GlobalSearchPanel> createState() => _GlobalSearchPanelState();
}

class _GlobalSearchPanelState extends State<GlobalSearchPanel> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _attachments = [];
  String? _error;
  int _selected = 0, _generation = 0;
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_changed);
    _load();
  }

  @override
  void didUpdateWidget(GlobalSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_changed);
      widget.store.addListener(_changed);
    }
    if (oldWidget.sync != widget.sync || oldWidget.store != widget.store) {
      _attachments = [];
      _error = null;
      _selected = 0;
      _load();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final generation = ++_generation, sync = widget.sync;
    if (sync == null || !identical(sync.store, widget.store)) return;
    try {
      final response = await sync.api.feature(
        sync.session.token,
        'GET',
        '/attachments',
      );
      if (mounted && generation == _generation) {
        setState(
          () => _attachments = (response['attachments'] as List)
              .map((a) => Map<String, dynamic>.from(a as Map))
              .toList(),
        );
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '附件搜索失败');
      }
    }
  }

  void _activate(VoidCallback callback) {
    if (widget.closeOnActivate) Navigator.pop(context);
    callback();
  }

  VoidCallback _open(GlobalSearchResult result) => () {
    switch (result.kind) {
      case GlobalSearchKind.task:
        widget.onTask(result.value as Task);
      case GlobalSearchKind.event:
        widget.onEvent(result.value as CalendarEvent);
      case GlobalSearchKind.project:
        widget.onProject(result.value as Project);
      case GlobalSearchKind.node:
        widget.onNode(result.value as FlowNode);
      case GlobalSearchKind.attachment:
        widget.onAttachment(result.value as Map<String, dynamic>);
    }
  };
  @override
  void dispose() {
    ++_generation;
    widget.store.removeListener(_changed);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final results = globalSearchResults(
      widget.store,
      query,
      cloudAttachments: _attachments,
    );
    final callbacks = results.map(_open).toList();
    if (query.isNotEmpty && widget.onCreateTask != null) {
      callbacks.add(() => widget.onCreateTask!(query));
    }
    if (query.isNotEmpty && widget.onNaturalLanguage != null) {
      callbacks.add(() => widget.onNaturalLanguage!(query));
    }
    if (_selected >= callbacks.length) {
      _selected = callbacks.isEmpty ? 0 : callbacks.length - 1;
    }
    final icons = [
      Icons.check_box_outlined,
      Icons.event_outlined,
      Icons.folder_outlined,
      Icons.account_tree_outlined,
      Icons.attach_file,
    ];
    final labels = ['任务', '日程', '项目', '节点', '附件'];
    return Dialog(
      child: SizedBox(
        width: 580,
        height: 460,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      _move(1, callbacks.length),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      _move(-1, callbacks.length),
                  const SingleActivator(LogicalKeyboardKey.enter): () {
                    if (callbacks.isNotEmpty) _activate(callbacks[_selected]);
                  },
                },
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  onEditingComplete: () {},
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: '搜索日程、任务、项目、节点、附件',
                  ),
                  onChanged: (_) => setState(() => _selected = 0),
                  onSubmitted: (_) {
                    if (callbacks.isNotEmpty) _activate(callbacks[_selected]);
                  },
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  children: [
                    for (var i = 0; i < results.length; i++)
                      ListTile(
                        selected: i == _selected,
                        leading: Icon(icons[results[i].kind.index], size: 20),
                        title: Text(results[i].title),
                        subtitle: Text(labels[results[i].kind.index]),
                        onTap: () => _activate(callbacks[i]),
                        trailing: results[i].kind == GlobalSearchKind.task
                            ? Checkbox(
                                value:
                                    (results[i].value as Task).status ==
                                    TaskStatus.done,
                                onChanged: (done) => widget.store.setTaskStatus(
                                  (results[i].value as Task).id,
                                  done == true
                                      ? TaskStatus.done
                                      : TaskStatus.todo,
                                ),
                              )
                            : null,
                      ),
                    if (query.isNotEmpty && widget.onCreateTask != null)
                      ListTile(
                        selected: _selected == results.length,
                        leading: const Icon(Icons.add, size: 20),
                        title: const Text('新建任务'),
                        onTap: () =>
                            _activate(() => widget.onCreateTask!(query)),
                      ),
                    if (query.isNotEmpty && widget.onNaturalLanguage != null)
                      ListTile(
                        selected: _selected == callbacks.length - 1,
                        leading: const Icon(
                          Icons.auto_awesome_outlined,
                          size: 20,
                        ),
                        title: const Text('自然语言'),
                        onTap: () =>
                            _activate(() => widget.onNaturalLanguage!(query)),
                      ),
                    if (_error != null)
                      TextButton(
                        onPressed: () {
                          setState(() => _error = null);
                          _load();
                        },
                        child: Text(_error!),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _move(int step, int count) {
    if (count == 0) return;
    setState(() => _selected = (_selected + step) % count);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          (_selected * 72.0).clamp(0.0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }
}
