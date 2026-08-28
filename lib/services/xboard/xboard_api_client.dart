import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kitony_box/services/xboard/xboard_models.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// 固定的 XBoard/V2Board 面板配置。
///
/// 目标站已核验：
/// - 首页 `https://kt.114432.xyz/` 为 EZ SPA，公开 `config.js` 声明 `PANEL_TYPE: 'Xboard'`。
/// - API 基址为 `https://pair_1.114432.xyz/api/v1`，而非首页域名下的 `/api/v1`。
/// - API host 含下划线，Android 无法用 `*.114432.xyz` 完成 hostname 校验；
///   TLS 连接需使用首页 host，再通过 HTTP Host 路由到 API 虚拟主机。
/// - 登录必须使用 `POST /passport/auth/login`（GET 返回 405 且 `Allow: POST`）。
abstract class XBoardPanel {
  static const String origin = 'https://kt.114432.xyz';

  /// 面板公开配置声明的 canonical API 地址，用于账号元数据与订阅 URL。
  static const String apiBaseUrl = 'https://pair_1.114432.xyz/api/v1';

  /// 实际 TLS 连接地址。该 host 符合 hostname 语法且被系统证书正常覆盖。
  static const String apiTransportBaseUrl = '$origin/api/v1';

  /// HTTP 虚拟主机；由 Cloudflare 将请求路由到 XBoard API。
  static const String apiRequestHost = 'pair_1.114432.xyz';

  /// 允许的订阅 host 后缀（订阅 URL 校验用）。
  static const List<String> allowedSubscribeHostSuffixes = ['114432.xyz'];

  /// 校验订阅 URL host 是否在面板允许范围内。
  static bool isAllowedSubscribeHost(String host) {
    final normalized = host.toLowerCase();
    return allowedSubscribeHostSuffixes.any(
      (suffix) => normalized == suffix || normalized.endsWith('.$suffix'),
    );
  }
}

/// XBoard API 客户端。
///
/// 原则：
/// - 统一 JSON 请求，设置连接/接收超时与 User-Agent；
/// - 解析 `{status, message, data, error}`，拒绝 text/html 的 SPA fallback；
/// - 认证错误统一转为 [XBoardSessionExpiredException]；
/// - 错误日志只保留 host、HTTP 状态与面板 message，绝不记录凭据。
class XBoardApiClient {
  late final Dio _dio;

