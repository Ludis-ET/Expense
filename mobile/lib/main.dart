import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'features/auth/auth_screen.dart';
import 'features/lock/app_lock_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/splash/splash_screen.dart';
import 'state/app_lock_state.dart';
import 'state/auth_state.dart';
import 'state/data_state.dart';
import 'state/prefs_state.dart';
import 'state/sms_state.dart';
import 'state/sync_state.dart';

Future<void> main() async {
  final bindings = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: bindings);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final prefs = await SharedPreferences.getInstance();
  final tokens = TokenStore(prefs);
  final api = ApiClient(tokens: tokens);

  // Anyone already signed in when this build arrived has been using Santim for
  // a while — the intro is for new accounts, not for an upgrade.
  if (!prefs.containsKey(PrefsState.onboardedKey) && tokens.refresh != null) {
    await prefs.setBool(PrefsState.onboardedKey, true);
  }

  runApp(SantimApp(prefs: prefs, api: api));
}

class SantimApp extends StatelessWidget {
  const SantimApp({super.key, required this.prefs, required this.api});

  final SharedPreferences prefs;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider(create: (_) => PrefsState(prefs)),
        ChangeNotifierProvider(
          create: (_) => AppLockState(prefs)..bootstrap(),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthState(api: api, prefs: prefs)..bootstrap(),
        ),
        ChangeNotifierProvider(
          create: (_) => SyncState(api: api)..start(),
        ),
        ChangeNotifierProvider(
          create: (ctx) => DataState(api, sync: ctx.read<SyncState>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) => SmsState(
            api: api,
            prefs: prefs,
            sync: ctx.read<SyncState>(),
          )..start(),
        ),
      ],
      child: Consumer<PrefsState>(
        builder: (context, prefsState, _) => MaterialApp(
          title: 'Santim',
          debugShowCheckedModeBanner: false,
          themeMode: prefsState.themeMode,
          theme: buildTheme(SantimTokens.light),
          darkTheme: buildTheme(SantimTokens.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              // The ceiling used to be 1.25, which meant someone who set 200%
              // text in Android settings got 125% — the app overriding an
              // accessibility control rather than honouring it. 1.6 covers the
              // large-text range; beyond that the densest screens (analytics
              // tables, the ledger) stop fitting on a phone at all.
              textScaler: TextScaler.linear(
                MediaQuery.textScalerOf(context).scale(1).clamp(0.85, 1.6),
              ),
              disableAnimations: prefsState.reduceMotion,
            ),
            child: child!,
          ),
          home: const _Gate(),
        ),
      ),
    );
  }
}

/// Splash → auth → optional app lock → shell.
class _Gate extends StatefulWidget {
  const _Gate();

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final lock = context.watch<AppLockState>();

    final showSplash = !_splashDone || auth.loading || !lock.ready;

    Widget child;
    if (showSplash) {
      child = SplashScreen(
        key: const ValueKey('splash'),
        onDone: () {
          if (mounted) setState(() => _splashDone = true);
        },
      );
    } else if (!auth.isAuthed) {
      child = const AuthScreen(key: ValueKey('auth'));
    } else if (lock.requiresUnlock) {
      child = const AppLockScreen(key: ValueKey('lock'));
    } else if (!context.watch<PrefsState>().onboarded) {
      child = const OnboardingScreen(key: ValueKey('onboarding'));
    } else {
      child = const AppShell(key: ValueKey('shell'));
    }

    return AnimatedSwitcher(
      duration: SplashScreen.fade,
      switchInCurve: Motion.easeOut,
      switchOutCurve: Motion.easeOut,
      child: child,
    );
  }
}
