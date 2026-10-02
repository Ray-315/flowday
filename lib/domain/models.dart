enum TaskStatus { todo, doing, waiting, done, cancelled }

enum Priority { low, normal, high, urgent }

enum Difficulty { low, normal, high }

enum RepeatFrequency { daily, weekly, monthly, yearly }

enum RepeatScope { thisOnly, thisAndFuture }

enum AttachmentKind { file, url, markdown }

class Attachment {
  String id, title, content;
  AttachmentKind kind;
  Attachment({
    required this.id,
    required this.title,
    required this.kind,
    this.content = '',
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'content': content,
  };
  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
    id: j['id'] as String,
    title: j['title'] as String,
    kind: _enum(AttachmentKind.values, j['kind'], AttachmentKind.url),
    content: j['content'] as String? ?? '',
  );
}

class RepeatRule {
  RepeatFrequency frequency;
  int interval;
  int? count;
  DateTime? until;
  RepeatRule({
    required this.frequency,
    this.interval = 1,
    this.count,
    this.until,
  });
  Map<String, dynamic> toJson() => {
    'frequency': frequency.name,
    'interval': interval,
    'count': count,
    'until': until?.toUtc().toIso8601String(),
  };
  factory RepeatRule.fromJson(Map<String, dynamic> j) => RepeatRule(
    frequency: _enum(
      RepeatFrequency.values,
      j['frequency'],
      RepeatFrequency.daily,
    ),
    interval: j['interval'] as int? ?? 1,
    count: j['count'] as int?,
    until: _date(j['until']),
  );
  DateTime occurrence(DateTime anchor, int index) {
    DateTime date(int year, int month, int day) => anchor.isUtc
        ? DateTime.utc(
            year,
            month,
            day,
            anchor.hour,
            anchor.minute,
            anchor.second,
            anchor.millisecond,
            anchor.microsecond,
          )
        : DateTime(
            year,
            month,
            day,
            anchor.hour,
            anchor.minute,
            anchor.second,
            anchor.millisecond,
            anchor.microsecond,
          );
    final steps = interval * index;
    if (frequency == RepeatFrequency.daily ||
        frequency == RepeatFrequency.weekly) {
      return date(
        anchor.year,
        anchor.month,
        anchor.day + steps * (frequency == RepeatFrequency.weekly ? 7 : 1),
      );
    }
    final month = DateTime(
      anchor.year + (frequency == RepeatFrequency.yearly ? steps : 0),
      anchor.month + (frequency == RepeatFrequency.monthly ? steps : 0),
    );
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    return date(
      month.year,
      month.month,
      anchor.day > lastDay ? lastDay : anchor.day,
    );
  }
}

List<Attachment> _attachments(dynamic value) => value == null
    ? []
    : (value as List)
          .map((x) => Attachment.fromJson(Map<String, dynamic>.from(x as Map)))
          .toList();
RepeatRule? _repeat(dynamic value) => value == null
    ? null
    : RepeatRule.fromJson(Map<String, dynamic>.from(value as Map));

enum NodeKind { task, condition, delay, milestone, note, link, group }

enum NodeStatus { locked, ready, doing, waiting, done, skipped }

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();
T _enum<T extends Enum>(List<T> values, dynamic value, T fallback) =>
    value == null
    ? fallback
    : values.firstWhere(
        (e) => e.name == value,
        orElse: () => throw const FormatException('未知状态'),
      );

class Project {
  String id, title, description;
  String? parentId;
  int color;
  DateTime? deadline, deletedAt;
  bool archived;
  List<Attachment> attachments;
  Project({
    required this.id,
    required this.title,
    this.parentId,
    this.description = '',
    this.color = 0xff2680ff,
    this.deadline,
    this.deletedAt,
    this.archived = false,
    List<Attachment>? attachments,
  }) : attachments = attachments ?? [];
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'parentId': parentId,
    'description': description,
    'color': color,
    'deadline': deadline?.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
    'archived': archived,
    'attachments': attachments.map((x) => x.toJson()).toList(),
  };
  factory Project.fromJson(Map<String, dynamic> j) => Project(
    id: j['id'] as String,
    title: j['title'] as String,
    parentId: j['parentId'] as String?,
    description: j['description'] as String? ?? '',
    color: j['color'] as int? ?? 0xff2680ff,
    deadline: _date(j['deadline']),
    deletedAt: _date(j['deletedAt']),
    archived: j['archived'] as bool? ?? false,
    attachments: _attachments(j['attachments']),
  );
}

