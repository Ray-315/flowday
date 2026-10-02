import 'package:flutter/material.dart';
import 'theme.dart';

class MiniCalendar extends StatefulWidget {
  const MiniCalendar({
    super.key,
    required this.selected,
    required this.onSelected,
    this.markedDays = const [],
    this.weekStartsMonday = true,
  });
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;
  final List<DateTime> markedDays;
  final bool weekStartsMonday;
  @override
  State<MiniCalendar> createState() => _MiniCalendarState();
}

class _MiniCalendarState extends State<MiniCalendar> {
  late DateTime month = displayDate(
    displayTime(widget.selected).year,
    displayTime(widget.selected).month,
    1,
  );
  @override
  void didUpdateWidget(MiniCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!sameDay(oldWidget.selected, widget.selected)) {
      month = displayDate(
        displayTime(widget.selected).year,
        displayTime(widget.selected).month,
        1,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final offset = widget.weekStartsMonday
        ? month.weekday - 1
        : month.weekday % 7;
    final first = displayDate(month.year, month.month, month.day - offset);
    final rows =
        ((displayDate(month.year, month.month + 1, 0).day + offset) / 7).ceil();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${month.year}年${month.month}月',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: () => setState(
                () => month = displayDate(month.year, month.month - 1, 1),
              ),
              icon: const Icon(Icons.chevron_left, size: 18),
            ),
            IconButton(
              onPressed: () => setState(
                () => month = displayDate(month.year, month.month + 1, 1),
              ),
              icon: const Icon(Icons.chevron_right, size: 18),
            ),
          ],
        ),
        Row(
          children:
              (widget.weekStartsMonday
                      ? ['一', '二', '三', '四', '五', '六', '日']
                      : ['日', '一', '二', '三', '四', '五', '六'])
                  .map(
                    (s) => Expanded(
                      child: Center(
                        child: Text(
                          s,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < rows; row++)
          Row(
            children: List.generate(7, (col) {
              final day = displayDate(
                first.year,
                first.month,
                first.day + row * 7 + col,
              );
              final active = sameDay(day, widget.selected);
              return Expanded(
                child: SizedBox(
                  height: 31,
                  child: InkWell(
                    onTap: () => widget.onSelected(day),
                    borderRadius: BorderRadius.circular(6),
                    child: Column(
                      children: [
                        Container(
                          width: 30,
                          height: 25,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 12,
                              color: active
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : day.month == month.month
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (widget.markedDays.any((d) => sameDay(d, day)))
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }
}
