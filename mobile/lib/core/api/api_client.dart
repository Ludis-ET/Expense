import 'dart:async';
import 'dart:convert';

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

/// Persisted access/refresh pair. Keys match the web app so a user reading
/// support docs sees the same names.
class TokenStore {
  TokenStore(this._prefs);

  static const _accessKey = 'rt.accessToken';
  static const _refreshKey = 'rt.refreshToken';
  static const _baseKey = 'santim.apiBase';

  final SharedPreferences _prefs;

  String? get access => _prefs.getString(_accessKey);
  String? get refresh => _prefs.getString(_refreshKey);
  String? get customBase => _prefs.getString(_baseKey);

  Future<void> set(String access, String refresh) async {
    await _prefs.setString(_accessKey, access);
    await _prefs.setString(_refreshKey, refresh);
  }

  Future<void> setBase(String? base) async {
    if (base == null || base.isEmpty) {
      await _prefs.remove(_baseKey);
    } else {
      await _prefs.setString(_baseKey, base);
    }
  }

  Future<void> clear() async {
    await _prefs.remove(_accessKey);
    await _prefs.remove(_refreshKey);
  }
}

/// Thin REST wrapper over the Express API. Refreshes the access token once on
/// a 401 and replays the original request, exactly like `lib/api.ts` does.
class ApiClient {
  ApiClient({required this.tokens, http.Client? httpClient, String? defaultBase})
      : _http = httpClient ?? http.Client(),
        _defaultBase = defaultBase ??
            const String.fromEnvironment(
              // Override at build time: `flutter build apk --dart-define=API_BASE=...`
              'API_BASE',
              defaultValue: 'https://santim.lunafh.com/backend/api/v1',
            );

  final TokenStore tokens;
  final http.Client _http;
  final String _defaultBase;

  /// Fires when a refresh fails and the session is unrecoverable.
  final _unauthorized = StreamController<void>.broadcast();
  Stream<void> get onUnauthorized => _unauthorized.stream;

  String get baseUrl => tokens.customBase ?? _defaultBase;

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _request<T>('GET', path, query: query);

  Future<T> post<T>(String path, {Object? body, bool skipAuth = false}) =>
      _request<T>('POST', path, body: body, skipAuth: skipAuth);

  Future<T> put<T>(String path, {Object? body}) => _request<T>('PUT', path, body: body);

  Future<T> patch<T>(String path, {Object? body}) => _request<T>('PATCH', path, body: body);

  Future<T> delete<T>(String path) => _request<T>('DELETE', path);

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
      // Flutter web uses the browser fetch stack — without this, GETs often
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
      final streamed = await _http.send(req).timeout(const Duration(seconds: 30));
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiError(0, 'The server took too long to respond.');
    } catch (_) {
      throw ApiError(0, 'Cannot reach the server. Check your connection.');
    }

    if (res.statusCode == 401 && !skipAuth && !isRetry && tokens.refresh != null) {
      if (await _tryRefresh()) {
        return _request<T>(method, path, body: body, query: query, isRetry: true);
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
        (err is Map && err['message'] is String) ? err['message'] as String : res.reasonPhrase ?? 'Request failed',
        code: (err is Map && err['code'] is String) ? err['code'] as String : null,
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

  Future<bool> _tryRefresh() async {
    try {
      final res = await _http
          .post(
            _uri('/auth/refresh', null),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': tokens.refresh}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode < 200 || res.statusCode >= 300) return false;
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      await tokens.set(data['accessToken'] as String, data['refreshToken'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _unauthorized.close();
    _http.close();
  }
}
