import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Future<void> showFlowLicenses(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const LicensesPanel());

class LicensesPanel extends StatefulWidget {
  const LicensesPanel({super.key, this.entries});
  final Stream<LicenseEntry>? entries;

  @override
  State<LicensesPanel> createState() => _LicensesPanelState();
}

class _LicensesPanelState extends State<LicensesPanel> {
  late final Future<Map<String, List<String>>> licenses = load();
  String? selected;

  Future<Map<String, List<String>>> load() async {
    final result = <String, List<String>>{};
    await for (final entry in widget.entries ?? LicenseRegistry.licenses) {
      final text = entry.paragraphs.map((p) => p.text).join('\n\n');
      for (final package in entry.packages) {
        (result[package] ??= []).add(text);
      }
    }
    return Map.fromEntries(
      result.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 960,
        height: 680,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 650;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                  child: Row(
                    children: [
                      if (!wide && selected != null)
                        IconButton(
                          key: const Key('license-back'),
                          onPressed: () => setState(() => selected = null),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      Expanded(
                        child: Text(
                          !wide && selected != null ? selected! : '开源许可',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        key: const Key('license-close'),
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: FutureBuilder<Map<String, List<String>>>(
                    future: licenses,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            '许可加载失败',
                            style: theme.textTheme.bodyMedium,
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final data = snapshot.data!;
                      if (data.isEmpty) return const SizedBox.shrink();
                      final current =
                          selected ?? (wide ? data.keys.first : null);
                      final list = ListView(
                        padding: const EdgeInsets.all(10),
                        children: data.keys
                            .map(
                              (name) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: ListTile(
                                  key: ValueKey('license-$name'),
                                  selected: current == name,
                                  selectedColor: colors.primary,
                                  selectedTileColor: colors.primary.withValues(
                                    alpha: .08,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  minTileHeight: 44,
                                  title: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  trailing: wide
                                      ? null
                                      : const Icon(
                                          Icons.chevron_right_rounded,
                                          size: 18,
                                        ),
                                  onTap: () => setState(() => selected = name),
                                ),
                              ),
                            )
                            .toList(),
                      );
                      final detail = current == null
                          ? const SizedBox.shrink()
                          : SelectionArea(
                              child: ListView(
                                key: ValueKey('license-detail-$current'),
                                padding: EdgeInsets.all(wide ? 24 : 18),
                                children: [
                                  if (wide) ...[
                                    Text(
                                      current,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                  for (
                                    var i = 0;
                                    i < data[current]!.length;
                                    i++
                                  ) ...[
                                    if (i > 0)
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 24,
                                        ),
                                        child: Divider(),
                                      ),
                                    Text(
                                      data[current]![i],
                                      style: theme.textTheme.bodyMedium!
                                          .copyWith(height: 1.65),
                                    ),
                                  ],
                                ],
                              ),
                            );
                      return wide
                          ? Row(
                              children: [
                                SizedBox(width: 240, child: list),
                                VerticalDivider(
                                  width: 1,
                                  color: theme.dividerColor,
                                ),
                                Expanded(child: detail),
                              ],
                            )
                          : current == null
                          ? list
                          : detail;
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
