import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/format.dart';

/// Device-local preferences: theme, amount masking, and the last-used currency
/// scope. Everything here is deliberately kept off the server.
class PrefsState extends ChangeNotifier {
  PrefsState(this._prefs)
    : _themeMode = _readTheme(_prefs),
      _amountsHidden = _prefs.getBool(_hiddenKey) ?? false,
      _reduceMotion = _prefs.getBool(_motionKey) ?? false,
      _hiddenCards = (_prefs.getStringList(_cardsHiddenKey) ?? const [])
          .toSet(),
      _cardOrder = _prefs.getStringList(_cardOrderKey) ?? const [],
      _collapsed = (_prefs.getStringList(_collapsedKey) ?? const []).toSet(),
      _onboarded = _prefs.getBool(onboardedKey) ?? false;

  static const _themeKey = 'santim.theme';
  static const _hiddenKey = 'santim.amountsHidden';
  static const _motionKey = 'santim.reduceMotion';
  static const _cardsHiddenKey = 'santim.dashboard.hidden';
  static const _cardOrderKey = 'santim.dashboard.order';
  static const _collapsedKey = 'santim.dashboard.collapsed';

  /// Public so `main()` can pre-set it for an existing install before the
  /// provider tree is built.
  static const onboardedKey = 'santim.onboarded';

  final SharedPreferences _prefs;
  ThemeMode _themeMode;
  bool _amountsHidden;
  bool _reduceMotion;
  Set<String> _hiddenCards;
  List<String> _cardOrder;
  Set<String> _collapsed;
  bool _onboarded;

  SharedPreferences get prefs => _prefs;

  static ThemeMode _readTheme(SharedPreferences p) =>
      switch (p.getString(_themeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  ThemeMode get themeMode => _themeMode;
  bool get amountsHidden => _amountsHidden;
  bool get reduceMotion => _reduceMotion;

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _prefs.setString(_themeKey, mode.name);
  }

  Future<void> toggleAmounts() async {
    _amountsHidden = !_amountsHidden;
    notifyListeners();
    await _prefs.setBool(_hiddenKey, _amountsHidden);
  }

  Future<void> setReduceMotion(bool value) async {
    _reduceMotion = value;
    notifyListeners();
    await _prefs.setBool(_motionKey, value);
  }

  // --- dashboard layout ------------------------------------------------------

  /// Ids the user has switched off in Customise dashboard.
  Set<String> get hiddenCards => _hiddenCards;

  /// User-chosen card order. Empty means "use the built-in order"; ids missing
  /// from the list keep their default position, so a new card added in a later
  /// release still appears for someone who has reordered.
  List<String> get cardOrder => _cardOrder;

  bool isCardVisible(String id) => !_hiddenCards.contains(id);

  Future<void> setCardVisible(String id, bool visible) async {
    if (visible) {
      _hiddenCards.remove(id);
    } else {
      _hiddenCards.add(id);
    }
    _hiddenCards = {..._hiddenCards};
    notifyListeners();
    await _prefs.setStringList(_cardsHiddenKey, _hiddenCards.toList());
  }

  Future<void> setCardOrder(List<String> ids) async {
    _cardOrder = List.unmodifiable(ids);
    notifyListeners();
    await _prefs.setStringList(_cardOrderKey, ids);
  }

  Future<void> resetDashboard() async {
    _hiddenCards = {};
    _cardOrder = const [];
    notifyListeners();
    await _prefs.remove(_cardsHiddenKey);
    await _prefs.remove(_cardOrderKey);
  }

  /// Sorts [ids] by the user's order, keeping unknown ids in their given
  /// position relative to the ones around them.
  List<String> applyOrder(List<String> ids) {
    if (_cardOrder.isEmpty) return ids;
    final rank = {for (var i = 0; i < _cardOrder.length; i++) _cardOrder[i]: i};
    final sorted = [...ids];
    sorted.sort((a, b) {
      final ra = rank[a] ?? rank.length + ids.indexOf(a);
      final rb = rank[b] ?? rank.length + ids.indexOf(b);
      return ra.compareTo(rb);
    });
    return sorted;
  }

  // --- collapsible sections --------------------------------------------------

  bool isCollapsed(String id) => _collapsed.contains(id);

  Future<void> setCollapsed(String id, bool collapsed) async {
    if (collapsed) {
      _collapsed.add(id);
    } else {
      _collapsed.remove(id);
    }
    _collapsed = {..._collapsed};
    notifyListeners();
    await _prefs.setStringList(_collapsedKey, _collapsed.toList());
  }

  // --- first run -------------------------------------------------------------

  bool get onboarded => _onboarded;

  Future<void> completeOnboarding() async {
    _onboarded = true;
    notifyListeners();
    await _prefs.setBool(onboardedKey, true);
  }

  /// Exposed so Settings can offer "show the intro again".
  Future<void> resetOnboarding() async {
    _onboarded = false;
    notifyListeners();
    await _prefs.setBool(onboardedKey, false);
  }

  /// `useMoney().money(...)`   formats through the visibility toggle so a single
  /// call site handles both states.
  String money(
    Object? amount, {
    String currency = 'ETB',
    bool decimals = false,
    bool compact = false,
  }) {
    if (_amountsHidden) return formatHiddenMoney(currency);
    return formatMoney(
      amount,
      currency: currency,
      decimals: decimals,
      compact: compact,
    );
  }

  String number(Object? value) =>
      _amountsHidden ? formatHiddenNumber() : '$value';
}
