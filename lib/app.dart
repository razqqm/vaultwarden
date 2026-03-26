import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'providers/session_provider.dart';
import 'screens/lock_screen.dart';
import 'screens/requests_screen.dart';
import 'screens/setup_screen.dart';

/// Theme mode: system (default), light, or dark.
final themeModeProvider = StateProvider<ThemeMode>((_) => ThemeMode.system);

/// App locale: null = system default.
final localeProvider = StateProvider<Locale?>((_) => null);

/// Lock timeout in seconds. 0 = immediate, -1 = never.
final lockTimeoutProvider = StateProvider<int>((_) => 0);

/// Poll interval in seconds for auth request refresh.
final pollIntervalProvider = StateProvider<int>((_) => 15);

/// Whether the app is locked (biometric required before showing content).
/// Starts as true — the very first frame never shows sensitive data.
final isLockedProvider = StateProvider<bool>((_) => true);

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isLocked = ref.read(isLockedProvider);

    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      // Lock immediately when leaving foreground.
      // This runs BEFORE iOS captures the app snapshot, so
      // the snapshot (and the first resumed frame) show LockScreen.
      if (!isLocked) {
        final timeout = ref.read(lockTimeoutProvider);
        if (timeout != -1) {
          _pausedAt ??= DateTime.now();
          ref.read(isLockedProvider.notifier).state = true;
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      final timeout = ref.read(lockTimeoutProvider);
      if (timeout == -1) return; // never-lock mode

      if (_pausedAt != null) {
        final elapsed = DateTime.now().difference(_pausedAt!).inSeconds;
        _pausedAt = null;

        if (elapsed < timeout) {
          // Timeout not reached — unlock without biometric.
          // The key is still in memory; just flip the flag.
          ref.read(isLockedProvider.notifier).state = false;
        } else {
          // Timeout exceeded — clear key, LockScreen will ask for biometric.
          ref.read(sessionProvider.notifier).lock();
        }
      }
      // If _pausedAt == null (e.g. biometric dialog triggered pause/resume),
      // do nothing — LockScreen handles its own flow.
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(sessionProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final isLocked = ref.watch(isLockedProvider);

    return MaterialApp(
      title: 'Vault Approver',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
      ),
      home: sessionAsync.when(
        data: (session) {
          FlutterNativeSplash.remove();
          if (session == null) return const SetupScreen();
          if (isLocked) return const LockScreen();
          return const RequestsScreen();
        },
        loading: () {
          FlutterNativeSplash.remove();
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icon/vault_approver_1024.png',
                    width: 120,
                    height: 120,
                  ),
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          );
        },
        error: (_, __) {
          FlutterNativeSplash.remove();
          return const SetupScreen();
        },
      ),
    );
  }
}
