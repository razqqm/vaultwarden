/// Bitwarden CipherString encryption type prefix.
/// Format: "{type}.{iv}|{ciphertext}|{mac}"
enum EncryptionType {
  aesCbc256_B64(0),
  aesCbc128_HmacSha256_B64(1),
  aesCbc256_HmacSha256_B64(2),
  rsa2048_OaepSha256_B64(3),
  rsa2048_OaepSha1_B64(4),
  rsa2048_OaepSha256_HmacSha256_B64(5),
  rsa2048_OaepSha1_HmacSha256_B64(6);

  const EncryptionType(this.value);
  final int value;

  static EncryptionType fromValue(int v) =>
      EncryptionType.values.firstWhere((e) => e.value == v);

  bool get hasIv =>
      this == aesCbc256_B64 ||
      this == aesCbc128_HmacSha256_B64 ||
      this == aesCbc256_HmacSha256_B64;

  bool get hasMac =>
      this == aesCbc128_HmacSha256_B64 ||
      this == aesCbc256_HmacSha256_B64 ||
      this == rsa2048_OaepSha256_HmacSha256_B64 ||
      this == rsa2048_OaepSha1_HmacSha256_B64;
}
