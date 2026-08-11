import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import '../core/utils/format.dart';
import 'ui.dart';

/// Field wrapper: label on the left, the `(i)` hint beside it, error underneath.
class FieldShell extends StatelessWidget {
  const FieldShell({
    super.key,
    required this.child,
    this.label,
    this.hint,
    this.error,
    this.trailing,
  });

  final Widget child;
  final String? label;
  final String? hint;
  final String? error;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Row(
            children: [
              Text(
                label!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: t.mutedForeground,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(width: 5),
                InfoHint(label: label!, body: hint!, size: 14),
              ],
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 7),
        ],
        child,
        if (error != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.error_outline, size: 13, color: t.danger),
              const SizedBox(width: 5),
              Expanded(
                child: Text(error!, style: TextStyle(fontSize: 12, color: t.danger)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.placeholder,
    this.error,
    this.keyboardType,
    this.obscure = false,
    this.maxLines = 1,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.sentences,
    this.inputFormatters,
    this.enabled = true,
    this.textInputAction,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? placeholder;
  final String? error;
  final TextInputType? keyboardType;
  final bool obscure;
  final int maxLines;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return FieldShell(
      label: label,
      hint: hint,
      error: error,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscure,
        maxLines: obscure ? 1 : maxLines,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        autofocus: autofocus,
        enabled: enabled,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        textInputAction: textInputAction,
        cursorColor: t.primary,
        style: TextStyle(fontSize: 15, color: t.foreground),
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: TextStyle(fontSize: 15, color: t.mutedForeground.withValues(alpha: 0.7)),
          prefixIcon: prefixIcon == null
              ? null
              : Icon(prefixIcon, size: 18, color: t.mutedForeground),
          prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),
          suffixIcon: suffix,
          filled: true,
          fillColor: t.surfaceMuted.withValues(alpha: t.isDark ? 0.55 : 0.7),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: prefixIcon == null ? 14 : 4,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.md),
            borderSide: BorderSide(color: t.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.md),
            borderSide: BorderSide(color: t.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.md),
            borderSide: BorderSide(color: t.ring, width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(R.md),
            borderSide: BorderSide(color: t.danger),
          ),
        ),
      ),
    );
  }
}

