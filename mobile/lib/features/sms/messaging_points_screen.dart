import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';

import '../../core/theme/theme.dart';

import '../../core/api/api_client.dart';
import '../../core/layout.dart';
import '../../core/theme/tokens.dart';
import '../../models/ingest.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/sms_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';

class MessagingPointsScreen extends StatefulWidget {
  const MessagingPointsScreen({super.key, this.fromSetup = false});
  final bool fromSetup;

  @override
  State<MessagingPointsScreen> createState() => _MessagingPointsScreenState();
}

class _MessagingPointsScreenState extends State<MessagingPointsScreen> {
  bool _loading = true;
  bool _scanning = false;
  String? _error;
  List<({String sender, String sample, int count, bool knownBank})> _scanned =
      const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final sms = context.read<SmsState>();
    final data = context.read<DataState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Future.wait([
        sms.loadBanks(),
        sms.loadSenderRules(),
        data.loadAccounts(),
        data.loadCategories(),
      ]);
      if (!mounted) return;
      // Show mapped banks immediately; inbox scan continues in the background.
      setState(() => _loading = false);
      await _scanInbox();
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load messaging points.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _scanInbox() async {
    if (!mounted) return;
    setState(() => _scanning = true);
    try {
      final scanned = await context.read<SmsState>().scanCandidateSenders();
      if (mounted) setState(() => _scanned = scanned);
    } catch (_) {
      if (mounted) setState(() => _scanned = const []);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _enableFoundBanks() async {
    final data = context.read<DataState>();
    final sms = context.read<SmsState>();
    final accounts = data.scopedAccounts;
    if (accounts.isEmpty) {
      toast(context, 'Create a wallet first', error: true);
      return;
    }
    final accountId = accounts.where((a) => a.isDefault).firstOrNull?.id ??
        accounts.first.id;
    final known = _scanned.where((s) => s.knownBank).toList();
    if (known.isEmpty) {
      toast(context, 'No known bank senders in recent SMS yet');
      return;
    }
    try {
      final n = await sms.enableFoundBanks(
        scanned: known,
        accountId: accountId,
      );
      if (!mounted) return;
      toast(
        context,
        n == 0
            ? 'Those banks were already mapped'
            : 'Enabled $n bank sender${n == 1 ? '' : 's'} · importing history…',
      );
      await sms.loadSenderRules();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _editRule({
    required String sender,
    String? sample,
    SenderRule? existing,
    BankCatalogItem? bank,
  }) async {
    final sms = context.read<SmsState>();
    final data = context.read<DataState>();
    var bankKey = existing?.bankKey ?? bank?.key ?? 'generic';
    String? accountId =
        existing?.accountId ?? data.scopedAccounts.firstOrNull?.id;
    String? categoryId = existing?.defaultCategoryId;
    var enabled = existing?.enabled ?? true;
    var autoCommit = existing?.autoCommit ?? false;
    final linked =
        data.accounts.data?.where((a) => a.id == accountId).firstOrNull;
    final digitsCtrl =
        TextEditingController(text: linked?.accountNumber ?? '');

    final saved = await showAppSheet<bool>(
      context,
      title: 'Bank message source',
      subtitle:
          'Mark "$sender" as a bank sender and choose which wallet it fills.',
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final t = ctx.t;
            final accounts = data.scopedAccounts;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                20 +
                    MediaQuery.of(ctx).viewInsets.bottom +
                    MediaQuery.of(ctx).padding.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (sample != null && sample.trim().isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(S.md),
                        decoration: BoxDecoration(
                          color: t.surfaceMuted.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          sample.replaceAll('\n', ' '),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.label,
                            height: 1.4,
                            color: t.foreground,
                          ),
                        ),
                      ),
                      const Gap(S.md),
                    ],
                    Text(
                      'Which bank is this?',
                      style: TextStyle(
                        fontSize: AppType.label,
                        color: t.mutedForeground,
                      ),
                    ),
                    const Gap(S.xs),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final b in sms.banks)
                          ChoiceChip(
                            label: Text(
                              b.label,
                              style: const TextStyle(fontSize: AppType.label),
                            ),
                            selected: bankKey == b.key,
                            onSelected: (_) =>
                                setLocal(() => bankKey = b.key),
                          ),
                        ChoiceChip(
                          label: const Text(
                            'Generic',
                            style: TextStyle(fontSize: AppType.label),
                          ),
                          selected: bankKey == 'generic',
                          onSelected: (_) =>
                              setLocal(() => bankKey = 'generic'),
                        ),
                      ],
                    ),
                    const Gap(S.md),
                    Text(
                      'Deposit into wallet',
                      style: TextStyle(
                        fontSize: AppType.label,
                        color: t.mutedForeground,
                      ),
                    ),
                    const Gap(S.xs),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final a in accounts)
                          ChoiceChip(
                            label: Text(
                              a.name,
                              style: const TextStyle(fontSize: AppType.label),
                            ),
                            selected: accountId == a.id,
                            onSelected: (_) => setLocal(() {
                              accountId = a.id;
                              if (digitsCtrl.text.trim().isEmpty &&
                                  (a.accountNumber?.isNotEmpty ?? false)) {
                                digitsCtrl.text = a.accountNumber!;
                              }
                            }),
                          ),
                      ],
                    ),
                    const Gap(S.md),
                    AppTextField(
                      controller: digitsCtrl,
                      label: 'Account digits (last 4+)',
                      hint: 'Matches transfers to your own wallets from SMS',
                      placeholder: '••••1234',
                      keyboardType: TextInputType.number,
                      textCapitalization: TextCapitalization.none,
                    ),
                    const Gap(S.sm),
                    PickerField<TxCategory>(
                      label: 'Default category',
                      value: (data.categories.data ?? const <TxCategory>[])
                          .where((c) => c.id == categoryId)
                          .firstOrNull,
                      options: (data.categories.data ?? const <TxCategory>[])
                          .where((c) => !c.archived)
                          .toList(),
                      labelOf: (c) => c.name,
                      placeholder: 'None',
                      allowClear: true,
                      onChanged: (c) =>
                          setLocal(() => categoryId = c?.id),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Treat as bank message',
                        style: TextStyle(fontSize: AppType.body),
                      ),
                      subtitle: const Text(
                        'Off = ignore this sender',
                        style: TextStyle(fontSize: AppType.label),
                      ),
                      value: enabled,
                      onChanged: (v) => setLocal(() => enabled = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Record without asking',
                        style: TextStyle(fontSize: AppType.body),
                      ),
                      subtitle: const Text(
                        'Needs wallet, category, and a confident parse.',
                        style: TextStyle(fontSize: AppType.label),
                      ),
                      value: autoCommit,
                      onChanged: (v) => setLocal(() => autoCommit = v),
                    ),
                    const Gap(S.md),
                    AppButton(
                      label: 'Save mapping',
                      expand: true,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    final digits = digitsCtrl.text.trim();
    digitsCtrl.dispose();
    if (saved != true || !mounted) return;
    try {
      if (accountId != null && digits.isNotEmpty) {
        final acc =
            data.accounts.data?.where((a) => a.id == accountId).firstOrNull;
        if (acc == null || acc.accountNumber != digits) {
          await context.read<ApiClient>().put(
            '/accounts/$accountId',
            body: {'accountNumber': digits},
          );
          await data.loadAccounts(force: true);
        }
      }
      if (accountId == null) {
        if (mounted) {
          toast(context, 'Pick a wallet to link this sender', error: true);
        }
        return;
      }
      await sms.upsertSenderRule({
        'sender': sender,
        'bankKey': bankKey,
        'accountId': accountId,
        'defaultCategoryId': categoryId,
        'enabled': enabled,
        'autoCommit': autoCommit,
      });
      final imported = await sms.importSenderHistory(sender);
      if (mounted) {
        toast(
          context,
          imported > 0
              ? 'Mapped · queued $imported recent SMS for review'
              : 'Bank message mapping saved',
        );
      }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final sms = context.watch<SmsState>();
    final knownFound =
        _scanned.where((s) => s.knownBank).length;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        foregroundColor: t.foreground,
        title: Text(
          'Messaging points',
          style: TextStyle(
            fontSize: AppType.lead,
            fontWeight: FontWeight.w700,
            color: t.foreground,
          ),
        ),
        actions: [
          if (widget.fromSetup)
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Done'),
            ),
        ],
      ),
      body: MeshBackground(
        child: _loading
            ? const PageLoader(rows: 4)
            : RefreshIndicator(
                onRefresh: _load,
                color: t.primary,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    8,
                    14,
                    ShellLayout.pageClearance(context),
                  ),
                  children: [
                    SectionLabel(
                      'MAPPED BANK SENDERS',
                      hint:
                          'Senders Santim is allowed to read. Map each one to a wallet '
                          'so the review deck can confirm in one swipe.',
                    ),
                    if (_error != null) ...[
                      const Gap(S.sm),
                      Text(_error!, style: TextStyle(color: t.danger)),
                    ],
                    if (sms.senderRules.isEmpty)
                      const EmptyState(
                        title: 'No bank senders yet',
                        description:
                            'Enable a sender from your inbox below and pick which wallet it should fill.',
                        icon: Icons.cell_tower_rounded,
                        compact: true,
                      )
                    else
                      for (final r in sms.senderRules)
                        _RuleTile(
                          rule: r,
                          onTap: () =>
                              _editRule(sender: r.sender, existing: r),
                          onDelete: () async {
                            await sms.deleteSenderRule(r.id);
                          },
                        ),
                    if (knownFound > 0) ...[
                      const Gap(S.md),
                      AppButton(
                        label: 'Enable $knownFound found bank'
                            '${knownFound == 1 ? '' : 's'}',
                        icon: Icons.auto_awesome_rounded,
                        expand: true,
                        onPressed: _enableFoundBanks,
                      ),
                      const Gap(S.xs),
                      Muted(
                        'Maps known bank short-codes from your SMS to your default wallet and imports recent history.',
                        size: 12,
                        maxLines: 3,
                      ),
                    ],
                    const Gap(S.lg),
                    SectionLabel(
                      'FROM YOUR MESSAGES',
                      trailing: _scanning
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                    if (!_scanning && _scanned.isEmpty)
                      const EmptyState(
                        title: 'No SMS found',
                        description:
                            'Grant SMS permission, then mark which senders are your banks.',
                        icon: Icons.sms_failed_outlined,
                        compact: true,
                      )
                    else
                      for (final s in _scanned.take(40))
                        _ScanTile(
                          sender: s.sender,
                          sample: s.sample,
                          count: s.count,
                          knownBank: s.knownBank,
                          already: sms.senderRules.any(
                            (r) =>
                                r.sender.toLowerCase() ==
                                s.sender.toLowerCase(),
                          ),
                          bank: _matchBank(sms.banks, s.sender),
                          onTap: () => _editRule(
                            sender: s.sender,
                            sample: s.sample,
                            bank: _matchBank(sms.banks, s.sender),
                          ),
                        ),
                    const Gap(S.lg),
                    SectionLabel('KNOWN BANKS'),
                    for (final b in sms.banks)
                      AppCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: S.lg,
                          vertical: S.md,
                        ),
                        onTap: () {
                          Haptics.select();
                          final sender = b.senders.firstOrNull ?? b.key;
                          _editRule(
                            sender: sender.toUpperCase(),
                            bank: b,
                          );
                        },
                        child: Row(
                          children: [
                            IconTile(
                              icon: Icons.account_balance_rounded,
                              color: t.primary,
                              size: 38,
                            ),
                            const GapX(S.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    b.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Muted(
                                    b.senders.take(3).join(' · '),
                                    size: 12,
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.add_rounded,
                              color: t.mutedForeground,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.rule,
    required this.onTap,
    required this.onDelete,
  });
  final SenderRule rule;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: S.lg,
          vertical: S.md,
        ),
        onTap: onTap,
        child: Row(
          children: [
            IconTile(
              icon: Icons.cell_tower_rounded,
              color: rule.enabled ? t.primary : t.mutedForeground,
              size: 38,
            ),
            const GapX(S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.sender,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Muted(
                    [
                      rule.bankLabel ?? rule.bankKey,
                      if (rule.account != null) rule.account!.name,
                      if (rule.autoCommit) 'auto',
                    ].join(' · '),
                    size: 12,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: t.danger, size: 20),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanTile extends StatelessWidget {
  const _ScanTile({
    required this.sender,
    required this.sample,
    required this.count,
    required this.already,
    required this.onTap,
    required this.knownBank,
    this.bank,
  });

  final String sender;
  final String sample;
  final int count;
  final bool already;
  final bool knownBank;
  final BankCatalogItem? bank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: S.lg,
          vertical: S.md,
        ),
        onTap: already ? null : onTap,
        child: Row(
          children: [
            IconTile(
              icon: knownBank
                  ? Icons.account_balance_rounded
                  : Icons.sms_outlined,
              color: knownBank ? t.primary : t.accent,
              size: 38,
            ),
            const GapX(S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sender,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Muted(
                    [
                      if (bank != null) bank!.label,
                      if (knownBank && bank == null) 'Bank-like',
                      '$count msgs',
                      sample.replaceAll('\n', ' '),
                    ].join(' · '),
                    size: 12,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            Text(
              already ? 'On' : 'Add',
              style: TextStyle(
                color: already ? t.success : t.primary,
                fontWeight: FontWeight.w700,
                fontSize: AppType.label,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BankCatalogItem? _matchBank(List<BankCatalogItem> banks, String sender) {
  final n = sender.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  for (final b in banks) {
    for (final s in b.senders) {
      final x = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (n == x || n.contains(x) || x.contains(n)) return b;
    }
  }
  return null;
}
