import 'dart:io';

import 'package:dio/dio.dart';

import '../l10n/app_localizations.dart';

/// Formats errors into user-friendly localized messages.
///
/// Handles DioException (network/HTTP errors), crypto errors,
/// and common runtime exceptions.
String formatError(Object e, AppLocalizations l) {
  if (e is DioException) {
    return _formatDioError(e, l);
  }
  if (e is SocketException) {
    return l.errorCannotConnect;
  }
  final msg = e.toString();
  if (msg.contains('MAC verification')) return l.errorInvalidMasterPassword;
  if (msg.contains('FormatException')) return l.errorInvalidServerResponse;
  if (msg.contains('RangeError') || msg.contains("type 'Null'")) {
    return l.errorUnexpectedFormat;
  }
  if (msg.contains('Biometric authentication failed')) {
    return l.errorBiometricFailed;
  }
  if (msg.contains('Setup not completed')) {
    return l.errorSessionExpired;
  }
  if (msg.contains('UserCancelled') || msg.contains('PasscodeNotSet')) {
    return l.errorBiometricFailed;
  }
  return msg.replaceAll('Exception: ', '');
}

String _formatDioError(DioException e, AppLocalizations l) {
  // If we got an HTTP response, always parse the body first —
  // this handles both raw DioExceptions and re-thrown ones from our API layer.
  if (e.response != null) {
    return _formatHttpError(e, l);
  }

  // Custom message set by our API layer (no response attached)
  if (e.message != null &&
      e.message!.isNotEmpty &&
      !_isDefaultDioMessage(e.message!)) {
    return e.message!;
  }

  // Network-level errors (no response from server)
  return _formatNetworkError(e, l);
}

/// Default Dio messages that should never be shown to the user.
bool _isDefaultDioMessage(String msg) {
  return msg.startsWith('The ') ||
      msg.startsWith('This exception') ||
      msg.contains('RequestOptions.validateStatus');
}

String _formatHttpError(DioException e, AppLocalizations l) {
  final status = e.response!.statusCode;
  final data = e.response!.data;

  if (data is Map) {
    final desc = data['error_description'] ??
        data['ErrorModel']?['Message'] ??
        data['message'] ??
        data['error'];
    if (desc != null && desc.toString().isNotEmpty) {
      final descStr = desc.toString();
      if (descStr.contains('invalid_grant') ||
          descStr.contains('invalid grant')) {
        return l.errorInvalidCredentials;
      }
      if (descStr.contains('Two-factor') ||
          descStr.contains('two factor') ||
          descStr.contains('Two Factor')) {
        return l.errorInvalidTwoFactorCode;
      }
      // Don't show raw technical strings to users
      if (_isTechnicalMessage(descStr)) {
        return _fallbackForStatus(status, l);
      }
      return descStr;
    }
  }

  return _fallbackForStatus(status, l);
}

/// Check if a server error message is too technical / ugly for users.
bool _isTechnicalMessage(String msg) {
  final lower = msg.toLowerCase();
  return lower.contains('exception') ||
      lower.contains('stacktrace') ||
      lower.contains('at line') ||
      lower.contains('null reference') ||
      msg.length > 200;
}

String _fallbackForStatus(int? status, AppLocalizations l) {
  if (status == null) return l.errorCannotConnect;
  if (status == 400) return l.errorInvalidRequest;
  if (status == 401) return l.errorSessionExpired;
  if (status == 403) return l.errorAccessDenied;
  if (status == 404) return l.errorEndpointNotFound;
  if (status == 429) return l.errorTooManyAttempts;
  if (status >= 500) return l.errorServerRetry(status);
  return l.errorServer(status);
}

String _formatNetworkError(DioException e, AppLocalizations l) {
  final msg = e.message ?? '';
  final errorStr = e.error?.toString() ?? '';
  final combined = '$msg $errorStr';

  // DNS resolution failure
  if (combined.contains('resolve host') ||
      combined.contains('getaddrinfo') ||
      combined.contains('Failed host lookup')) {
    return l.errorCannotResolve;
  }

  // Connection timeout
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      combined.contains('timed out')) {
    return l.errorConnectionTimeout;
  }

  // Connection refused / unreachable
  if (e.type == DioExceptionType.connectionError ||
      combined.contains('SocketException') ||
      combined.contains('Connection refused') ||
      combined.contains('Connection reset') ||
      combined.contains('Network is unreachable') ||
      combined.contains('No route to host') ||
      combined.contains('Software caused connection abort')) {
    return l.errorCannotConnect;
  }

  // SSL/TLS errors
  if (combined.contains('certificate') ||
      combined.contains('CERTIFICATE') ||
      combined.contains('HandshakeException') ||
      combined.contains('SSL') ||
      combined.contains('TLS')) {
    return l.errorSslCertificate;
  }

  // Request cancelled
  if (e.type == DioExceptionType.cancel) {
    return l.errorRequestCancelled;
  }

  // Fallback: if everything else, show a generic connection error
  // rather than the raw DioException dump
  return l.errorCannotConnect;
}

/// Returns true if the error represents a network/connectivity issue
/// (as opposed to a server-side or app-level error).
bool isNetworkError(Object e) {
  if (e is SocketException) return true;
  if (e is DioException) {
    if (e.response != null) {
      // Got a response from the server — not a network issue
      return false;
    }
    // No response: connection error, timeout, DNS, etc.
    return true;
  }
  final msg = e.toString();
  return msg.contains('SocketException') ||
      msg.contains('Connection refused') ||
      msg.contains('Failed host lookup') ||
      msg.contains('Network is unreachable');
}

/// Returns true if the error indicates the session/token has expired
/// and the user must re-authenticate.
bool isAuthError(Object e) {
  if (e is DioException && e.response?.statusCode == 401) return true;
  if (e.toString().contains('Setup not completed')) return true;
  return false;
}
