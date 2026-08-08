import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// The server could not be reached at all.
///
/// Kept distinct from [ApiException] because the two demand opposite
/// responses: a server that rejected a write means the write was wrong and
/// must not be retried, while an unreachable server means the write is
/// probably fine and belongs in the outbox. Conflating them would either
/// queue garbage forever or throw away good edits made on the train.
class NetworkException implements Exception {
  NetworkException([this.message = 'No connection to the server']);

  final String message;

  @override
  String toString() => message;
}

/// A non-2xx response, carrying the backend's own message.
///
/// The API returns human-readable messages for the cases that matter most here
/// - "Not enough available balance in Cash", "Pick a category" - so surfacing
/// `message` verbatim is better than inventing our own wording.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.code, this.details});

  final int statusCode;
  final String message;
  final String? code;
  final Object? details;

  bool get isAuthFailure => statusCode == 401;

  @override
  String toString() => message;
}

/// Thin HTTP client for the Santim API.
///
/// Owns the access/refresh token pair and transparently re-authenticates once
/// on a 401. Access tokens live 15 minutes, so without this every screen would
/// need its own retry.
class ApiClient {
  ApiClient({required this.baseUrl, FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Includes the version prefix, e.g. `https://host/api/v1`.
  String baseUrl;

  final FlutterSecureStorage _storage;
  final _http = http.Client();

  static const _kAccess = 'santim.accessToken';
  static const _kRefresh = 'santim.refreshToken';

  String? _accessToken;
  String? _refreshToken;

  /// Guards against a burst of parallel 401s firing a refresh each.
  Future<bool>? _refreshInFlight;

  String? get accessToken => _accessToken;

  Future<void> loadTokens() async {
    _accessToken = await _storage.read(key: _kAccess);
    _refreshToken = await _storage.read(key: _kRefresh);
  }

  Future<void> setTokens(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }

  bool get hasSession => _refreshToken != null;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}$normalized');
    if (query == null || query.isEmpty) return uri;

    return uri.replace(
      queryParameters: {
        for (final e in query.entries)
          if (e.value != null) e.key: '${e.value}',
      },
    );
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body}) => _send('POST', path, body: body);

  Future<dynamic> put(String path, {Object? body}) => _send('PUT', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool allowRetry = true,
  }) async {
    final request = http.Request(method, _uri(path, query))
      ..headers['Accept'] = 'application/json';

    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    if (_accessToken != null) {
      request.headers['Authorization'] = 'Bearer $_accessToken';
    }

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(const Duration(seconds: 25));
      response = await http.Response.fromStream(streamed);
    } on ApiException {
      rethrow;
    } catch (_) {
      // Socket errors, DNS failures, TLS problems and timeouts all land here.
      // None of them tell us anything about whether the request was valid.
      throw NetworkException();
    }

    if (response.statusCode == 401 && allowRetry && _refreshToken != null) {
      if (await _refreshSession()) {
        return _send(method, path, body: body, query: query, allowRetry: false);
      }
    }

    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode == 204 || response.body.isEmpty) return null;

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;

    final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
    final message = (error is Map<String, dynamic> ? error['message'] : null) ??
        (decoded is Map<String, dynamic> ? decoded['message'] : null) ??
        'Request failed (${response.statusCode})';

    throw ApiException(
      response.statusCode,
      '$message',
      code: error is Map<String, dynamic> ? error['code'] as String? : null,
      details: error is Map<String, dynamic> ? error['details'] : null,
    );
  }

  Future<bool> _refreshSession() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() => _refreshInFlight = null);
  }

  Future<bool> _doRefresh() async {
    try {
      final response = await _http.post(
        _uri('/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': _refreshToken}),
      );
      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      await setTokens(data['accessToken'] as String, data['refreshToken'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _http.close();
}
