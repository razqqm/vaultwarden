import 'dart:io';

import 'package:dio/dio.dart';

import '../models/auth_request.dart';
import '../models/kdf_params.dart';
import '../models/user_session.dart';
import 'secure_storage_service.dart';

class VaultApiService {
  late final Dio _dio;
  final SecureStorageService _storage;
  UserSession? _session;

  VaultApiService(this._storage) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
      },
    ));
    _dio.interceptors.add(_tokenRefreshInterceptor());
  }

  void configure(String serverUrl, UserSession session) {
    _dio.options.baseUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
    _session = session;
  }

  // ── Identity Endpoints ──

  /// POST /identity/accounts/prelogin → KDF params
  Future<KdfParams> prelogin(String serverUrl, String email) async {
    final response = await _dio.post(
      '${_normalizeUrl(serverUrl)}/identity/accounts/prelogin',
      data: {'email': email},
    );
    return KdfParams.fromJson(response.data as Map<String, dynamic>);
  }

  /// POST /identity/connect/token (password grant)
  /// Returns raw response with access_token, refresh_token, Key, etc.
  /// Throws [TwoFactorRequiredException] if 2FA is needed.
  Future<Map<String, dynamic>> login({
    required String serverUrl,
    required String email,
    required String masterPasswordHashB64,
    required String deviceId,
    String? twoFactorToken,
    int? twoFactorProvider,
    bool twoFactorRemember = true,
  }) async {
    final deviceType = Platform.isIOS ? '1' : '0';
    final data = {
      'grant_type': 'password',
      'username': email,
      'password': masterPasswordHashB64,
      'scope': 'api offline_access',
      'client_id': 'mobile',
      'deviceType': deviceType,
      'deviceIdentifier': deviceId,
      'deviceName': 'Vault Approver',
    };

    if (twoFactorToken != null) {
      data['twoFactorToken'] = twoFactorToken;
      data['twoFactorProvider'] = '${twoFactorProvider ?? 0}';
      data['twoFactorRemember'] = twoFactorRemember ? '1' : '0';
    }

    try {
      final response = await _dio.post(
        '${_normalizeUrl(serverUrl)}/identity/connect/token',
        data: data,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response != null) {
        final body = e.response!.data;
        if (body is Map && _isTwoFactorResponse(body)) {
          throw TwoFactorRequiredException(
            availableProviders: _parseTwoFactorProviders(body),
          );
        }
        // Re-throw with a more descriptive message for other 400 errors
        if (e.response!.statusCode == 400 && body is Map) {
          final desc = body['error_description']
              ?? body['ErrorModel']?['Message']
              ?? body['message']
              ?? body['error'];
          if (desc != null && desc.toString().isNotEmpty) {
            throw DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              message: desc.toString(),
            );
          }
        }
      }
      rethrow;
    }
  }

  /// Detect whether a 400 response body signals 2FA requirement.
  bool _isTwoFactorResponse(Map body) {
    // Vaultwarden/Bitwarden can signal 2FA in multiple ways:
    if (body.containsKey('TwoFactorProviders') ||
        body.containsKey('twoFactorProviders') ||
        body.containsKey('TwoFactorProviders2')) {
      return true;
    }
    final desc = (body['error_description'] ?? '').toString().toLowerCase();
    return desc.contains('two factor') || desc.contains('two-factor');
  }

  /// Parse provider list from various Vaultwarden/Bitwarden response formats.
  List<int> _parseTwoFactorProviders(Map body) {
    // Try TwoFactorProviders (List<int>) first
    final list = body['TwoFactorProviders'] ?? body['twoFactorProviders'];
    if (list is List) {
      return list.map((e) => e is int ? e : int.tryParse('$e') ?? 0).toList();
    }
    // TwoFactorProviders2 is Map<String, Object?> — keys are provider type IDs
    final map = body['TwoFactorProviders2'] ?? body['twoFactorProviders2'];
    if (map is Map) {
      return map.keys.map((k) => int.tryParse('$k') ?? 0).toList();
    }
    // Fallback: TOTP (0) assumed
    return <int>[0];
  }

  /// POST /identity/connect/token (refresh grant)
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final response = await _dio.post(
      '${_dio.options.baseUrl}/identity/connect/token',
      data: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': 'mobile',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    return response.data as Map<String, dynamic>;
  }

  // ── Auth Request Endpoints ──

  /// GET /api/auth-requests → pending auth requests
  Future<List<AuthRequest>> getPendingRequests() async {
    final response = await _dio.get(
      '/api/auth-requests',
      options: Options(headers: _authHeaders()),
    );
    final data = response.data as Map<String, dynamic>;
    final list = (data['data'] ?? data['Data']) as List;
    return list
        .map((e) => AuthRequest.fromJson(e as Map<String, dynamic>))
        .where((r) => !r.isExpired)
        .toList();
  }

  /// PUT /api/auth-requests/{uuid} → approve or deny
  Future<void> respondToAuthRequest({
    required String requestId,
    required bool approved,
    String? encryptedKey,
    required String deviceId,
  }) async {
    await _dio.put(
      '/api/auth-requests/$requestId',
      data: {
        'key': encryptedKey ?? '',
        'masterPasswordHash': null,
        'deviceIdentifier': deviceId,
        'requestApproved': approved,
      },
      options: Options(headers: _authHeaders()),
    );
  }

  // ── Helpers ──

  Map<String, String> _authHeaders() {
    if (_session == null) throw StateError('Not authenticated');
    return {'Authorization': 'Bearer ${_session!.accessToken}'};
  }

  String _normalizeUrl(String url) => url.replaceAll(RegExp(r'/+$'), '');

  Interceptor _tokenRefreshInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Skip token refresh for identity endpoints
        if (options.path.contains('/identity/')) {
          return handler.next(options);
        }
        if (_session != null && _session!.isAccessTokenExpired) {
          try {
            final result = await refreshToken(_session!.refreshToken);
            final expiresIn = result['expires_in'] as int? ?? 3600;
            _session = _session!.copyWith(
              accessToken: result['access_token'] as String,
              refreshToken:
                  result['refresh_token'] as String? ?? _session!.refreshToken,
              accessTokenExpiry:
                  DateTime.now().add(Duration(seconds: expiresIn)),
            );
            await _storage.saveSession(_session!);
            options.headers['Authorization'] = 'Bearer ${_session!.accessToken}';
          } catch (e) {
            // Refresh failed — will get 401 and caller handles re-auth
          }
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 && _session != null) {
          try {
            final result = await refreshToken(_session!.refreshToken);
            final expiresIn = result['expires_in'] as int? ?? 3600;
            _session = _session!.copyWith(
              accessToken: result['access_token'] as String,
              refreshToken:
                  result['refresh_token'] as String? ?? _session!.refreshToken,
              accessTokenExpiry:
                  DateTime.now().add(Duration(seconds: expiresIn)),
            );
            await _storage.saveSession(_session!);

            // Retry original request
            final opts = error.requestOptions;
            opts.headers['Authorization'] = 'Bearer ${_session!.accessToken}';
            final response = await _dio.fetch(opts);
            return handler.resolve(response);
          } catch (_) {
            return handler.next(error);
          }
        }
        return handler.next(error);
      },
    );
  }

  /// Update session reference (e.g., after token refresh from outside).
  void updateSession(UserSession session) {
    _session = session;
  }
}

/// Thrown when the server requires two-factor authentication.
class TwoFactorRequiredException implements Exception {
  final List<int> availableProviders;

  const TwoFactorRequiredException({required this.availableProviders});

  /// 0 = Authenticator (TOTP), 1 = Email, 2 = Duo, etc.
  bool get hasTotp => availableProviders.contains(0);
  bool get hasEmail => availableProviders.contains(1);

  @override
  String toString() => 'TwoFactorRequiredException(providers: $availableProviders)';
}
