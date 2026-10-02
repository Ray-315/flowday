import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A form select sharing the app's anchored menu and input decoration.
class FlowSelect<T> extends StatefulWidget {
  const FlowSelect({
    super.key,
    this.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration = const InputDecoration(),
    this.validator,
    this.isExpanded = true,
    this.isDense = true,
  });
  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final FormFieldValidator<T>? validator;
  final bool isExpanded, isDense;
  @override
  State<FlowSelect<T>> createState() => _FlowSelectState<T>();
}

class _FlowSelectState<T> extends State<FlowSelect<T>> {
  final fieldKey = GlobalKey<FormFieldState<T>>();
  final controller = MenuController();
  final focus = FocusNode();
  bool opened = false;
  @override
  void initState() {
    super.initState();
    focus.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(FlowSelect<T> old) {
    super.didUpdateWidget(old);
    if (old.initialValue != widget.initialValue) {
      final next = widget.initialValue;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.initialValue == next &&
            fieldKey.currentState?.value != next) {
          fieldKey.currentState?.didChange(next);
        }
      });
    }
  }

  @override
  void dispose() {
    focus.removeListener(refresh);
    focus.dispose();
    super.dispose();
  }

  void toggle() {
    if (widget.onChanged == null) return;
    if (controller.isOpen) {
      controller.close();
    } else {
      controller.open();
    }
  }

  @override
  Widget build(BuildContext context) => FormField<T>(
    key: fieldKey,
    initialValue: widget.initialValue,
    validator: widget.validator,
    enabled: widget.onChanged != null,
    builder: (field) => LayoutBuilder(
      builder: (context, c) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final selected = widget.items
            .where((item) => item.value == field.value)
            .firstOrNull;
        final width = c.maxWidth.isFinite ? c.maxWidth : 240.0;
        return MenuAnchor(
          controller: controller,
          childFocusNode: focus,
          useRootOverlay: true,
          crossAxisUnconstrained: false,
          alignmentOffset: const Offset(0, 5),
          onOpen: () => setState(() => opened = true),
          onClose: () => setState(() => opened = false),
          style: MenuStyle(
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(Size(width, 320)),
          ),
          menuChildren: widget.items
              .map(
                (item) => MenuItemButton(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) =>
                          states.contains(WidgetState.hovered) ||
                              states.contains(WidgetState.focused)
                          ? colors.primary.withValues(alpha: .12)
                          : item.value == field.value
                          ? colors.primary.withValues(alpha: .08)
                          : Colors.transparent,
                    ),
                  ),
                  trailingIcon: item.value == field.value
                      ? Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: colors.primary,
                        )
                      : const SizedBox(width: 16),
                  onPressed: !item.enabled
                      ? null
                      : () {
                          field.didChange(item.value);
                          widget.onChanged?.call(item.value);
                          controller.close();
                          focus.requestFocus();
                        },
                  child: DefaultTextStyle.merge(
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: item.value == field.value
                          ? colors.primary
                          : colors.onSurface,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: item.child,
                  ),
                ),
              )
              .toList(),
          builder: (context, _, child) => Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.arrowDown): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            },
            child: Actions(
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    toggle();
                    return null;
                  },
                ),
              },
              child: Focus(
                focusNode: focus,
                skipTraversal: widget.onChanged == null,
                child: Semantics(
                  button: true,
                  expanded: opened,
                  enabled: widget.onChanged != null,
                  child: MouseRegion(
                    cursor: widget.onChanged == null
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onChanged == null
                          ? null
                          : () {
                              focus.requestFocus();
                              toggle();
                            },
                      child: InputDecorator(
                        isFocused: focus.hasFocus || opened,
                        isEmpty: selected == null,
                        decoration: widget.decoration.copyWith(
                          enabled: widget.onChanged != null,
                          errorText: field.errorText,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: DefaultTextStyle.merge(
                                style: theme.textTheme.bodyMedium!.copyWith(
                                  color: widget.onChanged == null
                                      ? colors.onSurface.withValues(alpha: .38)
                                      : colors.onSurface,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                child:
                                    selected?.child ??
                                    Text(widget.decoration.hintText ?? ''),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              opened
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: colors.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