class Task {
  String id, title, description;
  String? projectId, parentId;
  TaskStatus status;
  Priority priority;
  Difficulty difficulty;
  RepeatRule? repeatRule;
  String? seriesId;
  DateTime? plannedStart, occurrenceDate;
  List<Attachment> attachments;
  int estimateMinutes, actualMinutes;
  DateTime? deadline, completedAt, deletedAt;
  bool splittable;
  bool archived;
  bool? strongReminder;
  int? reminderInterval, maxReminders;
  List<String> tags;
  Task({
    required this.id,
    required this.title,
    this.projectId,
    this.parentId,
    this.description = '',
    this.status = TaskStatus.todo,
    this.priority = Priority.normal,
    this.difficulty = Difficulty.normal,
    this.repeatRule,
    this.seriesId,
    this.plannedStart,
    this.occurrenceDate,
    List<Attachment>? attachments,
    this.estimateMinutes = 60,
    this.actualMinutes = 0,
    this.deadline,
    this.completedAt,
    this.deletedAt,
    this.splittable = true,
    this.archived = false,
    this.strongReminder,
    this.reminderInterval,
    this.maxReminders,
    List<String>? tags,
  }) : tags = tags ?? [],
       attachments = attachments ?? [];
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'projectId': projectId,
    'parentId': parentId,
    'description': description,
    'status': status.name,
    'priority': priority.name,
    'difficulty': difficulty.name,
    'repeatRule': repeatRule?.toJson(),
    'seriesId': seriesId,
    'plannedStart': plannedStart?.toUtc().toIso8601String(),
    'occurrenceDate': occurrenceDate?.toUtc().toIso8601String(),
    'attachments': attachments.map((x) => x.toJson()).toList(),
    'estimateMinutes': estimateMinutes,
    'actualMinutes': actualMinutes,
    'deadline': deadline?.toUtc().toIso8601String(),
    'completedAt': completedAt?.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
    'splittable': splittable,
    'archived': archived,
    'strongReminder': strongReminder,
    'reminderInterval': reminderInterval,
    'maxReminders': maxReminders,
    'tags': tags,
  };
  factory Task.fromJson(Map<String, dynamic> j) => Task(
    id: j['id'] as String,
    title: j['title'] as String,
    projectId: j['projectId'] as String?,
    parentId: j['parentId'] as String?,
    description: j['description'] as String? ?? '',
    status: _enum(TaskStatus.values, j['status'], TaskStatus.todo),
    priority: _enum(Priority.values, j['priority'], Priority.normal),
    difficulty: _enum(Difficulty.values, j['difficulty'], Difficulty.normal),
    repeatRule: _repeat(j['repeatRule']),
    seriesId: j['seriesId'] as String?,
    plannedStart: _date(j['plannedStart']),
    occurrenceDate: _date(j['occurrenceDate']),
    attachments: _attachments(j['attachments']),
    estimateMinutes: j['estimateMinutes'] as int? ?? 60,
    actualMinutes: j['actualMinutes'] as int? ?? 0,
    deadline: _date(j['deadline']),
    completedAt: _date(j['completedAt']),
    deletedAt: _date(j['deletedAt']),
    splittable: j['splittable'] as bool? ?? true,
    archived: j['archived'] as bool? ?? false,
    strongReminder: j['strongReminder'] as bool?,
    reminderInterval: j['reminderInterval'] as int?,
    maxReminders: j['maxReminders'] as int?,
    tags: j['tags'] == null ? null : List<String>.from(j['tags'] as List),
  );
}

