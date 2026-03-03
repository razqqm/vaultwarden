import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

import '../models/cipher_string.dart';
import '../models/encryption_type.dart';
import '../models/kdf_params.dart';

/// Implements the complete Bitwarden-compatible crypto chain in pure Dart.
///
/// Key hierarchy:
///   masterPassword + email → KDF → masterKey (32B)
///   masterKey → HKDF-Expand → stretchedMasterKey (64B = encKey + macKey)
///   stretchedMasterKey → decrypt(protectedSymmetricKey) → userKey (64B)
///   userKey → RSA-OAEP-SHA1(publicKey) → encryptedKey (for auth request approval)
class CryptoService {
  // ──────────────────────────────────────────────
  // Key Derivation
  // ──────────────────────────────────────────────

  /// Derive masterKey from email + masterPassword using server-provided KDF params.
  Future<Uint8List> deriveMasterKey(
    String email,
    String masterPassword,
    KdfParams kdf,
  ) async {
    final passwordBytes = utf8.encode(masterPassword);

    if (kdf.isArgon2id) {
      final emailBytes = utf8.encode(email.toLowerCase());
      // Argon2id salt = SHA-256(email), then truncated to 16 bytes
      final emailHash = _sha256(Uint8List.fromList(emailBytes));
      final salt = Uint8List.sublistView(emailHash, 0, 16);

      final algorithm = crypto.Argon2id(
        memory: kdf.memory ?? 65536, // already in KiB (e.g. 65536 = 64 MiB)
        parallelism: kdf.parallelism ?? 4,
        iterations: kdf.iterations,
        hashLength: 32,
      );

      final result = await algorithm.deriveKey(
        secretKey: crypto.SecretKey(passwordBytes),
        nonce: salt,
      );
      return Uint8List.fromList(await result.extractBytes());
    } else {
      // PBKDF2-SHA256
      final salt = utf8.encode(email.toLowerCase());
      return _pbkdf2Sha256(
        Uint8List.fromList(passwordBytes),
        Uint8List.fromList(salt),
        kdf.iterations,
        32,
      );
    }
  }

  /// Stretch masterKey (32 bytes) → stretchedMasterKey (64 bytes)
  /// using HKDF-Expand(SHA-256).
  ///   encKey = HKDF-Expand(prk=masterKey, info="enc", len=32)
  ///   macKey = HKDF-Expand(prk=masterKey, info="mac", len=32)
  Uint8List stretchMasterKey(Uint8List masterKey) {
    final encKey = _hkdfExpand(masterKey, utf8.encode('enc'), 32);
    final macKey = _hkdfExpand(masterKey, utf8.encode('mac'), 32);
    return Uint8List.fromList([...encKey, ...macKey]);
  }

  /// Derive masterPasswordHash for server authentication.
  /// PBKDF2-SHA256(password=masterKey, salt=masterPassword, iterations=1)
  /// Returns raw 32 bytes (caller base64-encodes for API).
  Future<Uint8List> deriveMasterPasswordHash(
    Uint8List masterKey,
    String masterPassword,
  ) async {
    return _pbkdf2Sha256(
      masterKey,
      Uint8List.fromList(utf8.encode(masterPassword)),
      1,
      32,
    );
  }

  // ──────────────────────────────────────────────
  // Symmetric Encryption / Decryption
  // ──────────────────────────────────────────────

  /// Decrypt protectedSymmetricKey (CipherString type 2) → userKey (64 bytes).
  ///
  /// 1. Verify HMAC-SHA256(iv || ciphertext, macKey) == mac
  /// 2. AES-256-CBC decrypt with PKCS7 padding
  Uint8List decryptUserKey(
    CipherString protectedKey,
    Uint8List stretchedMasterKey,
  ) {
    if (protectedKey.encType != EncryptionType.aesCbc256_HmacSha256_B64) {
      throw ArgumentError(
        'Expected type 2 (AES-256-CBC-HMAC), got ${protectedKey.encType}',
      );
    }

    final encKey = Uint8List.sublistView(stretchedMasterKey, 0, 32);
    final macKey = Uint8List.sublistView(stretchedMasterKey, 32, 64);

    // Verify MAC
    if (protectedKey.mac != null) {
      final macData = Uint8List.fromList([
        ...protectedKey.iv!,
        ...protectedKey.ciphertext,
      ]);
      final expectedMac = _hmacSha256(macKey, macData);
      if (!_constantTimeEquals(expectedMac, protectedKey.mac!)) {
        throw StateError('MAC verification failed');
      }
    }

    return _aesCbcDecrypt(encKey, protectedKey.iv!, protectedKey.ciphertext);
  }

  /// Encrypt plaintext with a symmetric key using AES-256-CBC + HMAC-SHA256.
  /// Returns CipherString type 2.
  CipherString encryptSymmetric(Uint8List plaintext, Uint8List key) {
    assert(key.length == 64, 'Key must be 64 bytes (32 enc + 32 mac)');
    final encKey = Uint8List.sublistView(key, 0, 32);
    final macKey = Uint8List.sublistView(key, 32, 64);

    final iv = _randomBytes(16);
    final ciphertext = _aesCbcEncrypt(encKey, iv, plaintext);
    final macData = Uint8List.fromList([...iv, ...ciphertext]);
    final mac = _hmacSha256(macKey, macData);

    return CipherString(
      encType: EncryptionType.aesCbc256_HmacSha256_B64,
      iv: iv,
      ciphertext: ciphertext,
      mac: mac,
    );
  }

