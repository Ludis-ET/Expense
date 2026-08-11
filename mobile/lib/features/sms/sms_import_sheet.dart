import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../state/sms_state.dart';
import '../../widgets/ui.dart';

Future<void> showSmsImportSheet(BuildContext context) {
  return showAppSheet<void>(
    context,
    title: 'Import history',
    subtitle: 'Pull older bank SMS into your inbox. Re-imports are de-duplicated.',
    builder: (ctx) => const _ImportSheet(),
  );
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet();

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  int _days = 30;
  int? _count;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recount());
  }

  DateTime get _min => DateTime.now().subtract(Duration(days: _days));

  Future<void> _recount() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = await context.read<SmsState>().countHistory(min: _min);
      setState(() => _count = n);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = await context.read<SmsState>().importHistory(min: _min);
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, 'Queued $n messages for upload');
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final d in const [30, 90, 180, 365])
                ChoiceChip(
                  label: Text(d == 365 ? '1 year' : '$d days'),
                  selected: _days == d,
                  onSelected: (_) {
                    setState(() => _days = d);
                    _recount();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _count == null ? 'Counting messages…' : 'About $_count messages in range',
            style: TextStyle(fontWeight: FontWeight.w700, color: t.foreground),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: t.danger, fontSize: 13)),
          ],
          const SizedBox(height: 18),
          AppButton(
            label: _busy ? 'Working…' : 'Import into queue',
            expand: true,
            onPressed: _busy ? null : _run,
          ),
        ],
      ),
    );
  }
}
