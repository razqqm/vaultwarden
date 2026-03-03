/// A pending "Login with device" auth request.
class AuthRequest {
  final String id;
  final String publicKey;
  final String requestDeviceType;
  final String requestIpAddress;
  final DateTime creationDate;
  final String? fingerprint;

  const AuthRequest({
    required this.id,
    required this.publicKey,
    required this.requestDeviceType,
    required this.requestIpAddress,
    required this.creationDate,
    this.fingerprint,
  });

  factory AuthRequest.fromJson(Map<String, dynamic> json) => AuthRequest(
        id: json['id'] as String? ?? json['Id'] as String,
        publicKey: json['publicKey'] as String? ?? json['PublicKey'] as String,
        requestDeviceType: json['requestDeviceType'] as String? ??
            json['RequestDeviceType'] as String? ??
            'Unknown',
        requestIpAddress: json['requestIpAddress'] as String? ??
            json['RequestIpAddress'] as String? ??
            '',
        creationDate: DateTime.parse(
          json['creationDate'] as String? ??
              json['CreationDate'] as String? ??
              DateTime.now().toIso8601String(),
        ),
      );

  AuthRequest copyWith({String? fingerprint}) => AuthRequest(
        id: id,
        publicKey: publicKey,
        requestDeviceType: requestDeviceType,
        requestIpAddress: requestIpAddress,
        creationDate: creationDate,
        fingerprint: fingerprint ?? this.fingerprint,
      );

  /// Minutes remaining before this request expires (15 min TTL).
  int get minutesRemaining {
    final elapsed = DateTime.now().difference(creationDate).inMinutes;
    return (15 - elapsed).clamp(0, 15);
  }

  bool get isExpired => minutesRemaining <= 0;
}
