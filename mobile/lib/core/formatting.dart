import 'package:intl/intl.dart';

/// Money and date formatting.
///
/// Amounts cross the wire as decimal strings, not doubles - the backend stores
/// `Decimal(14,2)` and serialises with `toFixed(2)` precisely so that cents do
/// not drift through a float. Parsing is therefore for display only; nothing
/// here is ever sent back as the source of truth for an amount.
class Money {
  static final _birr = NumberFormat.currency(locale: 'en_US', symbol: 'Br ', decimalDigits: 2);
  static final _plain = NumberFormat('#,##0.00', 'en_US');
  static final _compact = NumberFormat.compact(locale: 'en_US');

  static double parse(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  static String format(Object? value, {String currency = 'ETB'}) {
    final amount = parse(value);
    if (currency == 'ETB') return _birr.format(amount);
    return '$currency ${_plain.format(amount)}';
  }

  /// Signed for a ledger row: income reads `+`, expense reads `-`.
  static String signed(Object? value, String kind, {String currency = 'ETB'}) {
    final formatted = format(value, currency: currency);
    return switch (kind) {
      'INCOME' => '+$formatted',
      'EXPENSE' => '-$formatted',
      _ => formatted,
    };
  }

  static String compact(Object? value) => _compact.format(parse(value));
}

class Dates {
  static final _day = DateFormat('d MMM');
  static final _dayYear = DateFormat('d MMM yyyy');
  static final _full = DateFormat('d MMM yyyy, HH:mm');
  static final _time = DateFormat('HH:mm');

  static DateTime? tryParse(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse('$value')?.toLocal();
  }

  static String day(DateTime? d) =>
      d == null ? '—' : (d.year == DateTime.now().year ? _day.format(d) : _dayYear.format(d));

  static String full(DateTime? d) => d == null ? '—' : _full.format(d);

  static String time(DateTime? d) => d == null ? '—' : _time.format(d);

  /// "just now" / "12m ago" / "3h ago" / a date once it stops being useful.
  static String relative(DateTime? d) {
    if (d == null) return '—';
    final diff = DateTime.now().difference(d);

    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return day(d);
  }
}
