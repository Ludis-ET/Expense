import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/theme.dart';
import 'offline/local_db.dart';
import 'offline/sync_engine.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_shell.dart';
import 'screens/splash_screen.dart';
import 'state/auth_store.dart';
import 'state/capture_store.dart';
import 'state/data_store.dart';
import 'state/notification_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final api = ApiClient(baseUrl: AuthStore.defaultBaseUrl);
  final db = await LocalDb.open();
  final sync = SyncEngine(api: api, db: db);

  runApp(SantimApp(api: api, db: db, sync: sync));
}

class SantimApp extends StatefulWidget {
  const SantimApp({
    super.key,
    required this.api,
    required this.db,
    required this.sync,
  });

  final ApiClient api;
  final LocalDb db;
  final SyncEngine sync;

  @override
  State<SantimApp> createState() => _SantimAppState();
}

class _SantimAppState extends State<SantimApp> {
  late final AuthStore _auth;
  late final DataStore _data;
  late final CaptureStore _capture;
  late final NotificationStore _notifications;

  @override
  void initState() {
    super.initState();
    _auth = AuthStore(api: widget.api, db: widget.db)..bootstrap();
    _data = DataStore(api: widget.api, db: widget.db, sync: widget.sync);
    _capture = CaptureStore(api: widget.api, db: widget.db, sync: widget.sync);
    _notifications = NotificationStore(api: widget.api, db: widget.db);
    widget.sync.start();
    _auth.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (_auth.phase == AuthPhase.signedOut) {
      _notifications.reset();
      _data.reset();
      _capture.reset();
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _notifications.dispose();
    widget.sync.dispose();
    widget.api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: widget.api),
        Provider<LocalDb>.value(value: widget.db),
        ChangeNotifierProvider<SyncEngine>.value(value: widget.sync),
        ChangeNotifierProvider<AuthStore>.value(value: _auth),
        ChangeNotifierProvider<DataStore>.value(value: _data),
        ChangeNotifierProvider<CaptureStore>.value(value: _capture),
        ChangeNotifierProvider<NotificationStore>.value(value: _notifications),
      ],
      child: MaterialApp(
        title: 'Santim',
        debugShowCheckedModeBanner: false,
        theme: SantimTheme.light(),
        darkTheme: SantimTheme.dark(),
        home: const _Root(),
      ),
    );
  }
}

/// Switches between splash, auth and the app once the session is known.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final phase = context.select<AuthStore, AuthPhase>((s) => s.phase);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(
        key: ValueKey(phase),
        child: switch (phase) {
          AuthPhase.loading => const SplashScreen(),
          AuthPhase.signedOut => const LoginScreen(),
          AuthPhase.signedIn => const HomeShell(),
        },
      ),
    );
  }
}