class CalendarEvent {
  String id, title, location, notes;
  DateTime start, end;
  String? projectId, taskId;
  int color, actualMinutes;
  bool completed, locked, allDay;
  DateTime? deletedAt;
  RepeatRule? repeatRule;
  String? seriesId;
  DateTime? occurrenceDate;
  List<String> tags;
  List<Attachment> attachments;
  int? reminderLeadMinutes;
  List<Map<String, dynamic>>? reminderRules;
  bool? strongReminder;
  int? reminderInterval, maxReminders;
  CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.projectId,
    this.taskId,
    this.color = 0xff2680ff,
    this.location = '',
    this.notes = '',
    this.completed = false,
    this.locked = false,
    this.allDay = false,
    this.deletedAt,
    this.actualMinutes = 0,
    this.repeatRule,
    this.seriesId,
    this.occurrenceDate,
    List<String>? tags,
    List<Attachment>? attachments,
    this.reminderLeadMinutes,
    this.reminderRules,
    this.strongReminder,
    this.reminderInterval,
    this.maxReminders,
  }) : tags = tags ?? [],
       attachments = attachments ?? [];
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
    'projectId': projectId,
    'taskId': taskId,
    'color': color,
    'location': location,
    'notes': notes,
    'completed': completed,
    'locked': locked,
    'allDay': allDay,
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
    'actualMinutes': actualMinutes,
    'repeatRule': repeatRule?.toJson(),
    'seriesId': seriesId,
    'occurrenceDate': occurrenceDate?.toUtc().toIso8601String(),
    'tags': tags,
    'attachments': attachments.map((x) => x.toJson()).toList(),
    'reminderLeadMinutes': reminderLeadMinutes,
    'strongReminder': strongReminder,
    'reminderInterval': reminderInterval,
    'maxReminders': maxReminders,
    'reminderRules': reminderRules
        ?.map(
          (rule) => {
            ...rule,
            if (rule['dueAt'] != null)
              'dueAt': DateTime.parse(
                rule['dueAt'] as String,
              ).toUtc().toIso8601String(),
          },
        )
        .toList(),
  };
  factory CalendarEvent.fromJson(Map<String, dynamic> j) => CalendarEvent(
    id: j['id'] as String,
    title: j['title'] as String,
    start: DateTime.parse(j['start'] as String).toLocal(),
    end: DateTime.parse(j['end'] as String).toLocal(),
    projectId: j['projectId'] as String?,
    taskId: j['taskId'] as String?,
    color: j['color'] as int? ?? 0xff2680ff,
    location: j['location'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    completed: j['completed'] as bool? ?? false,
    locked: j['locked'] as bool? ?? false,
    allDay: j['allDay'] as bool? ?? false,
    deletedAt: _date(j['deletedAt']),
    actualMinutes: j['actualMinutes'] as int? ?? 0,
    repeatRule: _repeat(j['repeatRule']),
    seriesId: j['seriesId'] as String?,
    occurrenceDate: _date(j['occurrenceDate']),
    tags: j['tags'] == null ? [] : List<String>.from(j['tags'] as List),
    attachments: _attachments(j['attachments']),
    reminderLeadMinutes: j['reminderLeadMinutes'] as int?,
    strongReminder: j['strongReminder'] as bool?,
    reminderInterval: j['reminderInterval'] as int?,
    maxReminders: j['maxReminders'] as int?,
    reminderRules: j['reminderRules'] == null
        ? null
        : (j['reminderRules'] as List)
              .map((rule) => Map<String, dynamic>.from(rule as Map))
              .toList(),
  );
}

