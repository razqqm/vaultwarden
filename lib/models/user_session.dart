/// Persisted session state (tokens + server info).
/// The actual UserKey is NOT here — it's in secure storage separately.
class UserSession {
  final String email;
  final String serverUrl;
  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiry;

  const UserSession({
    required this.email,
    required this.serverUrl,
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiry,
  });

  bool get isAccessTokenExpired =>
      DateTime.now().isAfter(accessTokenExpiry.subtract(const Duration(minutes: 1)));

  Map<String, dynamic> toJson() => {
        'email': email,
        'serverUrl': serverUrl,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'accessTokenExpiry': accessTokenExpiry.toIso8601String(),
      };

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
        email: json['email'] as String,
        serverUrl: json['serverUrl'] as String,
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        accessTokenExpiry: DateTime.parse(json['accessTokenExpiry'] as String),
      );

  UserSession copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? accessTokenExpiry,
  }) =>
      UserSession(
        email: email,
        serverUrl: serverUrl,
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        accessTokenExpiry: accessTokenExpiry ?? this.accessTokenExpiry,
      );
}