  XBoardApiClient({
    String? baseUrl,
    String? requestHost,
    String? userAgent,
    Duration? timeout,
  }) {
    final usesDefaultPanel = baseUrl == null;
    final resolvedRequestHost =
        requestHost ?? (usesDefaultPanel ? XBoardPanel.apiRequestHost : null);
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? XBoardPanel.apiTransportBaseUrl,
        connectTimeout: timeout ?? const Duration(seconds: 10),
        receiveTimeout: timeout ?? const Duration(seconds: 15),
        sendTimeout: timeout ?? const Duration(seconds: 10),
        headers: {
          'User-Agent': userAgent ?? 'KitonyBox',
          HttpHeaders.hostHeader: ?resolvedRequestHost,
        },
        // 固定面板不需要重定向。拒绝自动跳转可避免 Authorization 与固定
        // Host 被带到未知目标，也让 API 域名变化以明确错误暴露出来。
        followRedirects: false,
        responseType: ResponseType.json,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        // 不接受任意证书：保持系统默认证书校验。
        client.badCertificateCallback = null;
        // 面板 API 必须与隧道状态无关。`HttpClient()` 会命中全局
        // KitonyBoxHttpOverrides，核心一运行就被改成走 PROXY localhost:mixedPort，
        // 于是登录/账号信息反过来依赖「代理已就绪」；更糟的是登录成功后导入订阅、
        // 配置刚下发的瞬间代理状态翻转，前一个请求 DIRECT、后一个请求突然走代理，
        // 握手失败只会得到一个无从下手的传输层错误。这里固定 DIRECT。
        client.findProxy = (_) => 'DIRECT';
        return client;
      },
    );
    _dio = dio;
  }

  /// 注入完整的 `Authorization` 头值。
  ///
  /// 传入的值就是面板返回的 `auth_data`，其本身已包含 `Bearer ` 前缀（旧版
  /// V2Board 则是原始凭据串），因此这里原样写入、不再拼接前缀。
  void setAuthorization(String? authorization) {
    _dio.interceptors.clear();
    if (authorization == null || authorization.isEmpty) return;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['Authorization'] = authorization;
          handler.next(options);
        },
      ),
    );
  }

  /// POST 登录。email 会做基础格式校验。
  Future<XBoardLoginData> login({
    required String email,
    required String password,
  }) async {
    final emailTrimmed = email.trim();
    if (emailTrimmed.isEmpty) {
      throw const XBoardValidationException('email is required');
    }
    if (password.isEmpty) {
      throw const XBoardValidationException('password is required');
    }
    final body = <String, Object?>{'email': emailTrimmed, 'password': password};
    final data = await _post('/passport/auth/login', body);
    final loginData = XBoardLoginData.fromData(data);
    if (loginData.authorization.isEmpty) {
      throw const XBoardException(
        'login succeeded but no auth credential returned',
      );
    }
    return loginData;
  }

  /// 获取用户信息（含流量与套餐）。需要已登录。
  ///
  /// 上游 `/user/info` 的 `select()` 只取 email、transfer_enable、expired_at、
  /// plan_id 等字段，**不含已用流量 `u`/`d`，也不含套餐详情 `plan`**——这些只有
  /// `/user/getSubscribe` 返回。只读 `/user/info` 会让已用流量恒为 0、套餐名恒为空，
  /// 所以这里合并两个接口的数据。
  Future<XBoardUserInfo> getUserInfo() async {
    final info = await _get('/user/info');
    // 订阅接口失败（例如尚未订阅套餐）不该让整个账号信息不可用，降级为只用
    // /user/info；但认证失效必须继续上抛，交给会话失效流程处理。
    Map<String, Object?> subscribe;
    try {
      subscribe = await _get('/user/getSubscribe');
    } on XBoardSessionExpiredException {
      rethrow;
    } on XBoardException {
      subscribe = const {};
    }
    return XBoardUserInfo.fromData({...info, ...subscribe});
  }

  /// GET /user/getSubscribe 获取订阅数据。
  Future<XBoardSubscribeData> getSubscribe() async {
    final data = await _get('/user/getSubscribe');
    return XBoardSubscribeData.fromData(data);
  }

  Future<Map<String, Object?>> _get(String path) async {
    return _execute(() async {
      final response = await _dio.get<Object?>(path);
      return _parseBody(response);
    });
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    return _execute(() async {
      final response = await _dio.post<Object?>(path, data: body);
      return _parseBody(response);
    });
  }

  Future<Map<String, Object?>> _parseBody(Response<Object?> response) async {
    final data = response.data;
    Object? body;
    if (data is String) {
      // 某些面板可能返回字符串 JSON。
      try {
        body = jsonDecode(data);
      } catch (_) {
        throw const XBoardParseException('unexpected response format');
      }
    } else {
      body = data;
    }
    if (body is! Map) {
      throw const XBoardParseException('unexpected response format');
    }
    final result = XBoardResponse.fromMap(body);
    if (!result.success) {
      throw XBoardException(result.message);
    }
    return result.data ?? <String, Object?>{};
  }

  Future<Map<String, Object?>> _execute(
    Future<Map<String, Object?>> Function() request,
  ) async {
    try {
      return await request();
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final body = e.response?.data;
      // 认证失效：401/403。
      if (statusCode == 401 || statusCode == 403) {
        final message = _extractPanelMessage(body);
        throw XBoardSessionExpiredException(message);
      }
      // SPA fallback 可能返回 200 但 text/html；dio responseType json 会抛格式错误。
      final contentType = e.response?.headers.value(Headers.contentTypeHeader);
      if (contentType?.contains('text/html') == true) {
        throw const XBoardParseException('panel returned html instead of json');
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          throw const XBoardNetworkException('network timeout');
        case DioExceptionType.connectionError:
          throw const XBoardNetworkException('network unavailable');
        case DioExceptionType.badCertificate:
          throw const XBoardNetworkException('bad certificate');
        default:
          final message = _extractPanelMessage(body);
          if (message.isNotEmpty) {
            throw XBoardException(message);
          }
          throw XBoardNetworkException(_describeTransportError(e));
      }
    }
  }

  /// 传输层错误的可诊断描述。
  ///
  /// `DioExceptionType.unknown` 下 `response` 与 `statusCode` 都是 null，真正的
  /// 原因藏在 `e.error`（SocketException / HandshakeException 等）。只拼类型与
  /// 描述，不含请求体与凭据。
  String _describeTransportError(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode != null) {
      return 'http error $statusCode';
    }
    final inner = e.error;
    // 传输层异常（连接/TLS）的 toString 只含 host、端口与系统错误，可安全展示。
    if (inner is SocketException || inner is TlsException) {
      return '${e.type.name}: $inner';
    }
    if (inner != null) {
      // 其它内层异常（如解析异常）可能带响应片段，登录响应里含 token，
      // 因此只输出类型名。
      return '${e.type.name}: ${inner.runtimeType}';
    }
    final message = e.message;
    return message == null || message.isEmpty
        ? e.type.name
        : '${e.type.name}: $message';
  }

  String _extractPanelMessage(Object? body) {
    if (body is! Map) return '';
    final message = body['message'];
    if (message is String && message.isNotEmpty) return message;
    final error = body['error'];
    if (error is Map) return error['message']?.toString() ?? '';
    if (error is String && error.isNotEmpty) return error;
    return '';
  }
}

/// 全局单例；登录状态通过 [XBoardApiClient.setAuthorization] 注入。
final xboardApiClient = XBoardApiClient();