  /// Decrypt CipherString type 2 with a 64-byte symmetric key.
  Uint8List decryptSymmetric(CipherString cs, Uint8List key) {
    assert(key.length == 64);
    final encKey = Uint8List.sublistView(key, 0, 32);
    final macKey = Uint8List.sublistView(key, 32, 64);

    if (cs.mac != null) {
      final macData = Uint8List.fromList([...cs.iv!, ...cs.ciphertext]);
      final expectedMac = _hmacSha256(macKey, macData);
      if (!_constantTimeEquals(expectedMac, cs.mac!)) {
        throw StateError('MAC verification failed');
      }
    }

    return _aesCbcDecrypt(encKey, cs.iv!, cs.ciphertext);
  }

  // ──────────────────────────────────────────────
  // RSA-OAEP (Auth Request Approval)
  // ──────────────────────────────────────────────

  /// Encrypt userKey with the requesting device's RSA public key.
  /// Uses RSA-2048 OAEP with SHA-1 (Bitwarden EncryptionType 4).
  /// Returns CipherString "4.{base64(ciphertext)}".
  String encryptUserKeyForApproval(Uint8List userKey, String publicKeyBase64) {
    final publicKeyBytes = base64Decode(publicKeyBase64);
    final rsaPublicKey = _parseSpkiPublicKey(publicKeyBytes);

    final cipher = OAEPEncoding.withSHA1(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(rsaPublicKey));

    final encrypted = cipher.process(userKey);
    return '4.${base64Encode(encrypted)}';
  }

  // ──────────────────────────────────────────────
  // Fingerprint Phrase
  // ──────────────────────────────────────────────

  /// Generate fingerprint phrase for visual verification of an auth request.
  ///
  /// Algorithm:
  ///   1. keyHash = SHA-256(publicKeyBytes)
  ///   2. For i in 0..4: take 4 bytes from HKDF-Expand(keyHash, email+i)
  ///      → convert to uint32 → mod 7776 → EFF wordlist word
  ///   3. Join with "-"
  String generateFingerprintPhrase(
    String publicKeyBase64,
    String email,
    List<String> wordlist,
  ) {
    final publicKeyBytes = base64Decode(publicKeyBase64);
    final keyHash = _sha256(publicKeyBytes);

    final words = <String>[];
    for (var i = 0; i < 5; i++) {
      final info = utf8.encode('${email.toLowerCase()}$i');
      final derived = _hkdfExpand(keyHash, Uint8List.fromList(info), 4);
      final index =
          ByteData.sublistView(derived).getUint32(0, Endian.big) % wordlist.length;
      words.add(wordlist[index]);
    }
    return words.join('-');
  }

  // ──────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────

  Uint8List _sha256(Uint8List data) {
    final digest = SHA256Digest();
    return digest.process(data);
  }

  Uint8List _hmacSha256(Uint8List key, Uint8List data) {
    final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(key));
    return hmac.process(data);
  }

  Uint8List _pbkdf2Sha256(
    Uint8List password,
    Uint8List salt,
    int iterations,
    int keyLength,
  ) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, keyLength));
    return derivator.process(password);
  }

  /// HKDF-Expand only (no Extract step).
  /// PRK is used directly as the HMAC key.
  Uint8List _hkdfExpand(Uint8List prk, Uint8List info, int length) {
    final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(prk));
    const hashLen = 32; // SHA-256 output
    final n = (length + hashLen - 1) ~/ hashLen;
    final result = BytesBuilder();
    var prev = Uint8List(0);

    for (var i = 1; i <= n; i++) {
      hmac.reset();
      final input = Uint8List.fromList([...prev, ...info, i]);
      prev = hmac.process(input);
      result.add(prev);
    }

    return Uint8List.sublistView(result.toBytes(), 0, length);
  }

  Uint8List _aesCbcDecrypt(Uint8List key, Uint8List iv, Uint8List ciphertext) {
    final params = ParametersWithIV(KeyParameter(key), iv);
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(false, PaddedBlockCipherParameters(params, null));
    return cipher.process(ciphertext);
  }

  Uint8List _aesCbcEncrypt(Uint8List key, Uint8List iv, Uint8List plaintext) {
    final params = ParametersWithIV(KeyParameter(key), iv);
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(true, PaddedBlockCipherParameters(params, null));
    return cipher.process(plaintext);
  }

  Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }

  /// Parse SPKI DER-encoded RSA public key.
  RSAPublicKey _parseSpkiPublicKey(Uint8List bytes) {
    final parser = ASN1Parser(bytes);
    final topSequence = parser.nextObject() as ASN1Sequence;
    final bitString = topSequence.elements![1] as ASN1BitString;
    // Skip the unused-bits byte (first byte of bit string value)
    final keyBytes = Uint8List.sublistView(bitString.valueBytes!, 1);

    final keyParser = ASN1Parser(keyBytes);
    final keySequence = keyParser.nextObject() as ASN1Sequence;
    final modulus = (keySequence.elements![0] as ASN1Integer).integer!;
    final exponent = (keySequence.elements![1] as ASN1Integer).integer!;

    return RSAPublicKey(modulus, exponent);
  }

  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
