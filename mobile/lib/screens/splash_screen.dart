import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../widgets/common.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SantimColors>()!;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const BrandMark(size: 56),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                children: [
                  const TextSpan(text: 'San'),
                  TextSpan(text: 'tim', style: TextStyle(color: colors.primary)),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: colors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
