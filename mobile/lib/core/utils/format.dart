import 'package:intl/intl.dart';

/// Locale per currency, matching `lib/format.ts` so amounts read identically on
/// both clients.
const _currencyLocale = <String, String>{
  'ETB': 'am_ET',
  'USD': 'en_US',
  'EUR': 'en_IE',
  'GBP': 'en_GB',
};

final _cache = <String, NumberFormat>{};

NumberFormat _fmt(String currency, {bool decimals = false, bool compact = false}) {
  final key = '$currency|$decimals|$compact';
  return _cache.putIfAbsent(key, () {
    final locale = _currencyLocale[currency] ?? 'en_US';
    if (compact) {
      return NumberFormat.compactCurrency(
        locale: locale,
        name: currency,
        symbol: currencySymbol(currency),
        decimalDigits: decimals ? 2 : 0,
      );
    }
    return NumberFormat.currency(
      locale: locale,
      name: currency,
      symbol: currencySymbol(currency),
      decimalDigits: decimals ? 2 : 0,
    );
  });
}

String currencySymbol(String currency) => switch (currency) {
      'ETB' => 'Br',
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      'KES' => 'KSh',
      'AED' => 'AED',
      _ => currency,
    };

double toNum(Object? amount) {
  if (amount == null) return 0;
  if (amount is num) return amount.toDouble();
  return double.tryParse('$amount') ?? 0;
}

/// `formatMoney` — "Br 12,450".
String formatMoney(
  Object? amount, {
  String currency = 'ETB',
  bool decimals = false,
  bool compact = false,
}) {
  final value = toNum(amount);
  try {
    return _fmt(currency, decimals: decimals, compact: compact).format(value);
  } catch (_) {
    return '$currency ${value.toStringAsFixed(decimals ? 2 : 0)}';
  }
}

/// Masked balance shown when amounts are hidden (banking-app style).
String formatHiddenMoney([String currency = 'ETB']) => '${currencySymbol(currency)} ••••••';

String formatHiddenNumber() => '••••••';

/// "+Br 500" in green contexts / "−Br 500" in red — the sign is carried here,
/// the colour by the caller.
String formatSignedMoney(Object? amount, String kind, {String currency = 'ETB'}) {
  final formatted = formatMoney(amount, currency: currency);
  return switch (kind) {
    'INCOME' => '+$formatted',
    'EXPENSE' => '−$formatted',
    _ => formatted,
  };
}

/// "2026-07" → "July 2026".
String formatMonthKey(String yyyyMm) {
  final parts = yyyyMm.split('-');
  if (parts.length < 2) return yyyyMm;
  final y = int.tryParse(parts[0]) ?? DateTime.now().year;
  final m = int.tryParse(parts[1]) ?? 1;
  return DateFormat('MMMM yyyy').format(DateTime(y, m));
}

/// "09 Aug 2026"
String formatDate(DateTime? date) =>
    date == null ? '-' : DateFormat('dd MMM yyyy').format(date);

String formatDayMonth(DateTime? date) =>
    date == null ? '-' : DateFormat('d MMM').format(date);

String formatLongDate(DateTime date) => DateFormat('EEEE, d MMMM yyyy').format(date);

String formatTime(DateTime date) => DateFormat('HH:mm').format(date);

/// ISO date the API expects for `date` fields.
String isoDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

String monthKey(DateTime date) => DateFormat('yyyy-MM').format(date);

/// `relativeTime` — "2 days ago", "in 3 hours", "just now".
String relativeTime(DateTime date) {
  final diff = date.difference(DateTime.now());
  final abs = diff.abs();
  final future = diff.inSeconds > 0;

  String plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';

  if (abs.inDays >= 1) {
    if (abs.inDays == 1) return future ? 'tomorrow' : 'yesterday';
    final s = plural(abs.inDays, 'day');
    return future ? 'in $s' : '$s ago';
  }
  if (abs.inHours >= 1) {
    final s = plural(abs.inHours, 'hour');
    return future ? 'in $s' : '$s ago';
  }
  if (abs.inMinutes >= 1) {
    final s = plural(abs.inMinutes, 'minute');
    return future ? 'in $s' : '$s ago';
  }
  return 'just now';
}

/// Groups list headers: "Today", "Yesterday", else the full date.
String dayLabel(DateTime date) {
  final now = DateTime.now();
  final d = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff > 1 && diff < 7) return DateFormat('EEEE').format(date);
  return DateFormat('d MMMM yyyy').format(date);
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0]).join().toUpperCase();
}

/// Signed percentage for delta chips: "+12%" / "−4%".
String formatPct(num? pct, {bool signed = true}) {
  if (pct == null) return '-';
  final rounded = pct.round();
  if (!signed) return '$rounded%';
  return '${rounded >= 0 ? '+' : '−'}${rounded.abs()}%';
}

// ---------------------------------------------------------------------------
// Gregorian ↔ Ethiopic (Amete Mihret), ported from `lib/ethiopian-calendar.ts`.
// 13 months: 12 × 30 days + Pagume (5 or 6), running ~7–8 years behind.
// ---------------------------------------------------------------------------

const _ethiopicEpoch = 1723856; // JDN of 1 Meskerem, year 1

const ethiopianMonths = <String>[
  'Meskerem', 'Tikimt', 'Hidar', 'Tahsas', 'Tir', 'Yekatit', 'Megabit',
  'Miazia', 'Ginbot', 'Sene', 'Hamle', 'Nehase', 'Pagume',
];

int _mod(int n, int m) => ((n % m) + m) % m;

int _gregorianToJdn(int year, int month, int day) {
  final a = ((14 - month) / 12).floor();
  final y = year + 4800 - a;
  final m = month + 12 * a - 3;
  return day +
      ((153 * m + 2) / 5).floor() +
      365 * y +
      (y / 4).floor() -
      (y / 100).floor() +
      (y / 400).floor() -
      32045;
}

class EthiopianDate {
  const EthiopianDate(this.year, this.month, this.day, this.monthName);
  final int year;

  /// 1..13
  final int month;

  /// 1..30
  final int day;
  final String monthName;
}

EthiopianDate toEthiopian(DateTime date) {
  final jdn = _gregorianToJdn(date.year, date.month, date.day);
  final r = _mod(jdn - _ethiopicEpoch, 1461);
  final n = _mod(r, 365) + 365 * (r / 1460).floor();
  final year = 4 * ((jdn - _ethiopicEpoch) / 1461).floor() + (r / 365).floor() - (r / 1460).floor();
  final month = (n / 30).floor() + 1;
  final day = _mod(n, 30) + 1;
  return EthiopianDate(year, month, day, ethiopianMonths[(month - 1).clamp(0, 12)]);
}

/// e.g. "15 Sene 2018"
String formatEthiopian(DateTime? date) {
  if (date == null) return '-';
  final e = toEthiopian(date);
  return '${e.day} ${e.monthName} ${e.year}';
}

/// "Good morning" / "Good afternoon" / "Good evening"
String greeting([DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}
