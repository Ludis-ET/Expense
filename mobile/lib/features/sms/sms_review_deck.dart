import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';

import '../../core/theme/theme.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../models/common.dart';
import '../../models/ingest.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../state/sms_state.dart';
import '../../widgets/ui.dart';
import 'sms_edit_sheet.dart';

/// Full-screen futuristic swipe deck for unresolved bank messages.
class SmsReviewDeck extends StatefulWidget {
  const SmsReviewDeck({super.key});

  @override
  State<SmsReviewDeck> createState() => _SmsReviewDeckState();
}

class _SmsReviewDeckState extends State<SmsReviewDeck>
    with TickerProviderStateMixin {
  double _dragX = 0;
  bool _busy = false;

  bool _canConfirm(InboxMessage m, DraftConfirm draft) {
    if (draft.accountId == null || draft.accountId!.isEmpty) return false;
    final kind =
        draft.kind ?? m.suggestion?.kind ?? m.parsedKind ?? TxKind.expense;
    if (kind == TxKind.transfer &&
        (draft.transferAccountId == null || draft.transferAccountId!.isEmpty)) {
      return false;
    }
    final amount = draft.amount ?? double.tryParse(m.parsedAmount ?? '');
    return amount != null && amount > 0;
  }

  Future<void> _confirm(InboxMessage m) async {
    if (_busy) return;
    final draft = DraftConfirm.fromMessage(m);
    if (!_canConfirm(m, draft)) {
      Haptics.reject();
      final edited = await showSmsEditSheet(context, message: m);
      if (edited == null || !mounted) return;
      await _submit(m.id, edited);
      return;
    }
    await _submit(m.id, draft.toBody());
  }

  Future<void> _submit(String id, Map<String, dynamic> body) async {
    setState(() => _busy = true);
    try {
      await context.read<SmsState>().confirm(id, body);
      if (!mounted) return;
      await context.read<DataState>().refreshAfterWrite();
      if (!mounted) return;
      Haptics.commit();
      setState(() => _dragX = 0);
      if (context.read<SmsState>().unresolved.isEmpty) {
        Navigator.pop(context);
        toast(context, 'Inbox clear');
      }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(InboxMessage m) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<SmsState>().reject(m.id);
      if (!mounted) return;
      Haptics.select();
      setState(() => _dragX = 0);
      if (context.read<SmsState>().unresolved.isEmpty) {
        Navigator.pop(context);
      }
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final sms = context.watch<SmsState>();
    final prefs = context.watch<PrefsState>();
    final list = sms.unresolved;
    final current = list.isEmpty ? null : list.first;
    final next = list.length > 1 ? list[1] : null;

    return Scaffold(
      backgroundColor: t.background,
      body: MeshBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                child: Row(
                  children: [
                    IconPill(
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text(
                      list.isEmpty ? 'Done' : '${list.length} left',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: t.mutedForeground,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
              Expanded(
                child: current == null
                    ? const Center(
                        child: EmptyState(
                          title: 'All caught up',
                          description: 'Every bank message has been reviewed.',
                          icon: Icons.verified_rounded,
                        ),
                      )
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          if (next != null)
                            Transform.scale(
                              scale: 0.94,
                              child: Opacity(
                                opacity: 0.55,
                                child: _CardFace(
                                  message: next,
                                  money: prefs.money,
                                  dragX: 0,
                                ),
                              ),
                            ),
                          GestureDetector(
                            onHorizontalDragUpdate: (d) {
                              setState(() => _dragX += d.delta.dx);
                            },
                            onHorizontalDragEnd: (d) {
                              final vx = d.primaryVelocity ?? 0;
                              if (_dragX > 110 || vx > 800) {
                                unawaitedConfirm(current);
                              } else if (_dragX < -110 || vx < -800) {
                                unawaitedReject(current);
                              } else {
                                setState(() => _dragX = 0);
                              }
                            },
                            onTap: () async {
                              final body = await showSmsEditSheet(
                                context,
                                message: current,
                              );
                              if (body != null) await _submit(current.id, body);
                            },
                            child: Transform.translate(
                              offset: Offset(_dragX, 0),
                              child: Transform.rotate(
                                angle: _dragX / 900,
                                child: _CardFace(
                                  message: current,
                                  money: prefs.money,
                                  dragX: _dragX,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              if (current != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(S.xl, S.sm, S.xl, S.lg),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Skip',
                          variant: BtnVariant.outline,
                          icon: Icons.close_rounded,
                          onPressed: _busy ? null : () => _reject(current),
                        ),
                      ),
                      const GapX(S.sm),
                      Expanded(
                        child: AppButton(
                          label: 'Edit',
                          variant: BtnVariant.secondary,
                          icon: Icons.tune_rounded,
                          onPressed: _busy
                              ? null
                              : () async {
                                  final body = await showSmsEditSheet(
                                    context,
                                    message: current,
                                  );
                                  if (body != null)
                                    await _submit(current.id, body);
                                },
                        ),
                      ),
                      const GapX(S.sm),
                      Expanded(
                        child: AppButton(
                          label: 'Record',
                          icon: Icons.check_rounded,
                          onPressed: _busy ? null : () => _confirm(current),
                        ),
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

  void unawaitedConfirm(InboxMessage m) => _confirm(m);
  void unawaitedReject(InboxMessage m) => _reject(m);
}

class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.message,
    required this.money,
    required this.dragX,
  });

  final InboxMessage message;
  final String Function(
    Object? v, {
    String currency,
    bool decimals,
    bool compact,
  })
  money;
  final double dragX;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final credit = message.isCredit;
    final confirmOpacity = (dragX / 120).clamp(0.0, 1.0);
    final skipOpacity = (-dragX / 120).clamp(0.0, 1.0);
    final amount = message.parsedAmount;
    final currency = message.parsedCurrency ?? 'ETB';
    final kind = message.suggestion?.kind ?? message.parsedKind;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.xl, vertical: S.md),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(S.xxl, S.xxl, S.xxl, S.xl),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Pill(
                        icon: Icons.account_balance_rounded,
                        label: message.bankLabel ?? message.sender,
                      ),
                      const Spacer(),
                      _Pill(
                        label: credit ? 'Credited' : 'Debited',
                        color: credit ? t.success : t.danger,
                      ),
                    ],
                  ),
                  const Gap(S.xxl),
                  Text(
                    amount == null ? ' ' : money(amount, currency: currency),
                    style: TextStyle(
                      fontSize: AppType.hero,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.2,
                      color: t.foreground,
                      height: 1,
                    ),
                  ),
                  const Gap(S.sm),
                  Text(
                    message.parsedPayee ?? 'Unknown counterparty',
                    style: TextStyle(
                      fontSize: AppType.lead,
                      fontWeight: FontWeight.w700,
                      color: t.foreground,
                    ),
                  ),
                  const Gap(S.xs),
                  Muted(
                    [
                      if (kind != null) kind.label,
                      formatDate(message.occurredAt ?? message.receivedAt),
                      if (message.parsedRef != null) 'ref ${message.parsedRef}',
                    ].join(' · '),
                    size: 13,
                  ),
                  if (message.suggestion?.reason != null) ...[
                    const Gap(S.md),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(S.md),
                      decoration: BoxDecoration(
                        color: t.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: t.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        message.suggestion!.reason!,
                        style: TextStyle(
                          fontSize: AppType.label,
                          height: 1.4,
                          color: t.foreground,
                        ),
                      ),
                    ),
                  ],
                  const Gap(S.lg),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ConfChip(confidence: message.confidence),
                      if (message.account == null)
                        _NeedChip(label: 'Pick wallet', color: t.warning),
                      if ((kind ?? TxKind.expense) == TxKind.transfer &&
                          message.suggestion?.transferAccountId == null)
                        _NeedChip(label: 'Pick destination', color: t.warning),
                      if (message.parsedAmount == null)
                        _NeedChip(label: 'Set amount', color: t.danger),
                    ],
                  ),
                  const Spacer(),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text(
                      'Original SMS',
                      style: TextStyle(
                        fontSize: AppType.bodySm,
                        color: t.mutedForeground,
                      ),
                    ),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(S.md),
                        decoration: BoxDecoration(
                          color: t.surfaceMuted.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          message.body,
                          style: TextStyle(
                            fontSize: AppType.label,
                            height: 1.45,
                            color: t.foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Positioned(
                top: 70,
                left: 8,
                child: Opacity(
                  opacity: skipOpacity,
                  child: _Stamp(label: 'SKIP', color: t.mutedForeground),
                ),
              ),
              Positioned(
                top: 70,
                right: 8,
                child: Opacity(
                  opacity: confirmOpacity,
                  child: _Stamp(label: 'RECORD', color: t.success),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.35,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.xs),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: AppType.lead,
          ),
        ),
      ),
    );
  }
}

class _ConfChip extends StatelessWidget {
  const _ConfChip({required this.confidence});
  final int confidence;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = confidence >= 80
        ? t.success
        : confidence >= 50
        ? t.warning
        : t.danger;
    return _Pill(label: '$confidence% sure', color: color);
  }
}

