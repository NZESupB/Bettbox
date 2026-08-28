import 'dart:convert';

/// XBoard 认证会话的运行时与过期信息。
///
/// 该对象在内存中保存完整认证凭据，但**绝不**随普通配置 JSON
/// 落盘；持久化由 CredentialStore 以混淆形式单独保存。
/// [toString] 不输出敏感字段，避免日志/异常泄漏。
class AuthSession {
  /// 完整的 `Authorization` 头值（面板返回的 `auth_data`，新版已含
  /// `Bearer ` 前缀）。使用时原样注入请求头，不再拼接前缀。
  final String authorization;

  /// 面板 origin。
  final String origin;

  /// 会话签发/保存时间。
  final DateTime savedAt;

  /// 服务端声明的过期时间（可选；未知时为 null，不主动猜测）。
  final DateTime? expiresAt;

  const AuthSession({
    required this.authorization,
    required this.origin,
    required this.savedAt,
    this.expiresAt,
  });

  bool get hasExpired {
    final expiresAt = this.expiresAt;
    return expiresAt != null && DateTime.now().isAfter(expiresAt);
  }

  /// 内存中使用后应及时清理；这里用不可逆截断代替输出完整凭据。
  String get authorizationMasked {
    if (authorization.length <= 8) return '***';
    return '${authorization.substring(0, 4)}...'
        '${authorization.substring(authorization.length - 4)}';
  }

  AuthSession copyWith({
    String? authorization,
    String? origin,
    DateTime? savedAt,
    DateTime? expiresAt,
  }) {
    return AuthSession(
      authorization: authorization ?? this.authorization,
      origin: origin ?? this.origin,
      savedAt: savedAt ?? this.savedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'authorization': authorization,
      'origin': origin,
      'savedAt': savedAt.toIso8601String(),
      if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
    };
  }

  factory AuthSession.fromJson(Map<String, Object?> json) {
    final savedAt = json['savedAt'];
    final expiresAt = json['expiresAt'];
    return AuthSession(
      authorization: json['authorization'] as String? ?? '',
      origin: json['origin'] as String? ?? '',
      savedAt: savedAt is String
          ? DateTime.tryParse(savedAt) ?? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(0),
      expiresAt: expiresAt is String ? DateTime.tryParse(expiresAt) : null,
    );
  }

  String encode() => jsonEncode(toJson());

  static AuthSession? decode(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final map = jsonDecode(value);
      if (map is! Map) return null;
      final session = AuthSession.fromJson(map.cast<String, Object?>());
      if (session.authorization.isEmpty) return null;
      return session;
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() {
    return 'AuthSession(origin: $origin, authorization: $authorizationMasked)';
  }
}
