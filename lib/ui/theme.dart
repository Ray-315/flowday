import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import '../domain/models.dart';
export 'select_field.dart';

const appFontFamily = 'HarmonyOS Sans SC';

const ink = Color(0xff111b40);
const muted = Color(0xff7b88a7);
const blue = Color(0xff237bff);
const line = Color(0xffe8edf6);
const canvas = Color(0xfff6f9fe);
const palette = [
  blue,
  Color(0xff8d6bef),
  Color(0xff20b69c),
  Color(0xffff7189),
  Color(0xfff5b544),
  Color(0xff34a5cd),
];
const taskLabels = ['未开始', '进行中', '等待', '已完成', '已取消'];
const priorityLabels = ['低', '普通', '高', '紧急'];
const nodeLabels = ['锁定', '可开始', '进行中', '等待', '已完成', '已跳过'];
const kindLabels = ['任务', '条件', '等待 / 延迟', '里程碑', '说明', '跨流程跳转', '分组'];

ThemeData flowTheme({
  Brightness brightness = Brightness.light,
  Color seed = blue,
  String density = 'comfortable',
}) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xff15171c) : canvas;
  final surface = dark ? const Color(0xff1d2026) : Colors.white;
  final subdued = dark ? const Color(0xff242831) : const Color(0xfff3f6fb);
  final raised = dark ? const Color(0xff282d36) : Colors.white;
  final stroke = dark ? const Color(0xff353b45) : line;
  final text = dark ? const Color(0xffe8ebf0) : ink;
  final secondary = dark ? const Color(0xffa5adbb) : const Color(0xff697894);
  final accent = dark ? Color.lerp(seed, Colors.white, .24)! : seed;
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
      .copyWith(
        primary: accent,
        onPrimary: dark ? const Color(0xff101723) : Colors.white,
        surface: surface,
        onSurface: text,
        onSurfaceVariant: secondary,
        surfaceContainerLowest: background,
        surfaceContainerLow: subdued,
        surfaceContainer: subdued,
        surfaceContainerHigh: raised,
        surfaceContainerHighest: raised,
        outline: stroke,
        outlineVariant: stroke,
        shadow: Colors.black,
      );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  OutlineInputBorder border(Color c, [double width = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: c, width: width),
  );
  final input = InputDecorationTheme(
    filled: true,
    fillColor: surface,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    hintStyle: TextStyle(
      fontFamily: appFontFamily,
      color: secondary,
      fontSize: 13,
    ),
    labelStyle: TextStyle(
      fontFamily: appFontFamily,
      color: secondary,
      fontSize: 13,
    ),
    floatingLabelStyle: TextStyle(
      fontFamily: appFontFamily,
      color: accent,
      fontSize: 13,
    ),
    prefixIconColor: secondary,
    suffixIconColor: secondary,
    border: border(stroke),
    enabledBorder: border(stroke),
    disabledBorder: border(stroke.withValues(alpha: .55)),
    focusedBorder: border(accent, 1.5),
    errorBorder: border(scheme.error),
    focusedErrorBorder: border(scheme.error, 1.5),
  );
  final menu = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(raised),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(6),
    shadowColor: WidgetStatePropertyAll(
      Colors.black.withValues(alpha: dark ? .35 : .12),
    ),
    side: WidgetStatePropertyAll(BorderSide(color: stroke)),
    shape: WidgetStatePropertyAll(shape),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(5)),
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: appFontFamily,
    fontFamilyFallback: const ['PingFang SC', 'Noto Sans CJK SC'],
  );
  return base.copyWith(
    scaffoldBackgroundColor: background,
    canvasColor: raised,
    dividerColor: stroke,
    visualDensity: density == 'compact'
        ? VisualDensity.compact
        : density == 'spacious'
        ? const VisualDensity(horizontal: 1, vertical: 1)
        : VisualDensity.standard,
    textTheme: base.textTheme
        .copyWith(
          bodyMedium: TextStyle(
            fontFamily: appFontFamily,
            color: text,
            fontSize: 14,
            height: 1.4,
          ),
          bodyLarge: TextStyle(
            fontFamily: appFontFamily,
            color: text,
            fontSize: 15,
            height: 1.4,
          ),
          bodySmall: TextStyle(
            fontFamily: appFontFamily,
            color: secondary,
            fontSize: 12,
            height: 1.4,
          ),
          titleMedium: TextStyle(
            fontFamily: appFontFamily,
            color: text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: TextStyle(
            fontFamily: appFontFamily,
            color: text,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          labelLarge: TextStyle(
            fontFamily: appFontFamily,
            color: text,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        )
        .apply(fontFamily: appFontFamily),
    iconTheme: IconThemeData(color: secondary, size: 20),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: stroke),
      ),
    ),
    inputDecorationTheme: input,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(40, 40),
        backgroundColor: accent,
        foregroundColor: scheme.onPrimary,
        disabledBackgroundColor: subdued,
        disabledForegroundColor: secondary.withValues(alpha: .5),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(40, 40),
        foregroundColor: accent,
        side: BorderSide(color: stroke),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        minimumSize: const Size(32, 36),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: secondary, shape: shape),
    ),
    menuTheme: MenuThemeData(style: menu),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        foregroundColor: WidgetStatePropertyAll(text),
        textStyle: WidgetStatePropertyAll(
          TextStyle(fontFamily: appFontFamily, fontSize: 13),
        ),
        overlayColor: WidgetStatePropertyAll(accent.withValues(alpha: .1)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: raised,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black26,
      textStyle: TextStyle(
        fontFamily: appFontFamily,
        color: text,
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: stroke),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: TextStyle(
        fontFamily: appFontFamily,
        color: text,
        fontSize: 13,
      ),
      inputDecorationTheme: input,
      menuStyle: menu,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: stroke),
      ),
      titleTextStyle: TextStyle(
        fontFamily: appFontFamily,
        color: text,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(
        fontFamily: appFontFamily,
        color: text,
        fontSize: 14,
        height: 1.5,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: stroke, thickness: 1, space: 1),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: BorderSide(color: secondary, width: 1.3),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : secondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accent : stroke,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(5),
      radius: const Radius.circular(4),
      thumbColor: WidgetStatePropertyAll(secondary.withValues(alpha: .35)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: raised,
        border: Border.all(color: stroke),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(
        fontFamily: appFontFamily,
        color: text,
        fontSize: 12,
      ),
    ),
  );
}

