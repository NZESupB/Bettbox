import 'dart:convert';

import 'package:kitony_box/models/account.dart';
import 'package:kitony_box/models/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Account 元数据', () {
    test('邮箱脱敏：a***e@example.com', () {
      expect(Account.maskEmail('alice@example.com'), 'a***e@example.com');
    });

    test('短邮箱脱敏：仅保留首字符', () {
      expect(Account.maskEmail('ab@x.com'), 'a***@x.com');
    });

    test('JSON 往返保持字段完整', () {
      final account = Account(
        id: 'xboard_default',
        origin: 'https://kt.114432.xyz',
        apiBaseUrl: 'https://pair_1.114432.xyz/api/v1',
        email: 'alice@example.com',
        label: 'alice',
        profileId: 'p123',
        lastSyncTime: DateTime.fromMillisecondsSinceEpoch(
          1700000000000,
          isUtc: true,
        ),
      );
      final restored = Account.decode(account.encode())!;
      expect(restored.id, account.id);
      expect(restored.origin, account.origin);
      expect(restored.email, account.email);
      expect(restored.profileId, 'p123');
      expect(restored.lastSyncTime!.millisecondsSinceEpoch, 1700000000000);
    });

    test('copyWith 支持清除关联字段', () {
      final account = Account(
        id: 'xboard_default',
        origin: '',
        apiBaseUrl: '',
        email: 'a@b.com',
        label: 'a',
        profileId: 'p123',
        lastSyncTime: DateTime.now(),
      );
      final cleared = account.copyWith(
        clearProfileId: true,
        clearLastSyncTime: true,
      );
      expect(cleared.profileId, isNull);
      expect(cleared.lastSyncTime, isNull);
    });
  });

  group('AuthSession', () {
    test('凭据掩码不泄露完整凭据', () {
      final session = AuthSession(
        authorization: 'abcdefgh12345678',
        origin: 'https://kt.114432.xyz',
        savedAt: DateTime.now(),
      );
      expect(session.authorizationMasked, 'abcd...5678');
      expect(session.toString(), isNot(contains('abcdefgh12345678')));
    });

    test('过期判断', () {
      final expired = AuthSession(
        authorization: 't',
        origin: '',
        savedAt: DateTime.now().subtract(const Duration(days: 2)),
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(expired.hasExpired, isTrue);

      final notExpired = AuthSession(
        authorization: 't',
        origin: '',
        savedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      expect(notExpired.hasExpired, isFalse);

      final unknown = AuthSession(
        authorization: 't',
        origin: '',
        savedAt: DateTime.now(),
      );
      expect(unknown.hasExpired, isFalse);
    });

    test('JSON 往返与损坏容错', () {
      final session = AuthSession(
        authorization: 'Bearer token-abc',
        origin: 'https://kt.114432.xyz',
        savedAt: DateTime.fromMillisecondsSinceEpoch(
          1700000000000,
          isUtc: true,
        ),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          1800000000000,
          isUtc: true,
        ),
      );
      final restored = AuthSession.decode(session.encode())!;
      expect(restored.authorization, 'Bearer token-abc');
      expect(restored.savedAt.millisecondsSinceEpoch, 1700000000000);

      // 损坏数据返回 null，不崩溃。
      expect(AuthSession.decode('not-json'), isNull);
      expect(AuthSession.decode(''), isNull);
    });

    test('encode/decode 使用标准 JSON', () {
      final session = AuthSession(
        authorization: 't',
        origin: 'https://kt.114432.xyz',
        savedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      final decoded = jsonDecode(session.encode()) as Map<String, dynamic>;
      expect(decoded['authorization'], 't');
      expect(decoded['origin'], 'https://kt.114432.xyz');
    });
  });
}
