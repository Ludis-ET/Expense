import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local app lock: 4–6 digit PIN in secure storage, optional biometrics,
/// and auto-lock when the app goes to the background.
class AppLockState extends ChangeNotifier with WidgetsBindingObserver {
  AppLockState(this._prefs) {
    WidgetsBinding.instance.addObserver(this);
  }

  static const _enabledKey = 'santim.appLock.enabled';
  static const _biometricKey = 'santim.appLock.biometric';
  static const _pinLenKey = 'santim.appLock.pinLen';
  static const _pinHashKey = 'santim.appLock.pinHash';
  static const _pinSaltKey = 'santim.appLock.pinSalt';
  static const pinMin = 4;
  static const pinMax = 6;

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final LocalAuthentication _auth = LocalAuthentication();

  bool _ready = false;
  bool _enabled = false;
  bool _biometric = false;
  bool _locked = false;
  bool _biometricAvailable = false;
  bool _ignoreLifecycle = false;
  int _pinLength = pinMin;
  String? _pinHash;
  String? _pinSalt;

  bool get ready => _ready;
  bool get enabled => _enabled;
  bool get biometricEnabled => _biometric;
  bool get locked => _locked;
  bool get biometricAvailable => _biometricAvailable;
  bool get requiresUnlock => _ready && _enabled && _locked;
  int get pinLength => _pinLength;

  Future<void> bootstrap() async {
    _enabled = _prefs.getBool(_enabledKey) ?? false;
    _biometric = _prefs.getBool(_biometricKey) ?? false;
    _pinLength = _prefs.getInt(_pinLenKey) ?? pinMin;
    if (_enabled) {
      _pinHash = await _secure.read(key: _pinHashKey);
      _pinSalt = await _secure.read(key: _pinSaltKey);
      if (_pinHash == null || _pinSalt == null) {
        _enabled = false;
        await _prefs.setBool(_enabledKey, false);
      } else {
        _locked = true;
      }
    }
    try {
      _biometricAvailable = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      _biometricAvailable = false;
    }
    _ready = true;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled || !_ready || _ignoreLifecycle) return;
    // `paused` only — `inactive` also fires during biometric prompts / system dialogs.
    if (state == AppLifecycleState.paused) {
      if (!_locked) {
        _locked = true;
        notifyListeners();
      }
    }
  }

  String _hash(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  String _newSalt() {
    final now = DateTime.now().microsecondsSinceEpoch.toString();
    return sha256.convert(utf8.encode('santim-$now')).toString().substring(0, 24);
  }

  bool isValidPinFormat(String pin) =>
      RegExp(r'^\d+$').hasMatch(pin) && pin.length >= pinMin && pin.length <= pinMax;

  Future<bool> verifyPin(String pin) async {
    if (!_enabled || _pinHash == null || _pinSalt == null) return false;
    if (!isValidPinFormat(pin)) return false;
    return _hash(pin, _pinSalt!) == _pinHash;
  }

  Future<bool> unlockWithPin(String pin) async {
    final ok = await verifyPin(pin);
    if (!ok) return false;
    _locked = false;
    notifyListeners();
    return true;
  }

  Future<bool> unlockWithBiometric() async {
    if (!_enabled || !_biometric || !_biometricAvailable) return false;
    _ignoreLifecycle = true;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock Santim',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (ok) {
        _locked = false;
        notifyListeners();
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      // Delay so the resume after biometric sheet does not re-lock instantly.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      _ignoreLifecycle = false;
    }
  }

  Future<void> lockNow() async {
    if (!_enabled) return;
    _locked = true;
    notifyListeners();
  }

  Future<void> enableWithPin(String pin) async {
    if (!isValidPinFormat(pin)) {
      throw ArgumentError('PIN must be $pinMin–$pinMax digits');
    }
    final salt = _newSalt();
    final hash = _hash(pin, salt);
    await _secure.write(key: _pinSaltKey, value: salt);
    await _secure.write(key: _pinHashKey, value: hash);
    await _prefs.setBool(_enabledKey, true);
    await _prefs.setInt(_pinLenKey, pin.length);
    _pinSalt = salt;
    _pinHash = hash;
    _pinLength = pin.length;
    _enabled = true;
    _locked = false;
    notifyListeners();
  }

  Future<void> changePin({required String currentPin, required String newPin}) async {
    if (!await verifyPin(currentPin)) {
      throw StateError('Current PIN is incorrect');
    }
    if (!isValidPinFormat(newPin)) {
      throw ArgumentError('PIN must be $pinMin–$pinMax digits');
    }
    final salt = _newSalt();
    final hash = _hash(newPin, salt);
    await _secure.write(key: _pinSaltKey, value: salt);
    await _secure.write(key: _pinHashKey, value: hash);
    await _prefs.setInt(_pinLenKey, newPin.length);
    _pinSalt = salt;
    _pinHash = hash;
    _pinLength = newPin.length;
    notifyListeners();
  }

  Future<void> disable({required String pin}) async {
    if (!await verifyPin(pin)) {
      throw StateError('PIN is incorrect');
    }
    await _secure.delete(key: _pinHashKey);
    await _secure.delete(key: _pinSaltKey);
    await _prefs.setBool(_enabledKey, false);
    await _prefs.setBool(_biometricKey, false);
    await _prefs.remove(_pinLenKey);
    _enabled = false;
    _biometric = false;
    _locked = false;
    _pinHash = null;
    _pinSalt = null;
    _pinLength = pinMin;
    notifyListeners();
  }

  Future<void> setBiometric(bool value) async {
    if (!_enabled) return;
    if (value && !_biometricAvailable) return;
    if (value) {
      _ignoreLifecycle = true;
      try {
        final ok = await _auth.authenticate(
          localizedReason: 'Confirm biometrics for Santim',
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
            useErrorDialogs: true,
          ),
        );
        if (!ok) return;
      } catch (_) {
        return;
      } finally {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        _ignoreLifecycle = false;
      }
    }
    _biometric = value;
    await _prefs.setBool(_biometricKey, value);
    notifyListeners();
  }
}
