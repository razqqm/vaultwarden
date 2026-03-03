import 'package:flutter_test/flutter_test.dart';
import 'package:vault_approver/models/auth_request.dart';

void main() {
  group('AuthRequest', () {
    test('parses from JSON (camelCase)', () {
      final json = {
        'id': 'abc-123',
        'publicKey': 'dGVzdA==',
        'requestDeviceType': 'AndroidPhone',
        'requestIpAddress': '192.168.1.1',
        'creationDate': '2025-01-15T10:30:00.000Z',
      };

      final request = AuthRequest.fromJson(json);

      expect(request.id, 'abc-123');
      expect(request.publicKey, 'dGVzdA==');
      expect(request.requestDeviceType, 'AndroidPhone');
      expect(request.requestIpAddress, '192.168.1.1');
      expect(request.creationDate.year, 2025);
    });

    test('parses from JSON (PascalCase)', () {
      final json = {
        'Id': 'abc-123',
        'PublicKey': 'dGVzdA==',
        'RequestDeviceType': 'iOS',
        'RequestIpAddress': '10.0.0.1',
        'CreationDate': '2025-06-01T12:00:00.000Z',
      };

      final request = AuthRequest.fromJson(json);

      expect(request.id, 'abc-123');
      expect(request.publicKey, 'dGVzdA==');
      expect(request.requestDeviceType, 'iOS');
    });

    test('isExpired returns true for old requests', () {
      final request = AuthRequest(
        id: '1',
        publicKey: 'key',
        requestDeviceType: 'Web',
        requestIpAddress: '1.2.3.4',
        creationDate: DateTime.now().subtract(const Duration(minutes: 20)),
      );

      expect(request.isExpired, isTrue);
      expect(request.minutesRemaining, 0);
    });

    test('isExpired returns false for fresh requests', () {
      final request = AuthRequest(
        id: '1',
        publicKey: 'key',
        requestDeviceType: 'Web',
        requestIpAddress: '1.2.3.4',
        creationDate: DateTime.now().subtract(const Duration(minutes: 2)),
      );

      expect(request.isExpired, isFalse);
      expect(request.minutesRemaining, greaterThan(10));
    });

    test('copyWith updates fingerprint', () {
      final request = AuthRequest(
        id: '1',
        publicKey: 'key',
        requestDeviceType: 'Web',
        requestIpAddress: '1.2.3.4',
        creationDate: DateTime.now(),
      );

      expect(request.fingerprint, isNull);

      final updated = request.copyWith(fingerprint: 'alpha-beta-gamma-delta-epsilon');
      expect(updated.fingerprint, 'alpha-beta-gamma-delta-epsilon');
      expect(updated.id, '1');
    });
  });
}
