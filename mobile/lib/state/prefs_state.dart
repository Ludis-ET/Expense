import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/format.dart';

/// Device-local preferences: theme, amount masking, and the last-used currency
/// scope. Everything here is deliberately kept off the server.
class PrefsState extends ChangeNotifier {
  PrefsState(this._prefs)
      : _themeMode = _readTheme(_prefs),
        _amountsHidden = _prefs.getBool(_hiddenKey) ?? false,
        _reduceMotion = _prefs.getBool(_motionKey) ?? false;

  static const _themeKey = 'santim.theme';
  static const _hiddenKey = 'santim.amountsHidden';
  static const _motionKey = 'santim.reduceMotion';

  final SharedPreferences _prefs;
  ThemeMode _themeMode;
  bool _amountsHidden;
  bool _reduceMotion;

  static ThemeMode _readTheme(SharedPreferences p) => switch (p.getString(_themeKey)) {
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

  /// `useMoney().money(...)` — formats through the visibility toggle so a single
  /// call site handles both states.
  String money(Object? amount, {String currency = 'ETB', bool decimals = false, bool compact = false}) {
    if (_amountsHidden) return formatHiddenMoney(currency);
    return formatMoney(amount, currency: currency, decimals: decimals, compact: compact);
  }

  String number(Object? value) => _amountsHidden ? formatHiddenNumber() : '$value';
}
