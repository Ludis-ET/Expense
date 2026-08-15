import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors the web client's `ApiError`.
class ApiError implements Exception {
  ApiError(this.status, this.message, {this.code, this.details});

  final int status;
  final String message;
  final String? code;
  final Object? details;

  bool get isNetwork => status == 0;
  bool get isAuth => status == 401;

  @override
  String toString() => message;
}

/// The access/refresh pair, held in the keystore-backed store.
///
/// These used to live in `SharedPreferences` - an unencrypted XML file in the
/// app's data directory - while the device ingest token and the app-lock PIN
/// both already used `FlutterSecureStorage`. The most sensitive credential in
/// the app was the one stored the least carefully, and with `allowBackup`
/// defaulting to true it was eligible for cloud backup as well.
///
/// [load] must be awaited before the store is read: secure storage is async and
/// the rest of the client wants a synchronous getter, so the pair is held in
/// memory for the session and written through.
class TokenStore {
  TokenStore(this._prefs);

  static const _accessKey = 'rt.accessToken';
  static const _refreshKey = 'rt.refreshToken';
  static const _legacyBaseKey = 'santim.apiBase';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    // Matches the app lock's configuration, so the app uses one mechanism for
    // secrets rather than two.
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? _access;
  String? _refresh;

  String? get access => _access;
  String? get refresh => _refresh;

  /// Reads the pair into memory, migrating any plaintext copy left behind by an
  /// older build. Call once during startup, before the first request.
  Future<void> load() async {
    // Drop any previously saved in-app API base override.
    await _prefs.remove(_legacyBaseKey);

    _access = await _secure.read(key: _accessKey);
    _refresh = await _secure.read(key: _refreshKey);

    // One-time migration: someone updating from a build that kept tokens in
    // plaintext should stay signed in, and the plaintext copy must not survive.
    final legacyAccess = _prefs.getString(_accessKey);
    final legacyRefresh = _prefs.getString(_refreshKey);
    if (legacyAccess != null || legacyRefresh != null) {
      _access ??= legacyAccess;
      _refresh ??= legacyRefresh;
      if (_access != null && _refresh != null) {
        await _write(_access!, _refresh!);
      }
      await _prefs.remove(_accessKey);
      await _prefs.remove(_refreshKey);
    }
  }

  Future<void> _write(String access, String refresh) async {
    await _secure.write(key: _accessKey, value: access);
    await _secure.write(key: _refreshKey, value: refresh);
  }

  Future<void> set(String access, String refresh) async {
    _access = access;
    _refresh = refresh;
    await _write(access, refresh);
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    await _secure.delete(key: _accessKey);
    await _secure.delete(key: _refreshKey);
    // Belt and braces: an interrupted migration could have left these behind.
    await _prefs.remove(_accessKey);
    await _prefs.remove(_refreshKey);
  }
}

/// Thin REST wrapper over the Express API. Refreshes the access token once on
/// a 401 and replays the original request, exactly like `lib/api.ts` does.
class ApiClient {
  ApiClient({required this.tokens, http.Client? httpClient, String? defaultBase})
    : _http = httpClient ?? http.Client(),
      _defaultBase =
          defaultBase ??
          const String.fromEnvironment(
            // Override at build time: `flutter build apk --dart-define=API_BASE=...`
            'API_BASE',
            defaultValue: 'https://expense-7py7.onrender.com/api/v1',
          );

  final TokenStore tokens;
  final http.Client _http;
  final String _defaultBase;

  /// Fires when a refresh fails and the session is unrecoverable.
  final _unauthorized = StreamController<void>.broadcast();
  Stream<void> get onUnauthorized => _unauthorized.stream;

