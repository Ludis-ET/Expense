import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatting.dart';
import '../../core/theme.dart';
import '../../models/ingest.dart';
import '../../state/capture_store.dart';
import '../../widgets/common.dart';
import 'capture_setup_screen.dart';
import 'review_deck_screen.dart';
import 'review_sheet.dart';

/// Bank messages waiting to become transactions.
///
/// Nothing here has touched the ledger yet. That is the whole design: a
/// mis-parsed message that auto-posted would have to be unpicked from budget
/// reservations and balances, so by default everything stops here first.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final capture = context.watch<CaptureStore>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Message inbox'),
        actions: [
          if (capture.isPaired)
            IconButton(
              tooltip: 'Re-read messages with the latest patterns',
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                final updated = await capture.reparse();
                if (context.mounted) {
                  showOk(
                    context,
                    updated == 0 ? 'Nothing changed' : 'Re-read $updated message(s)',
                  );
                }
              },
            ),
          IconButton(
            tooltip: 'Capture settings',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CaptureSetupScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: capture.refresh,
        child: !capture.isPaired
            ? ListView(
                children: [
                  const SizedBox(height: 90),
                  EmptyState(
                    icon: Icons.sms_outlined,
                    title: 'Capture is not set up',
                    message:
                        'Pair this phone and pick your banks. Santim will then read those '
                        'messages as they arrive and queue the transactions here.',
                    action: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(200, 48)),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CaptureSetupScreen()),
                      ),
                      child: const Text('Set up capture'),
                    ),
                  ),
                ],
              )
            : capture.inbox.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 110),
                      EmptyState(
                        icon: Icons.inbox_outlined,
                        title: 'All caught up',
                        message: 'New bank messages will appear here for a quick check.',
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: capture.inbox.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) return _ReviewAllBanner(count: capture.needsReview);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _MessageCard(message: capture.inbox[i - 1]),
                      );
                    },
                  ),
      ),
    );
  }
}

/// Entry point to the swipe deck.
///
/// Going through messages one at a time in a full-screen deck is much faster
/// than tapping into each one from a list, so it is the offer at the top -
/// the list stays for picking out a specific message.
class _ReviewAllBanner extends StatelessWidget {
  const _ReviewAllBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (count == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ReviewDeckScreen()),
          ),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withValues(alpha: 0.8),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Review all $count',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Swipe right to record, left to skip',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.swipe, color: Colors.white, size: 28),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final InboxMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = message.isParsed;
    final isIncome = message.parsedKind == 'INCOME';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _review(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      message.bankLabel ?? message.sender,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    Dates.relative(message.receivedAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (parsed)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        message.displayTitle,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${isIncome ? '+' : '−'}${Money.format(
                        message.parsedAmount,
                        currency: message.parsedCurrency ?? 'ETB',
                      )}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isIncome ? SantimTheme.income : SantimTheme.expense,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  "Couldn't read this one",
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: SantimTheme.warning,
                  ),
                ),

              const SizedBox(height: 8),
              Text(
                message.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 12),
              Row(
                children: [
                  if (parsed) _ConfidencePill(confidence: message.confidence),
                  if (message.parsedRef != null) ...[
                    const SizedBox(width: 8),
                    StatusPill(label: 'Ref ${message.parsedRef}', tone: PillTone.neutral),
                  ],
                  const Spacer(),
                  TextButton(
                    onPressed: () => _review(context),
                    child: Text(parsed ? 'Review' : 'Fix it'),
                  ),
                ],
              ),

              // An auto-post that was refused explains itself here - usually
              // the overdraw guard, which is worth reading rather than hiding.
              if (message.error != null) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: SantimTheme.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    message.error!,
                    style: theme.textTheme.bodySmall?.copyWith(color: SantimTheme.warning),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _review(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ReviewSheet(message: message),
      );
}

/// How much of the message the parser understood.
class _ConfidencePill extends StatelessWidget {
  const _ConfidencePill({required this.confidence});

  final int confidence;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (confidence) {
      >= 80 => ('Clear read', PillTone.good),
      >= 65 => ('Partly read', PillTone.warn),
      _ => ('Unsure', PillTone.bad),
    };

    return StatusPill(label: label, tone: tone);
  }
}
