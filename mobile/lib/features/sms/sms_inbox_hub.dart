import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';

import '../../core/theme/theme.dart';

import '../../core/api/api_client.dart';
import '../../core/layout.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../models/ingest.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../state/sms_state.dart';
import '../../widgets/ui.dart';
import 'sms_edit_sheet.dart';
import 'sms_import_sheet.dart';
import 'sms_review_deck.dart';
import 'sms_setup_wizard.dart';
import 'sms_settings_screen.dart';

class SmsInboxHub extends StatefulWidget {
  const SmsInboxHub({super.key});

  @override
  State<SmsInboxHub> createState() => _SmsInboxHubState();
}

class _SmsInboxHubState extends State<SmsInboxHub> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sms = context.read<SmsState>();
      sms.loadUnresolved(force: true);
      sms.flushUploads();
    });
  }

  Future<void> _openDeck() async {
    final sms = context.read<SmsState>();
    if (!sms.setupDone || !sms.isPaired) {
      final done = await showSmsSetupWizard(context);
      if (done != true || !mounted) return;
    }
    await sms.loadUnresolved(force: true);
    if (!mounted) return;
    if (sms.unresolved.isEmpty) {
      toast(context, 'Nothing to review right now');
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SmsReviewDeck()));
    if (mounted) await sms.loadUnresolved(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final sms = context.watch<SmsState>();
    final prefs = context.watch<PrefsState>();
    final needsSetup = !sms.isPaired || !sms.setupDone;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        foregroundColor: t.foreground,
        title: Text(
          'Message inbox',
          style: TextStyle(
            fontSize: AppType.lead,
            fontWeight: FontWeight.w700,
            color: t.foreground,
          ),
        ),
        actions: [
          IconPill(
            icon: Icons.settings_outlined,
            size: 34,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SmsSettingsScreen())),
          ),
          const GapX(S.sm),
        ],
      ),
      body: MeshBackground(
        child: RefreshIndicator(
          onRefresh: () => sms.loadUnresolved(force: true),
          color: t.primary,
          child: ListView(
            padding: EdgeInsets.fromLTRB(14, 8, 14, ShellLayout.pageClearance(context)),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              FadeInUp(
                child: GlassCard(
                  padding: const EdgeInsets.all(S.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(colors: [t.primary, t.accent]),
                              boxShadow: [
                                BoxShadow(color: t.primary.withValues(alpha: 0.4), blurRadius: 16),
                              ],
                            ),
                            child: Icon(
                              Icons.mark_email_unread_rounded,
                              color: t.primaryForeground,
                            ),
                          ),
                          const GapX(S.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${sms.needsReview} to review',
                                  style: TextStyle(
                                    fontSize: AppType.heading,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4,
                                    color: t.foreground,
                                  ),
                                ),
                                Muted(
                                  needsSetup
                                      ? 'Set up this phone to capture bank SMS'
                                      : sms.localPendingUploads > 0
                                      ? '${sms.localPendingUploads} waiting to upload'
                                      : 'Swipe right to record · left to skip',
                                  size: 12,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Gap(S.lg),
                      AppButton(
                        label: needsSetup ? 'Set up capture' : 'Review all',
                        icon: needsSetup ? Icons.phonelink_setup_rounded : Icons.style_rounded,
                        expand: true,
                        onPressed: needsSetup ? () => showSmsSetupWizard(context) : _openDeck,
                      ),
                    ],
                  ),
                ),
              ),
              const Gap(S.md),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Import history',
                      variant: BtnVariant.outline,
                      icon: Icons.history_rounded,
                      onPressed: needsSetup
                          ? () async {
                              final done = await showSmsSetupWizard(context);
                              if (done == true && context.mounted) {
                                await showSmsImportSheet(context);
                              }
                            }
                          : () => showSmsImportSheet(context),
                    ),
                  ),
                  if (needsSetup) ...[
                    const GapX(S.sm),
                    Expanded(
                      child: AppButton(
                        label: 'Setup',
                        variant: BtnVariant.ghost,
                        icon: Icons.phonelink_setup_rounded,
                        onPressed: () => showSmsSetupWizard(context),
                      ),
                    ),
                  ],
                ],
              ),
              const Gap(S.lg),
              SectionLabel('UNRESOLVED'),
              if (sms.loadingInbox && sms.unresolved.isEmpty)
                const PageLoader(rows: 3)
              else if (sms.inboxError != null && sms.unresolved.isEmpty)
                ErrorState(
                  message: sms.inboxError is ApiError
                      ? (sms.inboxError as ApiError).message
                      : 'Could not load inbox',
                  onRetry: () => sms.loadUnresolved(force: true),
                )
              else if (sms.unresolved.isEmpty)
                const EmptyState(
                  title: 'Inbox clear',
                  description: 'New bank messages will land here for a one-swipe confirm.',
                  icon: Icons.inbox_outlined,
                )
              else
                for (final m in sms.unresolved)
                  _InboxRow(
                    message: m,
                    money: (v) => prefs.money(v, currency: m.parsedCurrency ?? 'ETB'),
                    onTap: () async {
                      final body = await showSmsEditSheet(context, message: m);
                      if (body == null || !context.mounted) return;
                      try {
                        await sms.confirm(m.id, body);
                        if (context.mounted) {
                          toast(context, 'Recorded');
                          await context.read<DataState>().refreshAfterWrite();
                        }
                      } on ApiError catch (e) {
                        if (context.mounted) toast(context, e.message, error: true);
                      }
                    },
                    onSkip: () async {
                      Haptics.toggle();
                      try {
                        await sms.reject(m.id);
                      } on ApiError catch (e) {
                        if (context.mounted) toast(context, e.message, error: true);
                      }
                    },
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({
    required this.message,
    required this.money,
    required this.onTap,
    required this.onSkip,
  });

  final InboxMessage message;
  final String Function(Object?) money;
  final VoidCallback onTap;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final credit = message.isCredit;
    final amount = message.parsedAmount;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.md),
        onTap: onTap,
        child: Row(
          children: [
            IconTile(
              icon: credit ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: credit ? t.success : t.danger,
              size: 40,
            ),
            const GapX(S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.parsedPayee ?? message.bankLabel ?? message.sender,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: AppType.body,
                      color: t.foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Muted(
                    [
                      message.bankLabel ?? message.sender,
                      formatDate(message.occurredAt ?? message.receivedAt),
                      if (message.confidence > 0) '${message.confidence}%',
                    ].join(' · '),
                    size: 11.5,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount == null ? '—' : money(amount),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: credit ? t.success : t.foreground,
                  ),
                ),
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: t.mutedForeground,
                  ),
                  child: const Text('Skip', style: TextStyle(fontSize: AppType.label)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
