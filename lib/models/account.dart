import 'dart:convert';

/// XBoard/V2Board 面板账号的本地元数据。
///
/// 只保存非敏感字段：登录邮箱（可脱敏展示）、面板 origin、
/// 订阅 Profile 关联 id、最后同步时间等。密码不在此对象中保存，
/// 认证 token 也不在此对象中保存（见 [AuthSession] 与 CredentialStore）。
///
/// 与 `Traffic`/`TrafficValue` 一致，采用手写 JSON 序列化，
/// 不依赖 freezed/build_runner，避免引入代码生成步骤。
class Account {
  /// 稳定账号 id，用于关联 Profile 与 CredentialStore 中的会话。
  final String id;

  /// 面板首页 origin，如 `https://kt.114432.xyz`。
  final String origin;

  /// XBoard API base URL（可能不同于首页 origin，如 pair 域名）。
  final String apiBaseUrl;

  /// 脱敏邮箱（如 `a***e@example.com`），仅用于展示。
  final String email;

  /// 显示名（默认取邮箱前缀或面板名）。
  final String label;

  /// 关联的 KitonyBox Profile id，登录后创建/更新订阅时写入。
  final String? profileId;

  /// 上次成功同步订阅的时间。
  final DateTime? lastSyncTime;

  const Account({
    required this.id,
    required this.origin,
    required this.apiBaseUrl,
    required this.email,
    required this.label,
    this.profileId,
    this.lastSyncTime,
  });

  /// 脱敏邮箱：`a***e@example.com`，用于本地持久化与 UI 展示。
  static String maskEmail(String email) {
    final atIndex = email.indexOf('@');
    if (atIndex <= 0) return email;
    final name = email.substring(0, atIndex);
    final domain = email.substring(atIndex);
    if (name.length <= 2) {
      return '${name[0]}***$domain';
    }
    return '${name[0]}${'*' * (name.length - 2)}${name[name.length - 1]}$domain';
  }

  Account copyWith({
    String? id,
    String? origin,
    String? apiBaseUrl,
    String? email,
    String? label,
    String? profileId,
    DateTime? lastSyncTime,
    bool clearProfileId = false,
    bool clearLastSyncTime = false,
  }) {
    return Account(
      id: id ?? this.id,
      origin: origin ?? this.origin,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      email: email ?? this.email,
      label: label ?? this.label,
      profileId: clearProfileId ? null : profileId ?? this.profileId,
      lastSyncTime: clearLastSyncTime
          ? null
          : lastSyncTime ?? this.lastSyncTime,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'origin': origin,
      'apiBaseUrl': apiBaseUrl,
      'email': email,
      'label': label,
      if (profileId != null) 'profileId': profileId,
      if (lastSyncTime != null) 'lastSyncTime': lastSyncTime!.toIso8601String(),
    };
  }

  factory Account.fromJson(Map<String, Object?> json) {
    final lastSyncTime = json['lastSyncTime'];
    return Account(
      id: json['id'] as String? ?? '',
      origin: json['origin'] as String? ?? '',
      apiBaseUrl: json['apiBaseUrl'] as String? ?? '',
      email: json['email'] as String? ?? '',
      label: json['label'] as String? ?? '',
      profileId: json['profileId'] as String?,
      lastSyncTime: lastSyncTime is String
          ? DateTime.tryParse(lastSyncTime)
          : null,
    );
  }

  String encode() => jsonEncode(toJson());

  static Account? decode(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final map = jsonDecode(value);
      if (map is! Map) return null;
      return Account.fromJson(map.cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }
}
