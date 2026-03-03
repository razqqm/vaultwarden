import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/biometric_service.dart';
import '../services/crypto_service.dart';
import '../services/notification_service.dart';
import '../services/secure_storage_service.dart';
import '../services/vault_api.dart';

final cryptoServiceProvider = Provider<CryptoService>((_) => CryptoService());

final biometricServiceProvider =
    Provider<BiometricService>((_) => BiometricService());

final secureStorageProvider =
    Provider<SecureStorageService>((_) => SecureStorageService());

final apiServiceProvider = Provider<VaultApiService>(
  (ref) => VaultApiService(ref.read(secureStorageProvider)),
);

final notificationServiceProvider =
    Provider<NotificationService>((_) => NotificationService());
