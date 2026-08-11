import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../models/models.dart';

/// Session owner. Mirrors `lib/auth.tsx`: restores the token on boot, fetches
/// `/users/me`, and clears everything when a refresh finally fails.
class AuthState extends ChangeNotifier {
  AuthState({required this.api, required this.prefs}) {
    api.onUnauthorized.listen((_) {
      if (_user != null) {
        _user = null;
        notifyListeners();
      }
    });
  }

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
    if (api.tokens.access == null) {
      _loading = false;
      notifyListeners();
      return;
    }
    try {
      final json = await api.get<Map<String, dynamic>>('/users/me');
      _user = User.fromJson(json);
    } on ApiError catch (e) {
      // A dead network should not log the user out   only a rejected session.
      if (e.isAuth) await api.tokens.clear();
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
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic> patch) async {
    final json = await api.put<Map<String, dynamic>>('/users/me', body: patch);
    _user = User.fromJson(json);
    notifyListeners();
  }

  Future<void> logout() async {
    await api.tokens.clear();
    _user = null;
    notifyListeners();
  }
}
