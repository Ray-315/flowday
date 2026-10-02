import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../data/course_import.dart';
import '../domain/store.dart';
import 'theme.dart';

Future<void> showCourseImport(BuildContext context, FlowStore store) =>
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 720,
          height: MediaQuery.sizeOf(context).height * .85,
          child: CourseImportPanel(store: store),
        ),
      ),
    );

class CourseImportPanel extends StatefulWidget {
  const CourseImportPanel({
    super.key,
    required this.store,
    this.initialSource,
    this.initialFormat = 'csv',
  });
  final FlowStore store;
  final String? initialSource;
  final String initialFormat;
  @override
  State<CourseImportPanel> createState() => _CourseImportPanelState();
}

class _CourseImportPanelState extends State<CourseImportPanel> {
  late String format = widget.initialFormat;
  late String? source = widget.initialSource;
  String? filename;
  DateTime? semesterStart;
  List<String> headers = [];
  final mapping = <String, String>{};
  List<CourseLesson> preview = [];
  final selected = <int>{};
  bool busy = false;
  late final TextEditingController reminder;
  static const labels = {
    'title': '课程名',
    'teacher': '教师',
    'location': '地点',
    'notes': '备注',
    'start': '开始时间',
    'end': '结束时间',
    'weekday': '星期',
    'startTime': '开始时刻',
    'endTime': '结束时刻',
    'startWeek': '起始周',
    'endWeek': '结束周',
    'parity': '单双周',
  };
  List<CourseLesson> get selectedLessons => [
    for (final index in selected.toList()..sort()) preview[index],
  ];
  @override
  void initState() {
    super.initState();
    reminder = TextEditingController(
      text:
          '${widget.store.data.preferences['courseReminderLeadMinutes'] ?? 15}',
    );
    prepareMapping();
  }

  @override
  void dispose() {
    reminder.dispose();
    super.dispose();
  }

  void prepareMapping() {
    headers = [];
    mapping.clear();
    if (source == null || format != 'csv') return;
    List<List<String>> rows;
    try {
      rows = CourseImport.csv(source!.replaceFirst('\ufeff', ''));
    } on FormatException {
      return;
    }
    if (rows.isEmpty) return;
    headers = rows.first;
    for (final key in labels.keys) {
      final header = headers
          .where(
            (h) => CourseImport.aliases[key]!.contains(h.trim().toLowerCase()),
          )
          .firstOrNull;
      if (header != null) mapping[key] = header;
    }
  }

  void invalidate() {
    preview = [];
    selected.clear();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: '课程文件',
            extensions: ['csv', 'json', 'ics'],
            uniformTypeIdentifiers: [
              'public.comma-separated-values-text',
              'public.json',
              'public.ics',
            ],
          ),
        ],
      );
      if (file == null) return;
      final text = await file.readAsString();
      if (!mounted) return;
      setState(() {
        source = text;
        filename = file.name;
        format = file.name.split('.').last.toLowerCase();
        invalidate();
        prepareMapping();
      });
    } catch (error) {
      if (mounted) await showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> parse() async {
    try {
      final lessons = CourseImport.parse(
        source!,
        format,
        semesterStart: semesterStart,
        mapping: mapping,
      );
      setState(() {
        preview = lessons;
        selected
          ..clear()
          ..addAll(List.generate(preview.length, (i) => i));
      });
    } catch (error) {
      if (mounted) await showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => content(context),
  );

  Widget content(BuildContext context) {
    final conflicts = CourseImport.conflicts(
      selectedLessons,
      widget.store.events,
    );
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SectionTitle('导入课程')),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : load,
                icon: const Icon(Icons.file_open_outlined),
                label: Text(filename ?? '选择文件'),
              ),
              SizedBox(
                width: 120,
                child: FlowSelect<String>(
                  key: ValueKey(format),
                  initialValue: format,
                  items: const [
                    DropdownMenuItem(value: 'csv', child: Text('CSV')),
                    DropdownMenuItem(value: 'json', child: Text('JSON')),
                    DropdownMenuItem(value: 'ics', child: Text('ICS')),
                  ],
                  onChanged: (value) => setState(() {
                    format = value!;
                    invalidate();
                    prepareMapping();
                  }),
                ),
              ),
              OutlinedButton(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: semesterStart ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (date != null && mounted) {
                    setState(() {
                      semesterStart = date;
                      invalidate();
                    });
                  }
                },
                child: Text(
                  semesterStart == null ? '学期开始日期' : dateText(semesterStart!),
                ),
              ),
              FilledButton(
                onPressed: source == null || busy ? null : parse,
                child: const Text('预览'),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: reminder,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '课程提前提醒（分钟）'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                if (headers.isNotEmpty)
                  ExpansionTile(
                    title: const Text('字段映射'),
                    children: [
                      for (final entry in labels.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: FlowSelect<String>(
                            key: ValueKey('${entry.key}-${mapping[entry.key]}'),
                            initialValue: mapping[entry.key] ?? '',
                            decoration: InputDecoration(labelText: entry.value),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('无'),
                              ),
                              ...headers.toSet().map(
                                (header) => DropdownMenuItem(
                                  value: header,
                                  child: Text(header),
                                ),
                              ),
                            ],
                            onChanged: (value) => setState(() {
                              mapping[entry.key] = value!;
                              invalidate();
                            }),
                          ),
                        ),
                    ],
                  ),
                for (var i = 0; i < preview.length; i++)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(i),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        selected.add(i);
                      } else {
                        selected.remove(i);
                      }
                    }),
                    title: Text(preview[i].title),
                    subtitle: Text(
                      '${dateText(preview[i].start)} ${clockText(preview[i].start)}–${clockText(preview[i].end)}${preview[i].location.isEmpty ? '' : ' · ${preview[i].location}'}',
                    ),
                  ),
                if (conflicts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const SectionTitle('时间冲突'),
                  for (final conflict in conflicts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${conflict.lesson.title} · ${conflict.title}',
                      ),
                      subtitle: Text(
                        '${dateText(conflict.lesson.start)} ${clockText(conflict.lesson.start)}–${clockText(conflict.lesson.end)}',
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () async {
                        try {
                          final minutes = int.tryParse(reminder.text.trim());
                          if (minutes == null) {
                            throw const FormatException('请输入提醒分钟数');
                          }
                          CourseImport.commit(
                            widget.store,
                            selectedLessons,
                            reminderLeadMinutes: minutes,
                          );
                          Navigator.pop(context);
                        } catch (error) {
                          await showFailure(context, error);
                        }
                      },
                child: const Text('导入'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