  String get baseUrl => _defaultBase;

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    bool skipAuth = false,
  }) => _request<T>('GET', path, query: query, skipAuth: skipAuth);

  Future<T> post<T>(String path, {Object? body, bool skipAuth = false}) =>
      _request<T>('POST', path, body: body, skipAuth: skipAuth);

  Future<T> put<T>(String path, {Object? body}) =>
      _request<T>('PUT', path, body: body);

  Future<T> patch<T>(String path, {Object? body}) =>
      _request<T>('PATCH', path, body: body);

  Future<T> delete<T>(String path) => _request<T>('DELETE', path);

  /// Device-token auth for SMS ingest routes (no user JWT).
  Future<T> deviceRequest<T>(
    String method,
    String path, {
    required String deviceToken,
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    final uri = _uri(path, query);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-Device-Token': deviceToken,
      'Cache-Control': 'no-cache, no-store, must-revalidate',
    };
    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final streamed = await _http
          .send(req)
          .timeout(const Duration(seconds: 30));
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiError(0, 'The server took too long to respond.');
    } catch (_) {
      throw ApiError(0, 'Cannot reach the server. Check your connection.');
    }

    if (res.statusCode == 204 || res.bodyBytes.isEmpty) {
      if (res.statusCode >= 200 && res.statusCode < 300) return null as T;
      throw ApiError(
        res.statusCode,
        res.reasonPhrase ?? 'Empty response from server',
      );
    }

    Object? data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      data = null;
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final err = (data is Map<String, dynamic>) ? data['error'] : null;
      throw ApiError(
        res.statusCode,
        (err is Map && err['message'] is String)
            ? err['message'] as String
            : res.reasonPhrase ?? 'Request failed',
        code: (err is Map && err['code'] is String)
            ? err['code'] as String
            : null,
        details: (err is Map) ? err['details'] : null,
      );
    }
    return data as T;
  }

  Future<T> _request<T>(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool skipAuth = false,
    bool isRetry = false,
    bool cacheBust = false,
  }) async {
    final uri = _uri(path, query, cacheBust: cacheBust || method == 'GET');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      // Flutter web uses the browser fetch stack   without this, GETs often
      // come back 304 with an empty body and our JSON parser sees null.
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Pragma': 'no-cache',
    };
    final token = tokens.access;
    if (token != null && !skipAuth) headers['Authorization'] = 'Bearer $token';

    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final streamed = await _http
          .send(req)
          .timeout(const Duration(seconds: 30));
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiError(0, 'The server took too long to respond.');
    } catch (_) {
      throw ApiError(0, 'Cannot reach the server. Check your connection.');
    }

    if (res.statusCode == 401 &&
        !skipAuth &&
        !isRetry &&
        tokens.refresh != null) {
      final refreshed = await refreshSession();
      if (refreshed == true) {
        return _request<T>(
          method,
          path,
          body: body,
          query: query,
          isRetry: true,
        );
      }
      // Network blip during refresh must not wipe the session — callers keep
      // their cached data and retry when connectivity returns.
      if (refreshed == null) {
        throw ApiError(0, 'Cannot reach the server. Check your connection.');
      }
      await tokens.clear();
      _unauthorized.add(null);
    }

    // 304 + empty body = browser cache hit; retry once with a cache-buster param.
    if (res.statusCode == 304 && res.bodyBytes.isEmpty && !cacheBust) {
      return _request<T>(
        method,
        path,
        body: body,
        query: query,
        skipAuth: skipAuth,
        isRetry: isRetry,
        cacheBust: true,
      );
    }

    if (res.statusCode == 204 || res.bodyBytes.isEmpty) {
      if (res.statusCode >= 200 && res.statusCode < 300) return null as T;
      throw ApiError(
        res.statusCode,
        res.reasonPhrase ?? 'Empty response from server',
      );
    }

    Object? data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      data = null;
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final err = (data is Map<String, dynamic>) ? data['error'] : null;
      throw ApiError(
        res.statusCode,
        (err is Map && err['message'] is String)
            ? err['message'] as String
            : res.reasonPhrase ?? 'Request failed',
        code: (err is Map && err['code'] is String)
            ? err['code'] as String
            : null,
        details: (err is Map) ? err['details'] : null,
      );
    }
    return data as T;
  }

  Uri _uri(String path, Map<String, dynamic>? query, {bool cacheBust = false}) {
    final uri = Uri.parse('$baseUrl$path');
    final merged = <String, String>{...uri.queryParameters};
    query?.forEach((k, v) {
      if (v == null) return;
      if (v is List) {
        if (v.isEmpty) return;
        merged[k] = v.join(',');
      } else {
        merged[k] = '$v';
      }
    });
    if (cacheBust) merged['_'] = '${DateTime.now().millisecondsSinceEpoch}';
    return uri.replace(queryParameters: merged.isEmpty ? null : merged);
  }

  /// Refresh the access token.
  ///
  /// Returns `true` on success, `false` when the server rejected the refresh
  /// (session dead), and `null` when the network itself failed — so offline
  /// launches never clear a still-valid session.
  Future<bool?> refreshSession() async {
    final refresh = tokens.refresh;
    if (refresh == null) return false;
    try {
      final res = await _http
          .post(
            _uri('/auth/refresh', null),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refresh}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 401 || res.statusCode == 403) return false;
      if (res.statusCode < 200 || res.statusCode >= 300) return false;
      final data =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      await tokens.set(
        data['accessToken'] as String,
        data['refreshToken'] as String,
      );
      return true;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _unauthorized.close();
    _http.close();
  }
}