class _NeedChip extends StatelessWidget {
  const _NeedChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _Pill(label: label, color: color, icon: Icons.error_outline);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.icon, this.color});
  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = color ?? t.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.xs),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: c),
            const GapX(S.xxs),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: AppType.label,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

/// Draft fields derived from a message before edit/confirm.
class DraftConfirm {
  DraftConfirm({
    this.accountId,
    this.categoryId,
    this.transferAccountId,
    this.kind,
    this.amount,
    this.currency,
    this.date,
    this.payee,
    this.note,
    this.rememberMapping = false,
  });

  String? accountId;
  String? categoryId;
  String? transferAccountId;
  TxKind? kind;
  double? amount;
  String? currency;
  DateTime? date;
  String? payee;
  String? note;
  bool rememberMapping;

  factory DraftConfirm.fromMessage(InboxMessage m) {
    final kind = m.suggestion?.kind ?? m.parsedKind ?? TxKind.expense;
    return DraftConfirm(
      accountId: m.account?.id,
      transferAccountId: m.suggestion?.transferAccountId,
      kind: kind,
      amount: double.tryParse(m.parsedAmount ?? ''),
      currency: m.parsedCurrency,
      date: m.occurredAt ?? m.receivedAt,
      payee: m.parsedPayee,
      note: m.parsedRef == null
          ? (m.bankLabel ?? m.sender)
          : '${m.bankLabel ?? m.sender} · ref ${m.parsedRef}',
    );
  }

  Map<String, dynamic> toBody() => {
    if (accountId != null) 'accountId': accountId,
    if (categoryId != null) 'categoryId': categoryId,
    if (transferAccountId != null) 'transferAccountId': transferAccountId,
    if (kind != null) 'kind': kind!.wire,
    if (amount != null) 'amount': amount,
    if (currency != null) 'currency': currency,
    if (date != null) 'date': date!.toUtc().toIso8601String(),
    if (payee != null) 'payee': payee,
    if (note != null) 'note': note,
    'rememberMapping': rememberMapping,
    'tags': <String>[],
  };
}