/// The big amount input at the top of the transaction form: currency symbol,
/// oversized digits, and a colour that tracks income vs expense.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.currency,
    this.tint,
    this.autofocus = false,
    this.label = 'Amount',
    this.error,
  });

  final TextEditingController controller;
  final String currency;
  final Color? tint;
  final bool autofocus;
  final String label;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = tint ?? t.foreground;
    return FieldShell(
      label: label,
      error: error,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: t.surfaceMuted.withValues(alpha: t.isDark ? 0.5 : 0.65),
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: t.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              currencySymbol(currency),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: autofocus,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                cursorColor: t.primary,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: t.mutedForeground.withValues(alpha: 0.35),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            Text(
              currency,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pressable field that opens a picker sheet — the mobile stand-in for a
/// `<select>`.
class PickerField<T> extends StatelessWidget {
  const PickerField({
    super.key,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.label,
    this.hint,
    this.placeholder = 'Select',
    this.iconOf,
    this.colorOf,
    this.subtitleOf,
    this.error,
    this.sheetTitle,
    this.allowClear = false,
    this.enabled = true,
    this.leading,
  });

  final T? value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;
  final String? label;
  final String? hint;
  final String placeholder;
  final IconData Function(T)? iconOf;
  final Color Function(T)? colorOf;
  final String Function(T)? subtitleOf;
  final String? error;
  final String? sheetTitle;
  final bool allowClear;
  final bool enabled;
  final Widget? leading;

  Future<void> _open(BuildContext context) async {
    HapticFeedback.selectionClick();
    await showAppSheet<void>(
      context,
      title: sheetTitle ?? label ?? 'Select',
      builder: (ctx) => _PickerList<T>(
        value: value,
        options: options,
        labelOf: labelOf,
        iconOf: iconOf,
        colorOf: colorOf,
        subtitleOf: subtitleOf,
        allowClear: allowClear,
        onPick: (v) {
          Navigator.pop(ctx);
          onChanged(v);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final has = value != null;
    final tint = has && colorOf != null ? colorOf!(value as T) : null;

    return FieldShell(
      label: label,
      hint: hint,
      error: error,
      child: PressableScale(
        scale: 0.985,
        onTap: enabled && options.isNotEmpty ? () => _open(context) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: t.surfaceMuted.withValues(alpha: t.isDark ? 0.55 : 0.7),
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: t.border),
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 10)]
                else if (has && iconOf != null) ...[
                  IconTile(icon: iconOf!(value as T), color: tint, size: 30, radius: R.sm),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    has ? labelOf(value as T) : placeholder,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: has ? FontWeight.w600 : FontWeight.w400,
                      color: has ? t.foreground : t.mutedForeground.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                Icon(Icons.expand_more, size: 19, color: t.mutedForeground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerList<T> extends StatefulWidget {
  const _PickerList({
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onPick,
    required this.allowClear,
    this.iconOf,
    this.colorOf,
    this.subtitleOf,
  });

  final T? value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T?> onPick;
  final bool allowClear;
  final IconData Function(T)? iconOf;
  final Color Function(T)? colorOf;
  final String Function(T)? subtitleOf;

  @override
  State<_PickerList<T>> createState() => _PickerListState<T>();
}

class _PickerListState<T> extends State<_PickerList<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final searchable = widget.options.length > 7;
    final items = _query.isEmpty
        ? widget.options
        : widget.options
            .where((o) => widget.labelOf(o).toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: AppTextField(
              placeholder: 'Search',
              prefixIcon: Icons.search,
              onChanged: (v) => setState(() => _query = v),
              textCapitalization: TextCapitalization.none,
            ),
          ),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            itemCount: items.length + (widget.allowClear ? 1 : 0),
            itemBuilder: (context, i) {
              if (widget.allowClear && i == 0) {
                return ListTile(
                  onTap: () => widget.onPick(null),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
                  leading: Icon(Icons.block, size: 20, color: t.mutedForeground),
                  title: Text(
                    'None',
                    style: TextStyle(fontSize: 14.5, color: t.mutedForeground),
                  ),
                );
              }
              final o = items[i - (widget.allowClear ? 1 : 0)];
              final selected = o == widget.value;
              final tint = widget.colorOf?.call(o);
              return FadeInUp.staggered(
                index: i.clamp(0, 8),
                offset: 6,
                child: ListTile(
                  onTap: () => widget.onPick(o),
                  selected: selected,
                  selectedTileColor: t.primary.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  leading: widget.iconOf == null
                      ? null
                      : IconTile(icon: widget.iconOf!(o), color: tint, size: 36),
                  title: Text(
                    widget.labelOf(o),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: t.foreground,
                    ),
                  ),
                  subtitle: widget.subtitleOf == null
                      ? null
                      : Muted(widget.subtitleOf!(o), size: 12),
                  trailing: selected
                      ? Icon(Icons.check_circle, size: 20, color: t.primary)
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Segmented control — the income/expense/transfer switch and every two- or
/// three-way filter in the app.
class SegmentedTabs<T> extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.colorOf,
    this.iconOf,
    this.height = 42,
    this.expand = true,
  });

  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final Color Function(T)? colorOf;
  final IconData Function(T)? iconOf;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surfaceMuted.withValues(alpha: t.isDark ? 0.6 : 0.8),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(
        children: [
          for (final o in options)
            Builder(
              builder: (context) {
                final selected = o == value;
                final tint = colorOf?.call(o) ?? t.primary;
                final tab = GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (!selected) {
                      HapticFeedback.selectionClick();
                      onChanged(o);
                    }
                  },
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    curve: Motion.easeOut,
                    padding: EdgeInsets.symmetric(horizontal: expand ? 6 : 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? t.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(R.sm + 2),
                      boxShadow: selected ? t.cardShadow : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (iconOf != null) ...[
                          Icon(
                            iconOf!(o),
                            size: 15,
                            color: selected ? tint : t.mutedForeground,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            labelOf(o),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected ? tint : t.mutedForeground,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
                return expand ? Expanded(child: tab) : tab;
              },
            ),
        ],
      ),
    );
  }
}

/// Date field that opens the platform picker, themed to the app palette.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.firstDate,
    this.lastDate,
    this.allowClear = false,
    this.placeholder = 'Pick a date',
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? label;
  final String? hint;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool allowClear;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return FieldShell(
      label: label,
      hint: hint,
      child: PressableScale(
        scale: 0.985,
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? now,
            firstDate: firstDate ?? DateTime(now.year - 8),
            lastDate: lastDate ?? DateTime(now.year + 8),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(
                colorScheme: Theme.of(ctx).colorScheme.copyWith(
                      primary: t.primary,
                      onPrimary: t.primaryForeground,
                      surface: t.surfaceElevated,
                      onSurface: t.foreground,
                    ),
                dialogTheme: DialogThemeData(backgroundColor: t.surfaceElevated),
              ),
              child: child!,
            ),
          );
          if (picked != null) onChanged(picked);
        },
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: t.surfaceMuted.withValues(alpha: t.isDark ? 0.55 : 0.7),
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: t.border),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 16, color: t.mutedForeground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value == null ? placeholder : formatDate(value),
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: value == null ? FontWeight.w400 : FontWeight.w600,
                    color: value == null ? t.mutedForeground : t.foreground,
                  ),
                ),
              ),
              if (value != null && allowClear)
                GestureDetector(
                  onTap: () => onChanged(null),
                  child: Icon(Icons.close, size: 16, color: t.mutedForeground),
                )
              else if (value != null)
                Muted(formatEthiopian(value), size: 11),
            ],
          ),
        ),
      ),
    );
  }
}

