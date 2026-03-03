import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'providers/session_provider.dart';
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

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

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
        data: (session) =>
            session == null ? const SetupScreen() : const RequestsScreen(),
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => const SetupScreen(),
      ),
    );
  }
}
