import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_approver/models/cipher_string.dart';
import 'package:vault_approver/models/encryption_type.dart';

void main() {
  group('CipherString', () {
    group('parse', () {
      test('parses type 2 (AES-256-CBC-HMAC) correctly', () {
        final iv = base64Encode(Uint8List(16)); // 16 zero bytes
        final ct = base64Encode(Uint8List(32)); // 32 zero bytes
        final mac = base64Encode(Uint8List(32)); // 32 zero bytes
        final input = '2.$iv|$ct|$mac';

        final cs = CipherString.parse(input);

        expect(cs.encType, EncryptionType.aesCbc256_HmacSha256_B64);
        expect(cs.iv!.length, 16);
        expect(cs.ciphertext.length, 32);
        expect(cs.mac!.length, 32);
      });

      test('parses type 4 (RSA-OAEP-SHA1) correctly', () {
        final ct = base64Encode(Uint8List(256));
        final input = '4.$ct';

        final cs = CipherString.parse(input);

        expect(cs.encType, EncryptionType.rsa2048_OaepSha1_B64);
        expect(cs.iv, isNull);
        expect(cs.ciphertext.length, 256);
        expect(cs.mac, isNull);
      });

      test('parses type 0 (AES-256-CBC no MAC) correctly', () {
        final iv = base64Encode(Uint8List(16));
        final ct = base64Encode(Uint8List(48));
        final input = '0.$iv|$ct';

        final cs = CipherString.parse(input);

        expect(cs.encType, EncryptionType.aesCbc256_B64);
        expect(cs.iv!.length, 16);
        expect(cs.ciphertext.length, 48);
        expect(cs.mac, isNull);
      });

      test('throws on missing type prefix', () {
        expect(
          () => CipherString.parse('noprefix'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws on invalid type number', () {
        expect(
          () => CipherString.parse('99.abc'),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('encode', () {
      test('roundtrips type 2 correctly', () {
        final iv = Uint8List.fromList(List.generate(16, (i) => i));
        final ct = Uint8List.fromList(List.generate(32, (i) => i + 100));
        final mac = Uint8List.fromList(List.generate(32, (i) => i + 200));

        final cs = CipherString(
          encType: EncryptionType.aesCbc256_HmacSha256_B64,
          iv: iv,
          ciphertext: ct,
          mac: mac,
        );

        final encoded = cs.encode();
        final reparsed = CipherString.parse(encoded);

        expect(reparsed.encType, cs.encType);
        expect(reparsed.iv, cs.iv);
        expect(reparsed.ciphertext, cs.ciphertext);
        expect(reparsed.mac, cs.mac);
      });

      test('roundtrips type 4 correctly', () {
        final ct = Uint8List.fromList(List.generate(256, (i) => i % 256));

        final cs = CipherString(
          encType: EncryptionType.rsa2048_OaepSha1_B64,
          ciphertext: ct,
        );

        final encoded = cs.encode();
        expect(encoded.startsWith('4.'), isTrue);

        final reparsed = CipherString.parse(encoded);
        expect(reparsed.ciphertext, cs.ciphertext);
      });
    });
  });
}
