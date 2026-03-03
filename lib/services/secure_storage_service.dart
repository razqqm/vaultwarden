import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../models/user_session.dart';

class SecureStorageService {
  static const _keySession = 'session';
  static const _keyEncryptedUserKey = 'encrypted_user_key';
  static const _keyStorageKey = 'biometric_storage_key';
  static const _keyDeviceId = 'device_id';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.passcode,
    ),
  );

  // ── Session ──

  Future<void> saveSession(UserSession session) async {
    await _storage.write(
      key: _keySession,
      value: jsonEncode(session.toJson()),
    );
  }

  Future<UserSession?> loadSession() async {
    final raw = await _storage.read(key: _keySession);
    if (raw == null) return null;
    return UserSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> deleteSession() async {
    await _storage.delete(key: _keySession);
  }

  // ── Encrypted UserKey ──

  Future<void> saveEncryptedUserKey(String cipherString) async {
    await _storage.write(key: _keyEncryptedUserKey, value: cipherString);
  }

  Future<String?> loadEncryptedUserKey() async {
    return _storage.read(key: _keyEncryptedUserKey);
  }

  // ── Biometric Storage Key ──

  Future<void> saveBiometricStorageKey(String base64Key) async {
    await _storage.write(key: _keyStorageKey, value: base64Key);
  }

  Future<String?> loadBiometricStorageKey() async {
    return _storage.read(key: _keyStorageKey);
  }

  // ── Device ID ──

  Future<String> getOrCreateDeviceId() async {
    var id = await _storage.read(key: _keyDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      await _storage.write(key: _keyDeviceId, value: id);
    }
    return id;
  }

  // ── Setup check ──

  Future<bool> hasCompletedSetup() async {
    final key = await _storage.read(key: _keyEncryptedUserKey);
    final session = await _storage.read(key: _keySession);
    return key != null && session != null;
  }

  // ── Clear all ──

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
