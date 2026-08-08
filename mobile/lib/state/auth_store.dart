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
/// Defaults to the local API. Override with `--dart-define=SANTIM_API_URL=...`
/// for production, or change it in Settings on the device.
class AuthStore extends ChangeNotifier {
  AuthStore({required this.api, required this.db});

  final ApiClient api;
  final LocalDb db;

  static const _kBaseUrl = 'santim.baseUrl';
  static const _kLastUser = 'santim.lastUser';

  /// Local API during development. Override at build time with
  /// `--dart-define=SANTIM_API_URL=https://expense-7py7.onrender.com/api/v1`
  /// for production APKs.
  static const defaultBaseUrl = String.fromEnvironment(
    'SANTIM_API_URL',
    defaultValue: 'http://localhost:4000/api/v1',
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
    // Prefer local default over a leftover Render URL from an older session,
    // so browser/dev previews hit the machine running `npm run dev`.
    final looksRemote = saved != null &&
        (saved.contains('onrender.com') || saved.contains('https://expense'));
    api.baseUrl = (saved == null || looksRemote) ? defaultBaseUrl : saved;
    if (looksRemote || saved == null) await prefs.setString(_kBaseUrl, defaultBaseUrl);

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

  Future<void> updateProfile(Map<String, dynamic> body) async {
    final map = await api.put('/users/me', body: body) as Map<String, dynamic>;
    final userMap = map['user'] is Map<String, dynamic>
        ? map['user'] as Map<String, dynamic>
        : map;
    // Merge so partial responses don't blank fields the client already knows.
    final merged = <String, dynamic>{
      if (user != null) ...{
        'id': user!.id,
        'email': user!.email,
        'name': user!.name,
        'currency': user!.currency,
        'locale': user!.locale,
        'calendar': user!.calendar,
        'firstDayOfWeek': user!.firstDayOfWeek,
        'avatarId': user!.avatarId,
        'bannerId': user!.bannerId,
      },
      ...userMap,
      ...body,
    };
    user = AppUser.fromJson(merged);
    await db.put('profile', merged);
    await _rememberUser(merged);
    notifyListeners();
  }

  Future<void> refreshUser() async {
    final me = await api.get('/users/me');
    final map = me as Map<String, dynamic>;
    user = AppUser.fromJson(map);
    await db.put('profile', map);
    await _rememberUser(map);
    notifyListeners();
  }

  void _set(AuthPhase next) {
    phase = next;
    notifyListeners();
  }
}
