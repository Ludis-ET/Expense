import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/app_update.dart';
import '../../core/haptics.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/ui.dart';

/// Shows the update sheet when a newer APK is advertised by the API.
Future<void> maybePromptAppUpdate(
  BuildContext context, {
  bool manual = false,
}) async {
  final api = context.read<ApiClient>();
  final store = await SharedPreferences.getInstance();
  final service = AppUpdateService(api, store);
  final info = await service.fetch();
  if (!context.mounted) return;

  if (info == null) {
    if (manual)
      toast(context, 'Could not check for updates right now.', error: true);
    return;
  }
  if (!info.configured) {
    if (manual) toast(context, 'No update channel configured yet.');
    return;
  }
  if (!info.updateAvailable) {
    if (manual) {
      toast(
        context,
        'You’re on the latest version (${info.currentVersionName}).',
      );
    }
    return;
  }
  if (!manual && !await service.shouldPrompt(info)) return;
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: !info.mustUpdate,
    enableDrag: !info.mustUpdate,
    backgroundColor: Colors.transparent,
    builder: (_) => _UpdateSheet(info: info, service: service),
  );
}

class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet({required this.info, required this.service});

  final AppUpdateInfo info;
  final AppUpdateService service;

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _start() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    Haptics.toggle();
    try {
      final file = await widget.service.downloadApk(
        widget.info,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await widget.service.installApk(file);
      if (mounted) {
        toast(context, 'Install prompt opened   confirm to finish updating.');
        if (!widget.info.mustUpdate) Navigator.of(context).pop();
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Update failed. Try again.');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final info = widget.info;

    return SheetShell(
      title: info.mustUpdate ? 'Update required' : 'New version available',
      subtitle: '${info.currentVersionName} → ${info.versionName}',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.xl, 0, S.xl, S.huge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(S.lg),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    t.primary.withValues(alpha: 0.12),
                    t.accent.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(R.card),
                border: Border.all(color: t.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(colors: [t.primary, t.accent]),
                    ),
                    child: Icon(
                      Icons.system_update_alt_rounded,
                      color: t.primaryForeground,
                    ),
                  ),
                  const GapX(S.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Santim ${info.versionName}',
                          style: TextStyle(
                            fontSize: AppType.body,
                            fontWeight: FontWeight.w800,
                            color: t.foreground,
                          ),
                        ),
                        const Gap(S.hair),
                        Muted(
                          'Build ${info.versionCode} · downloads and installs on this phone',
                          size: 12,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (info.changelog.trim().isNotEmpty) ...[
              const Gap(S.lg),
              Text(
                'What’s new',
                style: TextStyle(
                  fontSize: AppType.label,
                  fontWeight: FontWeight.w800,
                  color: t.mutedForeground,
                ),
              ),
              const Gap(S.sm),
              Text(
                info.changelog.trim(),
                style: TextStyle(
                  fontSize: AppType.bodySm,
                  height: 1.5,
                  color: t.foreground,
                ),
              ),
            ],
            if (_downloading) ...[
              const Gap(S.xl),
              ClipRRect(
                borderRadius: BorderRadius.circular(R.pill),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  minHeight: 8,
                  backgroundColor: t.surfaceMuted,
                  color: t.primary,
                ),
              ),
              const Gap(S.sm),
              Muted(
                _progress > 0
                    ? 'Downloading… ${(_progress * 100).round()}%'
                    : 'Starting download…',
                size: 12,
              ),
            ],
            if (_error != null) ...[
              const Gap(S.md),
              Text(
                _error!,
                style: TextStyle(fontSize: AppType.bodySm, color: t.danger),
              ),
            ],
            const Gap(S.xl),
            AppButton(
              label: _downloading ? 'Downloading…' : 'Download & install',
              icon: Icons.download_rounded,
              expand: true,
              loading: _downloading,
              onPressed: _downloading ? null : _start,
            ),
            if (!info.mustUpdate) ...[
              const Gap(S.sm),
              AppButton(
                label: 'Not now',
                variant: BtnVariant.ghost,
                expand: true,
                onPressed: _downloading
                    ? null
                    : () async {
                        await widget.service.skipVersion(info.versionCode);
                        if (context.mounted) Navigator.of(context).pop();
                      },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
