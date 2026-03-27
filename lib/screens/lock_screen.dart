import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../providers/service_providers.dart';
import '../providers/session_provider.dart';
import '../utils/error_formatter.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen>
    with WidgetsBindingObserver {
  bool _authenticating = false;
  bool _biometricUnavailable = false;
  bool _pendingUnlock = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Only prompt biometrics when iOS confirms the app is fully active;
      // calling earlier triggers "User interaction required" (LAError.notInteractive).
      if (WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed) {
        _tryUnlock();
      } else {
        _pendingUnlock = true;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingUnlock) {
      _pendingUnlock = false;
      // Small safety margin for iOS to fully settle its UI stack.
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _tryUnlock();
      });
    }
  }

  Future<void> _tryUnlock({int retries = 1}) async {
    if (_authenticating) return;
    _authenticating = true;
    try {
      final biometric = ref.read(biometricServiceProvider);
      final available = await biometric.isAvailable();
      if (!available) {
        // Check if key already exists (e.g. restored silently).
        final existingKey = ref.read(userKeyProvider);
        if (existingKey != null) {
          ref.read(isLockedProvider.notifier).state = false;
          return;
        }
        if (mounted) setState(() => _biometricUnavailable = true);
        return;
      }
      if (mounted) setState(() => _biometricUnavailable = false);

      await ref.read(sessionProvider.notifier).unlockWithBiometrics();
      // Guard: if lock() was called while biometric was in progress,
      // the key has been zeroed — do not unlock.
      if (mounted && ref.read(userKeyProvider) != null) {
        ref.read(isLockedProvider.notifier).state = false;
      }
    } catch (e) {
      final msg = e.toString();
      // Retry if iOS wasn't ready for interaction.
      if (retries > 0 &&
          msg.contains('NotAvailable') &&
          msg.contains('interaction')) {
        _authenticating = false;
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) await _tryUnlock(retries: retries - 1);
        return;
      }
      final userCancelled =
          msg.contains('UserCancelled') || msg.contains('PasscodeNotSet');
      if (mounted && !userCancelled) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.unlockFailedMessage(formatError(e, l)))),
        );
      }
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _biometricUnavailable
                    ? Icons.fingerprint_outlined
                    : Icons.lock_outlined,
                size: 64,
                color: _biometricUnavailable
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                _biometricUnavailable ? l.biometricUnavailable : l.locked,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _tryUnlock,
                icon: Icon(_biometricUnavailable
                    ? Icons.refresh
                    : Icons.fingerprint),
                label: Text(
                    _biometricUnavailable ? l.biometricRetry : l.unlock),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