/// Toggle row with a title, optional hint, and a switch on the right.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return InkWell(
      borderRadius: BorderRadius.circular(R.md),
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: t.mutedForeground),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.foreground,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Muted(subtitle!, size: 12),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: t.primary,
              activeTrackColor: t.primary.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }
}

/// Colour swatch grid used by the category and account editors.
class ColorPickerRow extends StatelessWidget {
  const ColorPickerRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.colors,
    this.label = 'Colour',
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final List<Color> colors;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FieldShell(
      label: label,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final c in colors)
            Builder(
              builder: (context) {
                final hex = '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
                final selected = value?.toLowerCase() == hex;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(hex);
                  },
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? context.t.foreground : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: selected
                          ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 10)]
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Icon grid used by the category and account editors.
class IconPickerGrid extends StatelessWidget {
  const IconPickerGrid({
    super.key,
    required this.value,
    required this.onChanged,
    required this.names,
    required this.iconOf,
    this.tint,
    this.label = 'Icon',
  });

  final String? value;
  final ValueChanged<String> onChanged;
  final List<String> names;
  final IconData Function(String) iconOf;
  final Color? tint;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return FieldShell(
      label: label,
      child: SizedBox(
        height: 132,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: names.length,
          itemBuilder: (context, i) {
            final name = names[i];
            final selected = name == value;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(name);
              },
              child: AnimatedContainer(
                duration: Motion.fast,
                decoration: BoxDecoration(
                  color: selected
                      ? (tint ?? t.primary).withValues(alpha: 0.16)
                      : t.surfaceMuted.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(R.sm),
                  border: Border.all(
                    color: selected ? (tint ?? t.primary) : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  iconOf(name),
                  size: 18,
                  color: selected ? (tint ?? t.primary) : t.mutedForeground,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
