import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/layout.dart';
import '../../models/common.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';

/// `AiProviders` — bring your own key. Providers are tried in the order shown,
/// so the first enabled one that answers wins.
class AiProvidersScreen extends StatefulWidget {
  const AiProvidersScreen({super.key});

  @override
  State<AiProvidersScreen> createState() => _AiProvidersScreenState();
}

class _Provider {
  _Provider({
    required this.id,
    required this.label,
    required this.enabled,
    required this.hasKey,
    this.model,
  });

  final String id;
  final String label;
  bool enabled;
  bool hasKey;
  String? model;

  static const labels = {
    'anthropic': 'Claude (Anthropic)',
    'openai': 'OpenAI',
    'google': 'Gemini (Google)',
  };

  factory _Provider.fromJson(Map<String, dynamic> j) {
    final id = asStr(j['id'], '');
    return _Provider(
      id: id,
      label: labels[id] ?? id,
      enabled: asBool(j['enabled']),
      hasKey: asBool(j['hasKey'], asStrOrNull(j['apiKey']) != null),
      model: asStrOrNull(j['model']),
    );
  }
}

class _AiProvidersScreenState extends State<AiProvidersScreen> {
  List<_Provider> _providers = const [];
  bool _loading = true;
  bool _saving = false;
  Object? _error;
  String? _testing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final json = await context.read<ApiClient>().get<dynamic>('/ai/settings');
      final list = json is List ? json : (json is Map ? json['providers'] : null);
      if (!mounted) return;
      final found = mapList(list, _Provider.fromJson);
      setState(() {
        // Always show all three, in the priority order the server uses.
        _providers = [
          for (final id in _Provider.labels.keys)
            found.where((p) => p.id == id).firstOrNull ??
                _Provider(id: id, label: _Provider.labels[id]!, enabled: false, hasKey: false),
        ];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _save({String? id, String? apiKey}) async {
    setState(() => _saving = true);
    try {
      await context.read<ApiClient>().put(
        '/ai/settings',
        body: {
          'providers': [
            for (final p in _providers)
              {
                'id': p.id,
                'enabled': p.enabled,
                if (p.model != null && p.model!.isNotEmpty) 'model': p.model,
                if (p.id == id && apiKey != null && apiKey.isNotEmpty) 'apiKey': apiKey,
              },
          ],
        },
      );
      await _load();
      if (mounted) toast(context, 'Saved');
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test(String id) async {
    setState(() => _testing = id);
    try {
      final json = await context.read<ApiClient>().post<Map<String, dynamic>>(
        '/ai/settings/test',
        body: {'id': id},
      );
      if (!mounted) return;
      final ok = asBool(json['ok'], true);
      toast(
        context,
        ok ? 'Connection works' : asStr(json['error'], 'That key did not work.'),
        error: !ok,
      );
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _testing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'AI providers',
          style: TextStyle(
            fontSize: AppType.lead,
            fontWeight: FontWeight.w700,
            color: t.foreground,
          ),
        ),
      ),
      body: MeshBackground(
        showGrid: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: t.primary,
          backgroundColor: t.surface,
          child: ListView(
            padding: EdgeInsets.fromLTRB(14, 4, 14, ShellLayout.bottomClearance(context)),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              AppCard(
                padding: const EdgeInsets.all(S.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.key_outlined, size: 16, color: t.primary),
                    const GapX(S.md),
                    Expanded(
                      child: Text(
                        'Ask Santim runs on your own API key. Providers are tried '
                        'top to bottom, so the first enabled one that answers wins. '
                        'Keys are stored encrypted and never leave your account.',
                        style: TextStyle(
                          fontSize: AppType.label,
                          height: 1.5,
                          color: t.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(S.lg),
              if (_loading && _providers.isEmpty)
                const PageLoader(rows: 3, hero: false)
              else if (_error != null && _providers.isEmpty)
                ErrorState(
                  message: _error is ApiError
                      ? (_error as ApiError).message
                      : 'Could not load your AI settings.',
                  onRetry: _load,
                )
              else
                for (var i = 0; i < _providers.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.md),
                    child: FadeInUp.staggered(
                      index: i,
                      child: _ProviderCard(
                        provider: _providers[i],
                        priority: i + 1,
                        testing: _testing == _providers[i].id,
                        busy: _saving,
                        onToggle: (v) {
                          setState(() => _providers[i].enabled = v);
                          _save();
                        },
                        onSetKey: () => _setKey(context, _providers[i]),
                        onTest: () => _test(_providers[i].id),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setKey(BuildContext context, _Provider provider) async {
    final key = TextEditingController();
    final model = TextEditingController(text: provider.model ?? '');

    await showAppSheet<void>(
      context,
      title: provider.label,
      subtitle: 'Paste a key from your own account with that provider.',
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: key,
              label: 'API key',
              placeholder: provider.hasKey ? 'Leave blank to keep the current key' : 'sk-…',
              prefixIcon: Icons.vpn_key_outlined,
              obscure: true,
              textCapitalization: TextCapitalization.none,
              autofocus: true,
            ),
            const Gap(S.lg),
            AppTextField(
              controller: model,
              label: 'Model',
              hint: 'Optional. Leave blank to use the provider default.',
              placeholder: switch (provider.id) {
                'anthropic' => 'claude-opus-5',
                'openai' => 'gpt-4o',
                _ => 'gemini-2.0-flash',
              },
              prefixIcon: Icons.memory_outlined,
              textCapitalization: TextCapitalization.none,
            ),
            const Gap(S.xl),
            AppButton(
              label: 'Save',
              icon: Icons.check,
              size: BtnSize.lg,
              expand: true,
              onPressed: () {
                provider.model = model.text.trim().isEmpty ? null : model.text.trim();
                provider.enabled = true;
                Navigator.pop(ctx);
                _save(id: provider.id, apiKey: key.text.trim());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.priority,
    required this.testing,
    required this.busy,
    required this.onToggle,
    required this.onSetKey,
    required this.onTest,
  });

  final _Provider provider;
  final int priority;
  final bool testing;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onSetKey;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: t.surfaceMuted,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$priority',
                  style: TextStyle(
                    fontSize: AppType.label,
                    fontWeight: FontWeight.w700,
                    color: t.mutedForeground,
                  ),
                ),
              ),
              const GapX(S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.label,
                      style: TextStyle(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w700,
                        color: t.foreground,
                      ),
                    ),
                    const Gap(S.hair),
                    Muted(
                      provider.hasKey
                          ? 'Key saved${provider.model != null ? ' · ${provider.model}' : ''}'
                          : 'No key yet',
                      size: 11.5,
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: provider.enabled,
                onChanged: busy || !provider.hasKey ? null : onToggle,
                activeThumbColor: t.primary,
                activeTrackColor: t.primary.withValues(alpha: 0.35),
              ),
            ],
          ),
          const Gap(S.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: provider.hasKey ? 'Replace key' : 'Add key',
                  icon: Icons.vpn_key_outlined,
                  variant: BtnVariant.outline,
                  size: BtnSize.sm,
                  expand: true,
                  onPressed: onSetKey,
                ),
              ),
              const GapX(S.sm),
              Expanded(
                child: AppButton(
                  label: 'Test',
                  icon: Icons.bolt_outlined,
                  variant: BtnVariant.ghost,
                  size: BtnSize.sm,
                  expand: true,
                  loading: testing,
                  onPressed: provider.hasKey ? onTest : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
