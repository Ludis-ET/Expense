import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/native_ingest.dart';
import '../models/finance.dart';
import '../offline/local_db.dart';

enum AuthPhase { loading, signedOut, signedIn }

/// Session state, and the owner of the API base URL.
///
/// The base URL is mutable at runtime because a phone cannot reach the
/// developer's `localhost`: the default points at the emulator loopback and
/// Settings lets you retarget it at a LAN address or a deployed host.
class AuthStore extends ChangeNotifier {
  AuthStore({required this.api, required this.db});

  final ApiClient api;
  final LocalDb db;

  static const _kBaseUrl = 'santim.baseUrl';
  static const _kLastUser = 'santim.lastUser';

  /// Production API on Render. Override at build time with
  /// `--dart-define=SANTIM_API_URL=...` for local/emulator work.
  static const defaultBaseUrl = String.fromEnvironment(
    'SANTIM_API_URL',
    defaultValue: 'https://expense-7py7.onrender.com/api/v1',
  );

  AuthPhase phase = AuthPhase.loading;
  AppUser? user;
  String? lastError;

  /// True when we entered the session from a cached profile because the
  /// server could not be reached. The sync bar says so.
  bool offlineSession = false;

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kBaseUrl);
    // Prefer the baked-in production host over leftover emulator/LAN URLs from
    // an older install, so a release APK does not silently keep pointing at
    // 10.0.2.2 after an upgrade.
    final looksLocal = saved != null &&
        (saved.contains('10.0.2.2') ||
            saved.contains('localhost') ||
            saved.contains('127.0.0.1') ||
            RegExp(r'https?://192\.168\.').hasMatch(saved) ||
            RegExp(r'https?://10\.\d+\.').hasMatch(saved));
    api.baseUrl = (saved == null || looksLocal) ? defaultBaseUrl : saved;
    if (looksLocal) await prefs.setString(_kBaseUrl, defaultBaseUrl);

    await api.loadTokens();
    if (!api.hasSession) {
      _set(AuthPhase.signedOut);
      return;
    }

    // A stored refresh token is only a claim; make the server confirm it before
    // dropping the user into a session that will 401 on the first tap.
    try {
      final me = await api.get('/users/me');
      final map = me as Map<String, dynamic>;
      user = AppUser.fromJson(map);
      await db.put('profile', map);
      await _rememberUser(map);
      offlineSession = false;
      _set(AuthPhase.signedIn);
    } on NetworkException {
      // Tokens are still valid on the phone - open the app on cached data so
      // a tunnel or a dead zone does not strand someone at the login screen.
      final cached = await db.get('profile');
      if (cached?.data is Map<String, dynamic>) {
        user = AppUser.fromJson(cached!.data as Map<String, dynamic>);
        offlineSession = true;
        _set(AuthPhase.signedIn);
        return;
      }

      final remembered = prefs.getString(_kLastUser);
      if (remembered != null) {
        try {
          user = AppUser.fromJson(jsonDecode(remembered) as Map<String, dynamic>);
          offlineSession = true;
          _set(AuthPhase.signedIn);
          return;
        } catch (_) {/* fall through */}
      }

      // No cache to fall back on - stay signed out rather than invent a session.
      _set(AuthPhase.signedOut);
    } catch (_) {
      await api.clearTokens();
      _set(AuthPhase.signedOut);
    }
  }

  Future<void> _rememberUser(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kLastUser,
      jsonEncode({
        'id': map['id'],
        'email': map['email'],
        'name': map['name'],
        'currency': map['currency'] ?? 'ETB',
      }),
    );
  }

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = url.trim().replaceAll(RegExp(r'/$'), '');
    api.baseUrl = normalized;
    await prefs.setString(_kBaseUrl, normalized);

    // The native uploader keeps its own copy - it runs without Dart.
    await NativeIngest.configure(baseUrl: normalized);
    notifyListeners();
  }

  Future<bool> login(String email, String password) =>
      _authenticate('/auth/login', {'email': email, 'password': password});

  Future<bool> register(String name, String email, String password) => _authenticate(
        '/auth/register',
        {'name': name, 'email': email, 'password': password},
      );

  Future<bool> _authenticate(String path, Map<String, dynamic> body) async {
    lastError = null;
    try {
      final data = await api.post(path, body: body) as Map<String, dynamic>;
      await api.setTokens(data['accessToken'] as String, data['refreshToken'] as String);
      final userMap = data['user'] as Map<String, dynamic>;
      user = AppUser.fromJson(userMap);
      await _rememberUser(userMap);
      offlineSession = false;
      _set(AuthPhase.signedIn);
      return true;
    } on ApiException catch (e) {
      lastError = e.message;
      notifyListeners();
      return false;
    } on NetworkException {
      lastError = 'Could not reach the server at ${api.baseUrl}';
      notifyListeners();
      return false;
    } catch (_) {
      lastError = 'Could not reach the server at ${api.baseUrl}';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await api.clearTokens();
    // Signing out must also stop the phone forwarding messages - otherwise
    // capture would keep running against an account nobody is looking at.
    await NativeIngest.clear();
    await db.wipe();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastUser);
    user = null;
    offlineSession = false;
    _set(AuthPhase.signedOut);
  }

  void _set(AuthPhase next) {
    phase = next;
    notifyListeners();
  }
}
