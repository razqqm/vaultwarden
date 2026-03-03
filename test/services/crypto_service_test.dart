import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_approver/models/cipher_string.dart';
import 'package:vault_approver/models/encryption_type.dart';
import 'package:vault_approver/models/kdf_params.dart';
import 'package:vault_approver/services/crypto_service.dart';

void main() {
  late CryptoService crypto;

  setUp(() {
    crypto = CryptoService();
  });

  group('CryptoService', () {
    // ── PBKDF2 Key Derivation ──

    group('deriveMasterKey (PBKDF2)', () {
      test('derives deterministic key from email + password', () async {
        final kdf = KdfParams(kdfType: 0, iterations: 100);

        final key1 = await crypto.deriveMasterKey('test@example.com', 'password123', kdf);
        final key2 = await crypto.deriveMasterKey('test@example.com', 'password123', kdf);

        expect(key1, hasLength(32));
        expect(key1, equals(key2));
      });

      test('different passwords produce different keys', () async {
        final kdf = KdfParams(kdfType: 0, iterations: 100);

        final key1 = await crypto.deriveMasterKey('test@example.com', 'password1', kdf);
        final key2 = await crypto.deriveMasterKey('test@example.com', 'password2', kdf);

        expect(key1, isNot(equals(key2)));
      });

      test('email is case-insensitive', () async {
        final kdf = KdfParams(kdfType: 0, iterations: 100);

        final key1 = await crypto.deriveMasterKey('Test@Example.COM', 'pass', kdf);
        final key2 = await crypto.deriveMasterKey('test@example.com', 'pass', kdf);

        expect(key1, equals(key2));
      });
    });

    // ── HKDF Key Stretching ──

    group('stretchMasterKey', () {
      test('produces 64 bytes from 32-byte input', () {
        final masterKey = Uint8List(32);
        final stretched = crypto.stretchMasterKey(masterKey);

        expect(stretched, hasLength(64));
      });

      test('is deterministic', () {
        final masterKey = Uint8List.fromList(List.generate(32, (i) => i));
        final s1 = crypto.stretchMasterKey(masterKey);
        final s2 = crypto.stretchMasterKey(masterKey);

        expect(s1, equals(s2));
      });

      test('enc and mac halves are different', () {
        final masterKey = Uint8List.fromList(List.generate(32, (i) => i));
        final stretched = crypto.stretchMasterKey(masterKey);

        final encKey = stretched.sublist(0, 32);
        final macKey = stretched.sublist(32, 64);

        expect(encKey, isNot(equals(macKey)));
      });
    });

    // ── Master Password Hash ──

    group('deriveMasterPasswordHash', () {
      test('produces 32 bytes', () async {
        final masterKey = Uint8List.fromList(List.generate(32, (i) => i));
        final hash = await crypto.deriveMasterPasswordHash(masterKey, 'password');

        expect(hash, hasLength(32));
      });

      test('is deterministic', () async {
        final masterKey = Uint8List.fromList(List.generate(32, (i) => i));
        final h1 = await crypto.deriveMasterPasswordHash(masterKey, 'password');
        final h2 = await crypto.deriveMasterPasswordHash(masterKey, 'password');

        expect(h1, equals(h2));
      });
    });

    // ── Symmetric Encryption / Decryption ──

    group('encryptSymmetric / decryptSymmetric', () {
      test('roundtrips data correctly', () {
        final key = Uint8List.fromList(List.generate(64, (i) => i));
        final plaintext = Uint8List.fromList(utf8.encode('Hello, Bitwarden!'));

        final encrypted = crypto.encryptSymmetric(plaintext, key);
        expect(encrypted.encType, EncryptionType.aesCbc256_HmacSha256_B64);
        expect(encrypted.iv, hasLength(16));
        expect(encrypted.mac, hasLength(32));

        final decrypted = crypto.decryptSymmetric(encrypted, key);
        expect(decrypted, equals(plaintext));
      });

      test('different encryptions produce different ciphertexts (random IV)', () {
        final key = Uint8List.fromList(List.generate(64, (i) => i));
        final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);

        final enc1 = crypto.encryptSymmetric(plaintext, key);
        final enc2 = crypto.encryptSymmetric(plaintext, key);

        // IVs should differ
        expect(enc1.iv, isNot(equals(enc2.iv)));
        // Ciphertexts should differ
        expect(enc1.ciphertext, isNot(equals(enc2.ciphertext)));
      });

      test('fails on tampered MAC', () {
        final key = Uint8List.fromList(List.generate(64, (i) => i));
        final plaintext = Uint8List.fromList([1, 2, 3]);

        final encrypted = crypto.encryptSymmetric(plaintext, key);

        // Tamper with MAC
        final tamperedMac = Uint8List.fromList(encrypted.mac!);
        tamperedMac[0] ^= 0xFF;

        final tampered = CipherString(
          encType: encrypted.encType,
          iv: encrypted.iv,
          ciphertext: encrypted.ciphertext,
          mac: tamperedMac,
        );

        expect(
          () => crypto.decryptSymmetric(tampered, key),
          throwsA(isA<StateError>()),
        );
      });

      test('fails on wrong key', () {
        final key1 = Uint8List.fromList(List.generate(64, (i) => i));
        final key2 = Uint8List.fromList(List.generate(64, (i) => i + 1));
        final plaintext = Uint8List.fromList([1, 2, 3]);

        final encrypted = crypto.encryptSymmetric(plaintext, key1);

        expect(
          () => crypto.decryptSymmetric(encrypted, key2),
          throwsA(isA<StateError>()), // MAC check fails
        );
      });
    });

    // ── decryptUserKey ──

    group('decryptUserKey', () {
      test('decrypts a protectedSymmetricKey encrypted with stretchedMasterKey', () {
        // Simulate what the server stores:
        // 1. Generate a known "userKey" (64 bytes)
        final userKey = Uint8List.fromList(List.generate(64, (i) => (i * 7 + 3) % 256));

        // 2. Encrypt it with a known stretchedMasterKey
        final stretchedMasterKey = Uint8List.fromList(List.generate(64, (i) => i));
        final protectedKey = crypto.encryptSymmetric(userKey, stretchedMasterKey);

        // 3. Decrypt and verify
        final decrypted = crypto.decryptUserKey(protectedKey, stretchedMasterKey);
        expect(decrypted, equals(userKey));
      });

      test('rejects non-type-2 cipher strings', () {
        final key = Uint8List(64);
        final cs = CipherString(
          encType: EncryptionType.rsa2048_OaepSha1_B64,
          ciphertext: Uint8List(256),
        );

        expect(
          () => crypto.decryptUserKey(cs, key),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    // ── Full PBKDF2 Crypto Chain ──

    group('full PBKDF2 crypto chain', () {
      test('setup → encrypt → decrypt roundtrip', () async {
        final email = 'test@bitwarden.com';
        final password = 'my-master-password';
        final kdf = KdfParams(kdfType: 0, iterations: 100);

        // 1. Derive master key
        final masterKey = await crypto.deriveMasterKey(email, password, kdf);
        expect(masterKey, hasLength(32));

        // 2. Stretch
        final stretched = crypto.stretchMasterKey(masterKey);
        expect(stretched, hasLength(64));

        // 3. Password hash
        final hash = await crypto.deriveMasterPasswordHash(masterKey, password);
        expect(hash, hasLength(32));
        expect(base64Encode(hash), isNotEmpty);

        // 4. Simulate server: create and encrypt userKey
        final userKey = Uint8List.fromList(List.generate(64, (i) => (i * 13) % 256));
        final protectedKey = crypto.encryptSymmetric(userKey, stretched);

        // 5. Decrypt (what the client does)
        final decrypted = crypto.decryptUserKey(protectedKey, stretched);
        expect(decrypted, equals(userKey));
      });
    });

    // ── Argon2id ──

    group('deriveMasterKey (Argon2id)', () {
      test('derives 32-byte key with minimal params', () async {
        final kdf = KdfParams(
          kdfType: 1,
          iterations: 1,
          memory: 16384, // 16 MiB in KiB
          parallelism: 1,
        );

        final key = await crypto.deriveMasterKey('test@example.com', 'password', kdf);
        expect(key, hasLength(32));
      });

      test('is deterministic', () async {
        final kdf = KdfParams(
          kdfType: 1,
          iterations: 1,
          memory: 16384,
          parallelism: 1,
        );

        final k1 = await crypto.deriveMasterKey('user@test.com', 'pass', kdf);
        final k2 = await crypto.deriveMasterKey('user@test.com', 'pass', kdf);
        expect(k1, equals(k2));
      });
    });

    // ── Fingerprint Phrase ──

    group('generateFingerprintPhrase', () {
      test('produces 5 dash-separated words', () {
        final wordlist = List.generate(7776, (i) => 'word$i');
        final publicKeyB64 = base64Encode(Uint8List.fromList(List.generate(256, (i) => i)));

        final phrase = crypto.generateFingerprintPhrase(publicKeyB64, 'test@example.com', wordlist);

        final words = phrase.split('-');
        expect(words, hasLength(5));
        for (final word in words) {
          expect(word, startsWith('word'));
        }
      });

      test('is deterministic', () {
        final wordlist = List.generate(7776, (i) => 'word$i');
        final publicKeyB64 = base64Encode(Uint8List(128));

        final p1 = crypto.generateFingerprintPhrase(publicKeyB64, 'a@b.com', wordlist);
        final p2 = crypto.generateFingerprintPhrase(publicKeyB64, 'a@b.com', wordlist);
        expect(p1, equals(p2));
      });

      test('email is case-insensitive', () {
        final wordlist = List.generate(7776, (i) => 'w$i');
        final publicKeyB64 = base64Encode(Uint8List(128));

        final p1 = crypto.generateFingerprintPhrase(publicKeyB64, 'Test@Example.COM', wordlist);
        final p2 = crypto.generateFingerprintPhrase(publicKeyB64, 'test@example.com', wordlist);
        expect(p1, equals(p2));
      });

      test('different public keys produce different phrases', () {
        final wordlist = List.generate(7776, (i) => 'w$i');
        final pk1 = base64Encode(Uint8List.fromList(List.generate(128, (i) => 0)));
        final pk2 = base64Encode(Uint8List.fromList(List.generate(128, (i) => 1)));

        final p1 = crypto.generateFingerprintPhrase(pk1, 'a@b.com', wordlist);
        final p2 = crypto.generateFingerprintPhrase(pk2, 'a@b.com', wordlist);
        expect(p1, isNot(equals(p2)));
      });
    });

    // ── Symmetric encrypt → CipherString parse → decrypt roundtrip ──

    group('CipherString integration', () {
      test('encrypt → encode → parse → decrypt roundtrip', () {
        final key = Uint8List.fromList(List.generate(64, (i) => (i * 3 + 7) % 256));
        final plaintext = Uint8List.fromList(utf8.encode('vault data roundtrip test'));

        // Encrypt
        final encrypted = crypto.encryptSymmetric(plaintext, key);

        // Serialize to string (as server would store)
        final encoded = encrypted.encode();
        expect(encoded, startsWith('2.'));

        // Parse back (as client would receive)
        final parsed = CipherString.parse(encoded);

        // Decrypt
        final decrypted = crypto.decryptSymmetric(parsed, key);
        expect(utf8.decode(decrypted), equals('vault data roundtrip test'));
      });
    });
  });
}
