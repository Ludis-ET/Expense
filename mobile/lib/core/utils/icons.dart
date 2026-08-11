import 'package:flutter/material.dart';

/// The curated icon set from `components/finance/icons.ts`. Keys are stored in
/// the database, so they must match the web app one for one; the values are the
/// closest Material equivalents to each Lucide glyph.
const Map<String, IconData> financeIcons = {
  'banknote': Icons.payments_outlined,
  'bike': Icons.pedal_bike_outlined,
  'book-open': Icons.menu_book_outlined,
  'briefcase': Icons.work_outline,
  'bus': Icons.directions_bus_outlined,
  'car': Icons.directions_car_outlined,
  'circle': Icons.circle_outlined,
  'circle-ellipsis': Icons.more_horiz,
  'clapperboard': Icons.movie_outlined,
  'coffee': Icons.local_cafe_outlined,
  'credit-card': Icons.credit_card,
  'dumbbell': Icons.fitness_center_outlined,
  'flame': Icons.local_fire_department_outlined,
  'fuel': Icons.local_gas_station_outlined,
  'gamepad-2': Icons.sports_esports_outlined,
  'gift': Icons.card_giftcard_outlined,
  'graduation-cap': Icons.school_outlined,
  'hand-coins': Icons.volunteer_activism_outlined,
  'heart': Icons.favorite_border,
  'heart-pulse': Icons.monitor_heart_outlined,
  'home': Icons.home_outlined,
  'landmark': Icons.account_balance_outlined,
  'laptop': Icons.laptop_mac_outlined,
  'music': Icons.music_note_outlined,
  'paw-print': Icons.pets_outlined,
  'phone': Icons.phone_outlined,
  'piggy-bank': Icons.savings_outlined,
  'pill': Icons.medication_outlined,
  'plane': Icons.flight_outlined,
  'plug-zap': Icons.electrical_services_outlined,
  'plus-circle': Icons.add_circle_outline,
  'repeat': Icons.repeat,
  'shield': Icons.shield_outlined,
  'shirt': Icons.checkroom_outlined,
  'shopping-bag': Icons.shopping_bag_outlined,
  'shopping-basket': Icons.shopping_basket_outlined,
  'shopping-cart': Icons.shopping_cart_outlined,
  'smartphone': Icons.smartphone_outlined,
  'sparkles': Icons.auto_awesome_outlined,
  'store': Icons.storefront_outlined,
  'target': Icons.track_changes_outlined,
  'tree-palm': Icons.beach_access_outlined,
  'trending-up': Icons.trending_up,
  'users': Icons.group_outlined,
  'utensils': Icons.restaurant_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
  'wifi': Icons.wifi_outlined,
  'wrench': Icons.build_outlined,
};

IconData financeIcon(String? name) =>
    (name != null ? financeIcons[name] : null) ?? Icons.circle_outlined;

const iconNames = <String>[
  'banknote',
  'bike',
  'book-open',
  'briefcase',
  'bus',
  'car',
  'circle',
  'circle-ellipsis',
  'clapperboard',
  'coffee',
  'credit-card',
  'dumbbell',
  'flame',
  'fuel',
  'gamepad-2',
  'gift',
  'graduation-cap',
  'hand-coins',
  'heart',
  'heart-pulse',
  'home',
  'landmark',
  'laptop',
  'music',
  'paw-print',
  'phone',
  'piggy-bank',
  'pill',
  'plane',
  'plug-zap',
  'plus-circle',
  'repeat',
  'shield',
  'shirt',
  'shopping-bag',
  'shopping-basket',
  'shopping-cart',
  'smartphone',
  'sparkles',
  'store',
  'target',
  'tree-palm',
  'trending-up',
  'users',
  'utensils',
  'wallet',
  'wifi',
  'wrench',
];

/// Swatches offered by the colour picker   `FINANCE_COLORS`.
const financeColors = <Color>[
  Color(0xFFEF4444),
  Color(0xFFF97316),
  Color(0xFFF59E0B),
  Color(0xFF84CC16),
  Color(0xFF22C55E),
  Color(0xFF10B981),
  Color(0xFF14B8A6),
  Color(0xFF06B6D4),
  Color(0xFF3B82F6),
  Color(0xFF6366F1),
  Color(0xFF8B5CF6),
  Color(0xFFD946EF),
  Color(0xFFEC4899),
  Color(0xFF64748B),
];

/// Parses the `#rrggbb` strings the API stores for categories and accounts.
Color? parseHexColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var v = hex.replaceAll('#', '').trim();
  if (v.length == 3) v = v.split('').map((c) => '$c$c').join();
  if (v.length == 6) v = 'FF$v';
  final parsed = int.tryParse(v, radix: 16);
  return parsed == null ? null : Color(parsed);
}

/// Icon shown for each account type on the wallets screen.
IconData accountTypeIcon(String type) => switch (type) {
  'CASH' => Icons.payments_outlined,
  'BANK' => Icons.account_balance_outlined,
  'MOBILE_MONEY' => Icons.smartphone_outlined,
  'CARD' => Icons.credit_card,
  _ => Icons.account_balance_wallet_outlined,
};