class DisplayPreferences {
  static String dateFormat = 'chinese';
  static String timeFormat = '24';
  static String timezone = 'system';
}

DateTime displayTime(DateTime value) {
  if (DisplayPreferences.timezone == 'system') return value.toLocal();
  try {
    return tz.TZDateTime.from(
      value,
      tz.getLocation(DisplayPreferences.timezone),
    );
  } on tz.LocationNotFoundException {
    return value.toLocal();
  }
}

DateTime displayDate(
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
]) {
  if (DisplayPreferences.timezone == 'system') {
    return DateTime(year, month, day, hour, minute);
  }
  try {
    return tz.TZDateTime(
      tz.getLocation(DisplayPreferences.timezone),
      year,
      month,
      day,
      hour,
      minute,
    );
  } on tz.LocationNotFoundException {
    return DateTime(year, month, day, hour, minute);
  }
}

String dateText(DateTime date) {
  date = displayTime(date);
  final separator = DisplayPreferences.dateFormat == 'YYYY/MM/DD' ? '/' : '-';
  if (DisplayPreferences.dateFormat == 'chinese') {
    return '${date.year}年${date.month}月${date.day}日';
  }
  return '${date.year}$separator${date.month.toString().padLeft(2, '0')}$separator${date.day.toString().padLeft(2, '0')}';
}

String shortDate(DateTime date) {
  date = displayTime(date);
  return '${date.month}月${date.day}日';
}

String clockText(DateTime date) {
  date = displayTime(date);
  final hour = DisplayPreferences.timeFormat == '12'
      ? (date.hour % 12 == 0 ? 12 : date.hour % 12)
      : date.hour;
  return '${hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}${DisplayPreferences.timeFormat == '12' ? (date.hour < 12 ? ' AM' : ' PM') : ''}';
}

DateTime dayOnly(DateTime date) {
  date = displayTime(date);
  return displayDate(date.year, date.month, date.day);
}

bool sameDay(DateTime a, DateTime b) {
  a = displayTime(a);
  b = displayTime(b);
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

Color priorityColor(Priority value) => switch (value) {
  Priority.low => palette[2],
  Priority.normal => palette[4],
  _ => palette[3],
};

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        ?action,
      ],
    ),
  );
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color = blue});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).brightness == Brightness.dark
            ? Color.lerp(color, Colors.white, .45)
            : color,
        fontSize: 12,
      ),
    ),
  );
}

class ChoiceBar extends StatelessWidget {
  const ChoiceBar({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });
  final List<String> labels;
  final String selected;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: labels
        .map(
          (label) => TextButton(
            style: TextButton.styleFrom(
              backgroundColor: label == selected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: .1)
                  : Theme.of(context).colorScheme.surfaceContainerLow,
              foregroundColor: label == selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            ),
            onPressed: () => onSelected(label),
            child: Text(label),
          ),
        )
        .toList(),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;

Future<void> showFailure(BuildContext context, Object error) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('操作未完成'),
        content: Text(error.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );

Future<void> openEditor(BuildContext context, Widget child) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭详情',
      barrierColor: Colors.black26,
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      pageBuilder: (context, _, _) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 8,
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width < 600
                ? MediaQuery.sizeOf(context).width
                : 450,
            height: double.infinity,
            child: SafeArea(child: child),
          ),
        ),
      ),
    );
