import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
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
  String? _error;
  List<({String sender, String sample, int count})> _scanned = const [];

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
      try {
        _scanned = await sms.scanCandidateSenders();
      } catch (_) {
        _scanned = const [];
      }
    } on ApiError catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
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
    String? accountId = existing?.accountId ?? data.scopedAccounts.firstOrNull?.id;
    String? categoryId = existing?.defaultCategoryId;
    var enabled = existing?.enabled ?? true;
    var autoCommit = existing?.autoCommit ?? false;
    final linked = data.accounts.data?.where((a) => a.id == accountId).firstOrNull;
    final digitsCtrl = TextEditingController(text: linked?.accountNumber ?? '');

    final saved = await showAppSheet<bool>(
      context,
      title: 'Bank message source',
      subtitle: 'Mark "$sender" as a bank sender and choose which wallet it fills.',
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final t = ctx.t;
            final accounts = data.scopedAccounts;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).padding.bottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (sample != null && sample.trim().isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: t.surfaceMuted.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          sample.replaceAll('\n', ' '),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, height: 1.4, color: t.foreground),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Text('Which bank is this?', style: TextStyle(fontSize: 12, color: t.mutedForeground)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final b in sms.banks)
                          ChoiceChip(
                            label: Text(b.label, style: const TextStyle(fontSize: 12)),
                            selected: bankKey == b.key,
                            onSelected: (_) => setLocal(() => bankKey = b.key),
                          ),
                        ChoiceChip(
                          label: const Text('Generic', style: TextStyle(fontSize: 12)),
                          selected: bankKey == 'generic',
                          onSelected: (_) => setLocal(() => bankKey = 'generic'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('Deposit into wallet', style: TextStyle(fontSize: 12, color: t.mutedForeground)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final a in accounts)
                          ChoiceChip(
                            label: Text(a.name, style: const TextStyle(fontSize: 12)),
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
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: digitsCtrl,
                      label: 'Account digits (last 4+)',
                      hint: 'Matches transfers to your own wallets from SMS',
                      placeholder: '••••1234',
                      keyboardType: TextInputType.number,
                      textCapitalization: TextCapitalization.none,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      initialValue: categoryId,
                      decoration: const InputDecoration(labelText: 'Default category'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('None')),
                        for (final c in data.categories.data ?? const <TxCategory>[])
                          if (!c.archived)
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
                      ],
                      onChanged: (v) => setLocal(() => categoryId = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Treat as bank message', style: TextStyle(fontSize: 14)),
                      subtitle: const Text(
                        'Off = ignore this sender',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: enabled,
                      onChanged: (v) => setLocal(() => enabled = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Record without asking', style: TextStyle(fontSize: 14)),
                      subtitle: const Text(
                        'Needs wallet, category, and a confident parse.',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: autoCommit,
                      onChanged: (v) => setLocal(() => autoCommit = v),
                    ),
                    const SizedBox(height: 12),
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
        final acc = data.accounts.data?.where((a) => a.id == accountId).firstOrNull;
        if (acc != null && acc.accountNumber != digits) {
          await context.read<ApiClient>().put(
            '/accounts/$accountId',
            body: {'accountNumber': digits},
          );
          await data.loadAccounts(force: true);
        }
      }
      await sms.upsertSenderRule({
        'sender': sender,
        'bankKey': bankKey,
        'accountId': accountId,
        'defaultCategoryId': categoryId,
        'enabled': enabled,
        'autoCommit': autoCommit,
      });
      if (mounted) toast(context, 'Bank message mapping saved');
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final sms = context.watch<SmsState>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Messaging points',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.foreground),
        ),
        actions: [
          if (widget.fromSetup)
            TextButton(
              onPressed: () => Navigator.pop(context),
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
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 40),
                  children: [
                    Muted(
                      'Senders Santim is allowed to read. Map each one to a wallet '
                      'so the review deck can confirm in one swipe.',
                      size: 13,
                      height: 1.4,
                      maxLines: 4,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: t.danger)),
                    ],
                    const SizedBox(height: 18),
                    SectionLabel('MAPPED BANK SENDERS'),
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
                          onTap: () => _editRule(sender: r.sender, existing: r),
                          onDelete: () async {
                            await sms.deleteSenderRule(r.id);
                          },
                        ),
                    const SizedBox(height: 18),
                    SectionLabel('FROM YOUR MESSAGES'),
                    if (_scanned.isEmpty)
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
                          already: sms.senderRules.any(
                            (r) => r.sender.toLowerCase() == s.sender.toLowerCase(),
                          ),
                          bank: _matchBank(sms.banks, s.sender),
                          onTap: () => _editRule(
                            sender: s.sender,
                            sample: s.sample,
                            bank: _matchBank(sms.banks, s.sender),
                          ),
                        ),
                    const SizedBox(height: 18),
                    SectionLabel('KNOWN BANKS'),
                    for (final b in sms.banks)
                      AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          final sender = b.senders.firstOrNull ?? b.key;
                          _editRule(sender: sender.toUpperCase(), bank: b);
                        },
                        child: Row(
                          children: [
                            IconTile(icon: Icons.account_balance_rounded, color: t.primary, size: 38),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(b.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Muted(b.senders.take(3).join(' · '), size: 12),
                                ],
                              ),
                            ),
                            Icon(Icons.add_rounded, color: t.mutedForeground),
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
  const _RuleTile({required this.rule, required this.onTap, required this.onDelete});
  final SenderRule rule;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: onTap,
        child: Row(
          children: [
            IconTile(
              icon: Icons.cell_tower_rounded,
              color: rule.enabled ? t.primary : t.mutedForeground,
              size: 38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rule.sender, style: const TextStyle(fontWeight: FontWeight.w700)),
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
    this.bank,
  });

  final String sender;
  final String sample;
  final int count;
  final bool already;
  final BankCatalogItem? bank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: already ? null : onTap,
        child: Row(
          children: [
            IconTile(icon: Icons.sms_outlined, color: t.accent, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sender, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Muted(
                    [
                      if (bank != null) bank!.label,
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
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BankCatalogItem? _matchBank(List<BankCatalogItem> banks, String sender) {
  final n = sender.toLowerCase();
  for (final b in banks) {
    for (final s in b.senders) {
      final x = s.toLowerCase();
      if (n == x || n.contains(x) || x.contains(n)) return b;
    }
  }
  return null;
}
