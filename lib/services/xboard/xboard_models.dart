/// XBoard/V2Board 面板 API 的数据传输对象。
///
/// 面板接口是外部不稳定依赖：所有字段均做类型容错，
/// 未知字段忽略，错误类型统一为 [XBoardException]。
library;

/// 统一业务响应外壳：`{status, message, data, error}`。
class XBoardResponse<T> {
  /// 业务成功与否。XBoard 的 HTTP 200 不代表业务成功，必须看此字段。
  final bool success;

  /// 面板返回的 message（可能为空字符串）。
  final String message;

  /// 解析后的 data；失败或 data 为空时为 null。
  final T? data;

  const XBoardResponse({
    required this.success,
    required this.message,
    this.data,
  });

  static XBoardResponse<Map<String, Object?>> fromMap(Object? body) {
    if (body is! Map) {
      return const XBoardResponse(success: false, message: 'invalid response');
    }
    final map = body.map((key, value) => MapEntry(key.toString(), value));
    final status = map['status'];
    final message = map['message'];
    final data = map['data'];
    final error = map['error'];

    // XBoard 常见 status 为 'success'/'fail'；部分变体可能缺失 status，
    // 此时若 data 为有效 Map 且无 error，视为成功。
    final hasData = data is Map && data.isNotEmpty;
    final bool success;
    if (status == 'success' || status == true || status == 1) {
      success = true;
    } else if (status == 'fail' ||
        status == 'error' ||
        status == false ||
        status == 0) {
      success = false;
    } else {
      success = hasData && error == null;
    }
    final errorMessage = switch (message) {
      String s when s.isNotEmpty => s,
      _ => switch (error) {
        String s when s.isNotEmpty => s,
        Map m => m['message']?.toString() ?? 'unknown error',
        _ => success ? '' : 'request failed',
      },
    };
    return XBoardResponse<Map<String, Object?>>(
      success: success,
      message: errorMessage,
      data: data is Map
          ? data.map((key, value) => MapEntry(key.toString(), value))
          : null,
    );
  }
}

/// XBoard 业务/网络错误。message 只含面板提示或脱敏后的错误摘要，
/// 绝不包含密码、完整 token 或订阅 URL。
class XBoardException implements Exception {
  final String message;

  const XBoardException(this.message);

  @override
  String toString() => message;
}

/// 认证失效（401/403 或业务未登录）。
class XBoardSessionExpiredException extends XBoardException {
  // ignore: use_super_parameters — 需要默认值，super 参数不支持。
  const XBoardSessionExpiredException([String message = 'session expired'])
    : super(message);
}

/// 网络/超时/TLS 错误。
class XBoardNetworkException extends XBoardException {
  const XBoardNetworkException(super.message);
}

/// 表单/参数校验错误。
class XBoardValidationException extends XBoardException {
  const XBoardValidationException(super.message);
}

/// 响应不是 JSON（例如 SPA fallback 返回 text/html）。
class XBoardParseException extends XBoardException {
  // ignore: use_super_parameters — 需要默认值，super 参数不支持。
  const XBoardParseException([String message = 'unexpected response'])
    : super(message);
}

/// 登录成功数据。
///
/// XBoard/V2Board 的 `POST /passport/auth/login` 返回两个**语义完全不同**的字段：
/// - `auth_data`：认证凭据，且已是完整的 `Authorization` 头值（新版 XBoard 走
///   Sanctum，形如 `Bearer <token>`；旧版 V2Board 为原始凭据串，其
///   `user` 中间件同样原样读取 header）。
/// - `token`：用户的**订阅** token（`$user->token`），只用于拼订阅 URL，
///   拿它做认证会被面板判为未登录（403）。
class XBoardLoginData {
  /// 完整的 `Authorization` 头值，直接注入请求头，不再额外拼前缀。
  final String authorization;

  /// 面板订阅 token；与认证无关。
  final String? subscribeToken;

  final bool isAdmin;

  const XBoardLoginData({
    required this.authorization,
    this.subscribeToken,
    this.isAdmin = false,
  });

  factory XBoardLoginData.fromData(Map<String, Object?> data) {
    final subscribeToken = data['token']?.toString();
    final authData = data['auth_data']?.toString();
    // 认证凭据只认 `auth_data`；仅当面板未返回它时，才退回订阅 token 并
    // 补齐 Bearer 前缀，兼容不返回 auth_data 的魔改面板。
    final authorization = authData != null && authData.isNotEmpty
        ? authData
        : (subscribeToken == null || subscribeToken.isEmpty
              ? ''
              : 'Bearer $subscribeToken');
    return XBoardLoginData(
      authorization: authorization,
      subscribeToken: subscribeToken?.isNotEmpty == true
          ? subscribeToken
          : null,
      isAdmin: data['is_admin'] == true,
    );
  }
}

/// `/user/info` 返回的用户信息。字段名兼容常见 XBoard/V2Board 变体。
class XBoardUserInfo {
  final String? email;
  final int id;
  final int isAdmin;

  /// 套餐名称（可能为空）。
  final String? planName;

  /// 到期时间戳（秒）。0 表示未设置。
  final int expireAt;

  /// 已用/总流量（字节）。
  final int usedTraffic;
  final int totalTraffic;

  /// 剩余流量（字节）。null 表示面板未返回（未知），-1 表示无限制。
  final int? remainingTraffic;

  const XBoardUserInfo({
    this.email,
    this.id = 0,
    this.isAdmin = 0,
    this.planName,
    this.expireAt = 0,
    this.usedTraffic = 0,
    this.totalTraffic = 0,
    this.remainingTraffic,
  });

  bool get hasUnlimitedTraffic => remainingTraffic == -1;

  factory XBoardUserInfo.fromData(Map<String, Object?> data) {
    int parseIntValue(Object? value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    final email = data['email']?.toString();
    final planName = data['plan'] is Map
        ? (data['plan'] as Map)['name']?.toString()
        : data['plan_name']?.toString();

    final usedTraffic = parseIntValue(data['u']) + parseIntValue(data['d']);
    final totalTraffic = parseIntValue(
      data['transfer_enable'] ?? data['totalTraffic'],
    );
    // remaining_traffic 缺失时视为未知（null）；面板显式返回 -1 才是无限制。
    final remainingValue = data['remaining_traffic'] ?? data['residue'];

    return XBoardUserInfo(
      email: email,
      id: parseIntValue(data['id']),
      isAdmin: parseIntValue(data['is_admin']),
      planName: planName,
      expireAt: parseIntValue(data['expired_at'] ?? data['expire_at']),
      usedTraffic: usedTraffic,
      totalTraffic: totalTraffic,
      remainingTraffic: remainingValue == null
          ? null
          : parseIntValue(remainingValue),
    );
  }
}

/// `/user/getSubscribe` 返回的订阅数据。
class XBoardSubscribeData {
  /// 订阅 URL（绝对 HTTPS URL）。
  final String? subscribeUrl;

  /// 订阅 token（可选；若无 URL 可按版本约定拼接）。
  final String? token;

  const XBoardSubscribeData({this.subscribeUrl, this.token});

  factory XBoardSubscribeData.fromData(Map<String, Object?> data) {
    final subscribeUrl = data['subscribe_url']?.toString();
    final token = data['token']?.toString();
    return XBoardSubscribeData(
      subscribeUrl: subscribeUrl,
      token: token?.isNotEmpty == true ? token : null,
    );
  }
}
