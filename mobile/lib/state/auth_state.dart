import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../models/models.dart';

/// Session owner. Mirrors `lib/auth.tsx`: restores the token + last-known user
/// on boot so the app opens offline, then refreshes `/users/me` when online.
class AuthState extends ChangeNotifier {
  AuthState({required this.api, required this.prefs}) {
    api.onUnauthorized.listen((_) {
      _clearCachedUser();
      if (_user != null) {
        _user = null;
        notifyListeners();
      }
    });
  }

  static const _userKey = 'rt.user';

  final ApiClient api;
  final SharedPreferences prefs;

  User? _user;
  bool _loading = true;
  String? _error;

  User? get user => _user;
  bool get loading => _loading;
  bool get isAuthed => _user != null;
  String? get error => _error;

  /// Called once at startup, behind the splash screen.
  Future<void> bootstrap() async {
    if (api.tokens.access == null && api.tokens.refresh == null) {
      _clearCachedUser();
      _loading = false;
      notifyListeners();
      return;
    }

    // Show the last-known user immediately so a cold start offline still
    // lands in the app instead of the login screen.
    final cached = _readCachedUser();
    if (cached != null) {
      _user = cached;
      notifyListeners();
    }

    // No access token but refresh still around — try refresh before /me.
    if (api.tokens.access == null && api.tokens.refresh != null) {
      final refreshed = await api.refreshSession();
      if (refreshed == false) {
        await api.tokens.clear();
        _clearCachedUser();
        _user = null;
        _loading = false;
        notifyListeners();
        return;
      }
      // refreshed == null means network; keep cached user if we have one.
      if (refreshed == null) {
        _loading = false;
        notifyListeners();
        return;
      }
    }

    try {
      final json = await api.get<Map<String, dynamic>>('/users/me');
      _user = User.fromJson(json);
      await _writeCachedUser(_user!);
      _error = null;
    } on ApiError catch (e) {
      // A dead network should not log the user out — only a rejected session.
      if (e.isAuth) {
        await api.tokens.clear();
        _clearCachedUser();
        _user = null;
      } else if (e.isNetwork && _user == null) {
        // Tokens exist but we never cached a profile (pre-offline builds).
        // Keep them signed in with a minimal stub so AppShell + cache can load.
        _user = _offlineStubUser();
      }
      _error = e.isNetwork ? e.message : null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    _error = null;
    final res = await api.post<Map<String, dynamic>>(
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
      skipAuth: true,
    );
    await api.tokens.set(
      res['accessToken'] as String,
      res['refreshToken'] as String,
    );
    final me = await api.get<Map<String, dynamic>>('/users/me');
    _user = User.fromJson(me);
    await _writeCachedUser(_user!);
    notifyListeners();
  }

  Future<void> register(String name, String email, String password) async {
    _error = null;
    final res = await api.post<Map<String, dynamic>>(
      '/auth/register',
      body: {'name': name.trim(), 'email': email.trim(), 'password': password},
      skipAuth: true,
    );
    await api.tokens.set(
      res['accessToken'] as String,
      res['refreshToken'] as String,
    );
    final me = await api.get<Map<String, dynamic>>('/users/me');
    _user = User.fromJson(me);
    await _writeCachedUser(_user!);
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic> patch) async {
    final json = await api.put<Map<String, dynamic>>('/users/me', body: patch);
    _user = User.fromJson(json);
    await _writeCachedUser(_user!);
    notifyListeners();
  }

  Future<void> logout() async {
    await api.tokens.clear();
    _clearCachedUser();
    _user = null;
    notifyListeners();
  }

  User? _readCachedUser() {
    final raw = prefs.getString(_userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return User.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedUser(User user) async {
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  void _clearCachedUser() {
    prefs.remove(_userKey);
  }

  /// Last-resort profile when tokens exist offline but `rt.user` was never saved.
  User _offlineStubUser() => User(
        id: 'offline',
        name: 'You',
        email: '',
        currency: prefs.getString('rt.activeCurrency') ?? 'ETB',
        firstDayOfWeek: 1,
      );
}