class FlowNode {
  String id, projectId, title, description;
  NodeKind kind;
  NodeStatus status;
  String? taskId;
  double x, y;
  bool anyPredecessor;
  String? groupId, targetProjectId, selectedBranchEdgeId;
  bool collapsed;
  bool delayWaiting;
  DateTime? completedAt;
  FlowNode({
    required this.id,
    required this.projectId,
    required this.title,
    this.kind = NodeKind.task,
    this.status = NodeStatus.ready,
    this.taskId,
    this.x = 0,
    this.y = 0,
    this.anyPredecessor = false,
    this.description = '',
    this.groupId,
    this.targetProjectId,
    this.selectedBranchEdgeId,
    this.collapsed = false,
    this.delayWaiting = false,
    this.completedAt,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'title': title,
    'description': description,
    'kind': kind.name,
    'status': status.name,
    'taskId': taskId,
    'x': x,
    'y': y,
    'anyPredecessor': anyPredecessor,
    'groupId': groupId,
    'targetProjectId': targetProjectId,
    'selectedBranchEdgeId': selectedBranchEdgeId,
    'collapsed': collapsed,
    'delayWaiting': delayWaiting,
    'completedAt': completedAt?.toUtc().toIso8601String(),
  };
  factory FlowNode.fromJson(Map<String, dynamic> j) => FlowNode(
    id: j['id'] as String,
    projectId: j['projectId'] as String,
    title: j['title'] as String,
    description: j['description'] as String? ?? '',
    kind: _enum(NodeKind.values, j['kind'], NodeKind.task),
    status: _enum(NodeStatus.values, j['status'], NodeStatus.ready),
    taskId: j['taskId'] as String?,
    x: (j['x'] as num? ?? 0).toDouble(),
    y: (j['y'] as num? ?? 0).toDouble(),
    anyPredecessor: j['anyPredecessor'] as bool? ?? false,
    groupId: j['groupId'] as String?,
    targetProjectId: j['targetProjectId'] as String?,
    selectedBranchEdgeId: j['selectedBranchEdgeId'] as String?,
    collapsed: j['collapsed'] as bool? ?? false,
    delayWaiting: j['delayWaiting'] as bool? ?? false,
    completedAt: _date(j['completedAt']),
  );
}

class FlowEdge {
  String id, projectId, sourceId, targetId, label;
  bool active;
  int delayMinutes;
  DateTime? availableAt;
  FlowEdge({
    required this.id,
    required this.projectId,
    required this.sourceId,
    required this.targetId,
    this.label = '',
    this.active = true,
    this.delayMinutes = 0,
    this.availableAt,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'sourceId': sourceId,
    'targetId': targetId,
    'label': label,
    'active': active,
    'delayMinutes': delayMinutes,
    'availableAt': availableAt?.toUtc().toIso8601String(),
  };
  factory FlowEdge.fromJson(Map<String, dynamic> j) => FlowEdge(
    id: j['id'] as String,
    projectId: j['projectId'] as String,
    sourceId: j['sourceId'] as String,
    targetId: j['targetId'] as String,
    label: j['label'] as String? ?? '',
    active: j['active'] as bool? ?? true,
    delayMinutes: j['delayMinutes'] as int? ?? 0,
    availableAt: _date(j['availableAt']),
  );
}

class Capture {
  String id, text;
  DateTime createdAt;
  bool processed;
  Capture({
    required this.id,
    required this.text,
    required this.createdAt,
    this.processed = false,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'processed': processed,
  };
  factory Capture.fromJson(Map<String, dynamic> j) => Capture(
    id: j['id'] as String,
    text: j['text'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    processed: j['processed'] as bool? ?? false,
  );
}

class AppNotice {
  String id, title, body;
  DateTime createdAt;
  bool read, acknowledged;
  String? taskId;
  String? type, eventId, projectId, nodeId;
  AppNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.acknowledged = false,
    this.taskId,
    this.type,
    this.eventId,
    this.projectId,
    this.nodeId,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'read': read,
    'acknowledged': acknowledged,
    'taskId': taskId,
    'type': type,
    'eventId': eventId,
    'projectId': projectId,
    'nodeId': nodeId,
  };
  factory AppNotice.fromJson(Map<String, dynamic> j) => AppNotice(
    id: j['id'] as String,
    title: j['title'] as String,
    body: j['body'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
    read: j['read'] as bool? ?? false,
    acknowledged: j['acknowledged'] as bool? ?? false,
    taskId: j['taskId'] as String?,
    type: j['type'] as String?,
    eventId: j['eventId'] as String?,
    projectId: j['projectId'] as String?,
    nodeId: j['nodeId'] as String?,
  );
}

class FlowData {
  List<Project> projects;
  List<Task> tasks;
  List<CalendarEvent> events;
  List<FlowNode> nodes;
  List<FlowEdge> edges;
  List<Capture> captures;
  List<AppNotice> notices;
  Map<String, dynamic> preferences;
  FlowData({
    List<Project>? projects,
    List<Task>? tasks,
    List<CalendarEvent>? events,
    List<FlowNode>? nodes,
    List<FlowEdge>? edges,
    List<Capture>? captures,
    List<AppNotice>? notices,
    Map<String, dynamic>? preferences,
  }) : projects = projects ?? [],
       tasks = tasks ?? [],
       events = events ?? [],
       nodes = nodes ?? [],
       edges = edges ?? [],
       captures = captures ?? [],
       notices = notices ?? [],
       preferences = preferences ?? {};
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'projects': projects.map((x) => x.toJson()).toList(),
    'tasks': tasks.map((x) => x.toJson()).toList(),
    'events': events.map((x) => x.toJson()).toList(),
    'nodes': nodes.map((x) => x.toJson()).toList(),
    'edges': edges.map((x) => x.toJson()).toList(),
    'captures': captures.map((x) => x.toJson()).toList(),
    'notices': notices.map((x) => x.toJson()).toList(),
    'preferences': preferences,
  };
  factory FlowData.fromJson(Map<String, dynamic> j) {
    try {
      if (j['schemaVersion'] != 1) throw const FormatException('不支持的数据版本');
      List<T> parse<T>(String key, T Function(Map<String, dynamic>) f) =>
          (j[key] as List)
              .map((x) => f(Map<String, dynamic>.from(x as Map)))
              .toList();
      final data = FlowData(
        projects: parse('projects', Project.fromJson),
        tasks: parse('tasks', Task.fromJson),
        events: parse('events', CalendarEvent.fromJson),
        nodes: parse('nodes', FlowNode.fromJson),
        edges: parse('edges', FlowEdge.fromJson),
        captures: parse('captures', Capture.fromJson),
        notices: parse('notices', AppNotice.fromJson),
        preferences: Map<String, dynamic>.from(j['preferences'] as Map),
      );
      data.validate();
      return data;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('数据字段格式不正确');
    }
  }
  void validate() {
    void check(bool ok, String message) {
      if (!ok) throw FormatException(message);
    }

    Set<String> ids(Iterable<String> values) {
      final list = values.toList();
      final set = list.toSet();
      check(
        list.every((x) => x.trim().isNotEmpty) && set.length == list.length,
        '标识为空或重复',
      );
      return set;
    }

    final p = ids(projects.map((x) => x.id)),
        t = ids(tasks.map((x) => x.id)),
        n = ids(nodes.map((x) => x.id));
    ids(events.map((x) => x.id));
    ids(edges.map((x) => x.id));
    ids(captures.map((x) => x.id));
    ids(notices.map((x) => x.id));
    void ref(String? id, Set<String> all) =>
        check(id == null || all.contains(id), '关联对象不存在');
    void title(String value) => check(value.trim().isNotEmpty, '标题不能为空');
    void attachments(List<Attachment> values) {
      ids(values.map((x) => x.id));
      for (final value in values) {
        title(value.title);
      }
    }

    void repeat(RepeatRule? rule) {
      if (rule == null) return;
      check(rule.interval > 0 && rule.interval <= 366, '重复间隔无效');
      check(
        rule.count == null || (rule.count! > 0 && rule.count! <= 1000),
        '重复次数无效',
      );
    }

    void reminderOverrides(int? interval, int? maximum) {
      check(interval == null || (interval >= 1 && interval <= 10080), '提醒间隔无效');
      check(maximum == null || (maximum >= 1 && maximum <= 50), '提醒次数无效');
    }

    void cycles(Map<String, String?> parents) {
      for (final id in parents.keys) {
        final seen = <String>{};
        String? current = id;
        while (current != null) {
          check(seen.add(current), '父级关系不能形成循环');
          current = parents[current];
        }
      }
    }

    for (final x in projects) {
      title(x.title);
      attachments(x.attachments);
      ref(x.parentId, p);
    }
    cycles({for (final x in projects) x.id: x.parentId});
    for (final x in tasks) {
      title(x.title);
      attachments(x.attachments);
      repeat(x.repeatRule);
      reminderOverrides(x.reminderInterval, x.maxReminders);
      ref(x.projectId, p);
      ref(x.parentId, t);
      check(x.estimateMinutes >= 0 && x.actualMinutes >= 0, '耗时不能为负数');
    }
    cycles({for (final x in tasks) x.id: x.parentId});
    for (final x in events) {
      title(x.title);
      attachments(x.attachments);
      repeat(x.repeatRule);
      reminderOverrides(x.reminderInterval, x.maxReminders);
      ref(x.projectId, p);
      ref(x.taskId, t);
      check(x.end.isAfter(x.start), '结束时间必须晚于开始时间');
      check(x.actualMinutes >= 0, '耗时不能为负数');
      check(
        x.reminderLeadMinutes == null ||
            (x.reminderLeadMinutes! >= 0 && x.reminderLeadMinutes! <= 10080),
        '提醒提前时间无效',
      );
      check(
        x.reminderRules == null || x.reminderRules!.length <= 10,
        '提醒规则数量无效',
      );
      for (final rule in x.reminderRules ?? <Map<String, dynamic>>[]) {
        final lead = rule['leadMinutes'], due = rule['dueAt'];
        check((lead != null) != (due != null), '提醒规则必须指定提前时间或提醒时刻');
        if (lead != null) {
          check(lead is int && lead >= 0 && lead <= 10080, '提醒提前时间无效');
        }
        if (due != null) {
          check(due is String && DateTime.tryParse(due) != null, '提醒时刻无效');
        }
      }
    }
    for (final x in nodes) {
      title(x.title);
      ref(x.projectId, p);
      ref(x.taskId, t);
      check(x.x.isFinite && x.y.isFinite, '节点坐标无效');
      ref(x.targetProjectId, p);
      ref(x.groupId, n);
      if (x.groupId != null) {
        final group = nodes.firstWhere((v) => v.id == x.groupId);
        check(
          group.kind == NodeKind.group && group.projectId == x.projectId,
          '分组必须属于同一项目',
        );
      }
      if (x.selectedBranchEdgeId != null) {
        check(
          x.kind == NodeKind.condition &&
              edges.any(
                (e) => e.id == x.selectedBranchEdgeId && e.sourceId == x.id,
              ),
          '条件出口无效',
        );
      }
    }
    cycles({for (final x in nodes) x.id: x.groupId});
    for (final x in edges) {
      check(x.delayMinutes >= 0, '延迟不能为负数');
      ref(x.projectId, p);
      ref(x.sourceId, n);
      ref(x.targetId, n);
      check(
        nodes.firstWhere((v) => v.id == x.sourceId).projectId == x.projectId &&
            nodes.firstWhere((v) => v.id == x.targetId).projectId ==
                x.projectId,
        '连线必须属于同一项目',
      );
    }
    for (final x in captures) {
      title(x.text);
    }
    for (final x in notices) {
      title(x.title);
      ref(x.taskId, t);
    }
    if (preferences.containsKey('calendarView')) {
      check(
        preferences['calendarView'] is String &&
            const [
              '月',
              '周',
              '日',
              '时间轴',
              '列表',
            ].contains(preferences['calendarView']),
        '日历视图设置无效',
      );
    }
    if (preferences.containsKey('displayName')) {
      final name = preferences['displayName'];
      check(name is String && name.length <= 100, '显示名称设置无效');
    }
    if (preferences.containsKey('weekStartsMonday')) {
      check(preferences['weekStartsMonday'] is bool, '每周起始日设置无效');
    }
    if (preferences.containsKey('overlapStyle')) {
      check(
        preferences['overlapStyle'] is String &&
            const ['并排', '层叠', '聚合'].contains(preferences['overlapStyle']),
        '日程重叠样式设置无效',
      );
    }
    const booleans = [
      'workflowAutoTodo',
      'workflowSkipCompletes',
      'workflowAutoUnlock',
      'workflowCheckDependencies',
      'workflowAllowManualUnlock',
      'workflowShowEdgeLabels',
      'workflowShowDescription',
      'workflowShowEstimate',
      'workflowShowMilestones',
      'workflowAutoLayout',
      'sidebarCollapsed',
      'showNavigationLabels',
      'showSearch',
      'showShortcutHints',
      'reduceMotion',
      'automaticBackup',
      'strongReminder',
    ];
    for (final key in booleans) {
      if (preferences.containsKey(key)) {
        check(preferences[key] is bool, '$key 设置无效');
      }
    }
    final enums = <String, List<String>>{
      'themeMode': ['light', 'dark', 'system'],
      'density': ['comfortable', 'compact', 'spacious'],
      'sidebarPosition': ['left', 'right'],
      'dateFormat': ['chinese', 'YYYY-MM-DD', 'YYYY/MM/DD'],
      'timeFormat': ['24', '12'],
      'fontFamily': ['HarmonyOS Sans SC', 'Microsoft YaHei', 'system'],
      'defaultTaskPriority': ['low', 'normal', 'high', 'urgent'],
      'workflowDefaultPriority': ['low', 'normal', 'high', 'urgent'],
      'workflowDefaultKind': ['task', 'milestone', 'note'],
    };
    for (final entry in enums.entries) {
      if (preferences.containsKey(entry.key)) {
        check(
          entry.value.contains(preferences[entry.key]),
          '${entry.key} 设置无效',
        );
      }
    }
    final ranges = <String, (num, num)>{
      'brandColor': (0xff000000, 0xffffffff),
      'fontScale': (.8, 1.5),
      'defaultEventMinutes': (5, 1440),
      'defaultEstimateMinutes': (5, 1440),
      'workflowEstimateMinutes': (5, 1440),
      'timeStepMinutes': (5, 60),
      'workflowZoom': (25, 200),
      'reminderMinutes': (0, 10080),
      'courseReminderLeadMinutes': (0, 10080),
      'reminderInterval': (1, 10080),
      'maxReminders': (1, 100),
    };
    for (final entry in ranges.entries) {
      if (!preferences.containsKey(entry.key)) continue;
      final v = preferences[entry.key];
      check(
        v is num &&
            v.isFinite &&
            v >= entry.value.$1 &&
            v <= entry.value.$2 &&
            (entry.key == 'fontScale' || v is int),
        '${entry.key} 设置无效',
      );
    }
  }
}
