/// KDF parameters returned by POST /identity/accounts/prelogin.
class KdfParams {
  /// 0 = PBKDF2-SHA256, 1 = Argon2id
  final int kdfType;
  final int iterations;

  /// KiB, Argon2id only (default: 65536 = 64 MiB)
  final int? memory;

  /// Argon2id only (default: 4)
  final int? parallelism;

  const KdfParams({
    required this.kdfType,
    required this.iterations,
    this.memory,
    this.parallelism,
  });

  factory KdfParams.fromJson(Map<String, dynamic> json) => KdfParams(
        kdfType: (json['kdf'] ?? json['Kdf']) as int,
        iterations: (json['kdfIterations'] ?? json['KdfIterations']) as int,
        memory: (json['kdfMemory'] ?? json['KdfMemory']) as int?,
        parallelism: (json['kdfParallelism'] ?? json['KdfParallelism']) as int?,
      );

  bool get isArgon2id => kdfType == 1;
  bool get isPbkdf2 => kdfType == 0;
}
