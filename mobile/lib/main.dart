import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/theme/theme.dart';
import 'core/theme/tokens.dart';
import 'features/auth/auth_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/splash/splash_screen.dart';
import 'state/auth_state.dart';
import 'state/data_state.dart';
import 'state/prefs_state.dart';
import 'state/sms_state.dart';
import 'state/sync_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
            // The app's own type scale should not be blown out by a very large
            // system font setting; 1.25 keeps every card legible.
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                MediaQuery.textScalerOf(context).scale(1).clamp(0.85, 1.25),
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

/// Holds the splash for its full run, then shows the shell or the auth screen
/// depending on whether the restored session held up.
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

    // The splash covers the bootstrap request, so there is never a flash of
    // the login screen for a user who is already signed in.
    final showSplash = !_splashDone || auth.loading;

    return AnimatedSwitcher(
      duration: SplashScreen.fade,
      switchInCurve: Motion.easeOut,
      switchOutCurve: Motion.easeOut,
      child: showSplash
          ? SplashScreen(
              key: const ValueKey('splash'),
              onDone: () {
                if (mounted) setState(() => _splashDone = true);
              },
            )
          : auth.isAuthed
              ? const AppShell(key: ValueKey('shell'))
              : const AuthScreen(key: ValueKey('auth')),
    );
  }
}
