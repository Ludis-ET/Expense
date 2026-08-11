import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import '../models/common.dart';

/// Latest Android build advertised by `GET /app/android-update`.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.configured,
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.changelog,
    required this.forceUpdate,
    required this.minSupportedVersionCode,
    required this.currentVersionCode,
    required this.currentVersionName,
  });

  final bool configured;
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String changelog;
  final bool forceUpdate;
  final int minSupportedVersionCode;
  final int currentVersionCode;
  final String currentVersionName;

  bool get updateAvailable => configured && versionCode > currentVersionCode;

  bool get belowMinimum =>
      configured && currentVersionCode < minSupportedVersionCode;

  bool get mustUpdate => forceUpdate || belowMinimum;
}

/// Checks the API for a newer APK, downloads it, and hands it to the installer.
class AppUpdateService {
  AppUpdateService(this._api, this._prefs);

  static const _skipKey = 'santim.skip_update_code';

  final ApiClient _api;
  final SharedPreferences _prefs;

  int? get skippedVersionCode => _prefs.getInt(_skipKey);

  Future<void> skipVersion(int versionCode) => _prefs.setInt(_skipKey, versionCode);

  Future<void> clearSkip() => _prefs.remove(_skipKey);

  Future<AppUpdateInfo?> fetch() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final json = await _api.get<Map<String, dynamic>>(
        '/app/android-update',
        skipAuth: true,
      );
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      final configured = asBool(json['configured']);
      if (!configured) {
        return AppUpdateInfo(
          configured: false,
          versionCode: currentCode,
          versionName: info.version,
          apkUrl: '',
          changelog: '',
          forceUpdate: false,
          minSupportedVersionCode: 1,
          currentVersionCode: currentCode,
          currentVersionName: info.version,
        );
      }
      return AppUpdateInfo(
        configured: true,
        versionCode: asInt(json['versionCode']),
        versionName: asStr(json['versionName'], info.version),
        apkUrl: asStr(json['apkUrl']),
        changelog: asStr(json['changelog']),
        forceUpdate: asBool(json['forceUpdate']),
        minSupportedVersionCode: asInt(json['minSupportedVersionCode'], 1),
        currentVersionCode: currentCode,
        currentVersionName: info.version,
      );
    } catch (_) {
      return null;
    }
  }

  /// True when the user should see the update sheet now.
  Future<bool> shouldPrompt(AppUpdateInfo info) async {
    if (!info.updateAvailable) return false;
    if (info.mustUpdate) return true;
    final skipped = skippedVersionCode;
    if (skipped != null && skipped >= info.versionCode) return false;
    return true;
  }

  Future<bool> ensureInstallPermission() async {
    if (!Platform.isAndroid) return false;
    final status = await Permission.requestInstallPackages.status;
    if (status.isGranted) return true;
    final result = await Permission.requestInstallPackages.request();
    return result.isGranted;
  }

  /// Downloads [info.apkUrl] with progress callbacks (0–1). Returns local path.
  Future<File> downloadApk(
    AppUpdateInfo info, {
    required void Function(double progress) onProgress,
  }) async {
    final uri = Uri.parse(info.apkUrl);
    final request = http.Request('GET', uri);
    final response = await http.Client().send(request).timeout(const Duration(minutes: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiError(response.statusCode, 'Could not download the update (${response.statusCode}).');
    }

    final total = response.contentLength ?? 0;
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'santim-${info.versionCode}.apk'));
    final sink = file.openWrite();
    var received = 0;

    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress((received / total).clamp(0.0, 1.0));
        } else {
          onProgress(0);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    onProgress(1);
    return file;
  }

  Future<void> installApk(File file) async {
    final allowed = await ensureInstallPermission();
    if (!allowed) {
      throw ApiError(0, 'Allow Santim to install updates in system settings, then try again.');
    }
    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type == ResultType.error || result.type == ResultType.noAppToOpen) {
      throw ApiError(
        0,
        result.message.isNotEmpty ? result.message : 'Could not open the installer.',
      );
    }
  }
}
