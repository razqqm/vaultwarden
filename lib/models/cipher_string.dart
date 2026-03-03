import 'dart:convert';
import 'dart:typed_data';

import 'encryption_type.dart';

/// Parses and encodes Bitwarden CipherString format.
///
/// Symmetric (type 0,1,2): "encType.{base64_iv}|{base64_ct}|{base64_mac}"
/// Asymmetric (type 3,4,5,6): "encType.{base64_ct}" or "encType.{base64_ct}|{base64_mac}"
class CipherString {
  final EncryptionType encType;
  final Uint8List? iv;
  final Uint8List ciphertext;
  final Uint8List? mac;

  CipherString({
    required this.encType,
    this.iv,
    required this.ciphertext,
    this.mac,
  });

  factory CipherString.parse(String encoded) {
    final dotIndex = encoded.indexOf('.');
    if (dotIndex == -1) {
      throw FormatException('Invalid CipherString: no type prefix', encoded);
    }

    final encType = EncryptionType.fromValue(int.parse(encoded.substring(0, dotIndex)));
    final rest = encoded.substring(dotIndex + 1);
    final parts = rest.split('|');

    if (encType.hasIv) {
      // Symmetric: iv|ct|mac or iv|ct
      if (parts.length < 2) {
        throw FormatException('Invalid symmetric CipherString', encoded);
      }
      return CipherString(
        encType: encType,
        iv: base64Decode(parts[0]),
        ciphertext: base64Decode(parts[1]),
        mac: parts.length > 2 && parts[2].isNotEmpty ? base64Decode(parts[2]) : null,
      );
    } else {
      // Asymmetric: ct or ct|mac
      return CipherString(
        encType: encType,
        ciphertext: base64Decode(parts[0]),
        mac: parts.length > 1 && parts[1].isNotEmpty ? base64Decode(parts[1]) : null,
      );
    }
  }

  String encode() {
    final buf = StringBuffer('${encType.value}.');
    if (encType.hasIv && iv != null) {
      buf.write(base64Encode(iv!));
      buf.write('|');
    }
    buf.write(base64Encode(ciphertext));
    if (encType.hasMac && mac != null) {
      buf.write('|');
      buf.write(base64Encode(mac!));
    }
    return buf.toString();
  }

  @override
  String toString() => encode();
}
