import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the one-time device token and capture prefs for bank SMS ingest.
class DeviceStore {
  DeviceStore(this._prefs);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  static const _tokenKey = 'santim.deviceToken';
  static const _deviceIdKey = 'santim.deviceId';
  static const _deviceNameKey = 'santim.deviceName';
  static const _captureKey = 'santim.smsCaptureEnabled';
  static const _setupDoneKey = 'santim.smsSetupDone';

  Future<String?> get deviceToken => _secure.read(key: _tokenKey);

  String? get deviceId => _prefs.getString(_deviceIdKey);
  String? get deviceName => _prefs.getString(_deviceNameKey);

  bool get captureEnabled => _prefs.getBool(_captureKey) ?? true;
  bool get setupDone => _prefs.getBool(_setupDoneKey) ?? false;

  bool get isPaired => deviceId != null;

  Future<void> savePairing({
    required String deviceId,
    required String deviceName,
    required String deviceToken,
  }) async {
    await _secure.write(key: _tokenKey, value: deviceToken);
    await _prefs.setString(_deviceIdKey, deviceId);
    await _prefs.setString(_deviceNameKey, deviceName);
    // Setup is not done until the wizard finishes bank mapping.
    await _prefs.setBool(_captureKey, true);
  }

  Future<void> setCaptureEnabled(bool enabled) async {
    await _prefs.setBool(_captureKey, enabled);
  }

  Future<void> setSetupDone(bool done) async {
    await _prefs.setBool(_setupDoneKey, done);
  }

  Future<void> clearPairing() async {
    await _secure.delete(key: _tokenKey);
    await _prefs.remove(_deviceIdKey);
    await _prefs.remove(_deviceNameKey);
    await _prefs.remove(_setupDoneKey);
    await _prefs.setBool(_captureKey, false);
  }
}
