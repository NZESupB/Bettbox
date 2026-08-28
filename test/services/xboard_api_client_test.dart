import 'dart:convert';
import 'dart:io';

import 'package:kitony_box/services/xboard/xboard_api_client.dart';
import 'package:kitony_box/services/xboard/xboard_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用本地 HttpServer mock 验证 XBoard API 客户端的行为。
/// 禁止依赖真实账号或目标面板。
void main() {
  group('XBoardApiClient login', () {
    test('固定面板分离 TLS host 与 API Host', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        expect(
          request.headers.value(HttpHeaders.hostHeader),
          XBoardPanel.apiRequestHost,
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'status': 'success',
            'data': {
              'token': 'test-token',
              'auth_data': 'Bearer auth-data-value',
            },
          }),
        );
        await request.response.close();
      });

      try {
        final client = XBoardApiClient(
          baseUrl: 'http://${server.address.host}:${server.port}',
          requestHost: XBoardPanel.apiRequestHost,
        );
        await client.login(email: 'user@example.com', password: 'secret');
      } finally {
        await server.close(force: true);
        await subscription.cancel();
      }
    });

    test('自定义 baseUrl 默认保留目标服务器 Host', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        expect(
          request.headers.value(HttpHeaders.hostHeader),
          '${server.address.host}:${server.port}',
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'status': 'success',
            'data': {
              'token': 'test-token',
              'auth_data': 'Bearer auth-data-value',
            },
          }),
        );
        await request.response.close();
      });

      try {
        final client = XBoardApiClient(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );
        await client.login(email: 'user@example.com', password: 'secret');
      } finally {
        await server.close(force: true);
        await subscription.cancel();
      }
    });

    test('POST /passport/auth/login 用 auth_data 作认证凭据', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/passport/auth/login');
        final body = await utf8.decoder.bind(request).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        expect(json['email'], 'user@example.com');
        expect(json['password'], isNotEmpty);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'status': 'success',
            'message': 'ok',
            'data': {
              'token': 'test-token-123',
              'auth_data': 'Bearer auth-data-value',
              'is_admin': false,
            },
          }),
        );
        await request.response.close();
      });

      try {
        final client = XBoardApiClient(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );
        final data = await client.login(
          email: 'user@example.com',
          password: 'secret',
        );
        // `auth_data` 才是认证凭据；`token` 是订阅 token，不能拿来认证。
        expect(data.authorization, 'Bearer auth-data-value');
        expect(data.subscribeToken, 'test-token-123');
        expect(data.isAdmin, isFalse);
      } finally {
        await server.close(force: true);
        await subscription.cancel();
      }
    });

    test('面板未返回 auth_data 时退回 token 并补 Bearer 前缀', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'status': 'success',
            'data': {'token': 'only-token'},
          }),
        );
        await request.response.close();
      });

      try {
        final client = XBoardApiClient(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );
        final data = await client.login(
          email: 'user@example.com',
          password: 'secret',
        );
        expect(data.authorization, 'Bearer only-token');
        expect(data.subscribeToken, 'only-token');
      } finally {
        await server.close(force: true);
        await subscription.cancel();
      }
    });

    test('业务失败时抛 XBoardException 且不泄漏凭据', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.statusCode = HttpStatus.ok;
        request.response.write(
          jsonEncode({'status': 'fail', 'message': '邮箱或密码错误'}),
        );
        await request.response.close();
      });

      try {
        final client = XBoardApiClient(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );
        await expectLater(
          client.login(email: 'user@example.com', password: 'wrong'),
          throwsA(
            isA<XBoardException>().having(
              (e) => e.message,
              'message',
              contains('邮箱或密码错误'),
            ),
          ),
        );
      } finally {
        await server.close(force: true);
        await subscription.cancel();
      }
    });

    test('认证失效 403 转为 XBoardSessionExpiredException', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.statusCode = HttpStatus.forbidden;
        request.response.write(
          jsonEncode({'status': 'fail', 'message': '未登录'}),
        );
        await request.response.close();
      });

      try {
        final client = XBoardApiClient(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );
        await expectLater(
          client.getUserInfo(),
          throwsA(isA<XBoardSessionExpiredException>()),
        );
      } finally {
        await server.close(force: true);
        await subscription.cancel();
      }
    });

    test('拒绝 API 重定向且不向目标 host 发送请求', () async {
      var redirectedRequestReceived = false;
      final targetServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final targetSubscription = targetServer.listen((request) async {
        redirectedRequestReceived = true;
        await request.response.close();
      });
      final sourceServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final sourceSubscription = sourceServer.listen((request) async {
        request.response.statusCode = HttpStatus.temporaryRedirect;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'http://${targetServer.address.host}:${targetServer.port}/redirected',
        );
        await request.response.close();
      });

      try {
        final client = XBoardApiClient(
          baseUrl: 'http://${sourceServer.address.host}:${sourceServer.port}',
        );
        client.setAuthorization('Bearer auth-data-value');
        await expectLater(
          client.getUserInfo(),
          throwsA(isA<XBoardNetworkException>()),
        );
        expect(redirectedRequestReceived, isFalse);
      } finally {
        await sourceServer.close(force: true);
        await sourceSubscription.cancel();
        await targetServer.close(force: true);
        await targetSubscription.cancel();
      }
    });

    test('SPA fallback 返回 text/html 时拒绝解析', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write('<html>SPA fallback</html>');
        await request.response.close();
      });

      try {
        final client = XBoardApiClient(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );
        await expectLater(
          client.getUserInfo(),
          throwsA(isA<XBoardException>()),
        );
      } finally {
        await server.close(force: true);
        await subscription.cancel();
      }
    });

    test('表单校验：空邮箱/密码直接抛 XBoardValidationException', () async {
      final client = XBoardApiClient();
      await expectLater(
        client.login(email: '', password: 'x'),
        throwsA(isA<XBoardValidationException>()),
      );
      await expectLater(
        client.login(email: 'a@b.com', password: ''),
        throwsA(isA<XBoardValidationException>()),
      );
    });
  });

  group('XBoardApiClient user info & subscribe', () {
    test('流量与套餐取自 /user/getSubscribe（/user/info 不返回 u/d）', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final paths = <String>[];
      final subscription = server.listen((request) async {
        paths.add(request.uri.path);
        final auth = request.headers.value(HttpHeaders.authorizationHeader);
        // auth_data 已含 Bearer 前缀，必须原样透传，不能拼成 `Bearer Bearer ...`。
        expect(auth, 'Bearer auth-data-value');
        request.response.headers.contentType = ContentType.json;
        // 按上游 select() 的真实字段构造：/user/info 既没有 u/d，也没有 plan。
        final data = request.uri.path == '/user/info'
            ? {
                'email': 'user@example.com',
                'transfer_enable': 1073741824,
                'expired_at': 1735689600,
                'plan_id': 7,
              }
            : {
                'plan_id': 7,
                'token': 'subscribe-token',
                'expired_at': 1735689600,
                'u': 1024,
                'd': 2048,
                'transfer_enable': 1073741824,
                'plan': {'name': 'Pro'},
              };
        request.response.write(jsonEncode({'status': 'success', 'data': data}));
        await request.response.close();
      });

      try {
        final client = XBoardApiClient(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );
        client.setAuthorization('Bearer auth-data-value');
        final info = await client.getUserInfo();
        expect(paths, containsAll(['/user/info', '/user/getSubscribe']));
        expect(info.email, 'user@example.com');
        // 只读 /user/info 时这里会是 0——这正是流量显示不准的原因。
        expect(info.usedTraffic, 3072);
        expect(info.totalTraffic, 1073741824);
        expect(info.planName, 'Pro');
        expect(info.expireAt, 1735689600);
      } finally {
        await server.close(force: true);
        await subscription.cancel();
      }
    });

    test('订阅接口业务失败时降级为只用 /user/info，不影响账号信息', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/user/getSubscribe') {
          request.response.write(
            jsonEncode({'status': 'fail', 'message': '订阅计划不存在'}),
          );
        } else {
          request.response.write(
            jsonEncode({
              'status': 'success',
              'data': {
                'email': 'user@example.com',
                'transfer_enable': 1073741824,
                'expired_at': 1735689600,
              },
            }),
          );
        }
        await request.response.close();
      });

      try {
        final client = XBoardApiClient(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );
        final info = await client.getUserInfo();
        expect(info.email, 'user@example.com');
        expect(info.totalTraffic, 1073741824);
        expect(info.usedTraffic, 0);
      } finally {
        await server.close(force: true);
        await subscription.cancel();
      }
    });

    test('/user/getSubscribe 返回订阅 URL', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        expect(request.uri.path, '/user/getSubscribe');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'status': 'success',
            'data': {'subscribe_url': 'https://pair_1.114432.xyz/sub/abc123'},
          }),
        );
        await request.response.close();
      });

      try {
        final client = XBoardApiClient(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );
        final subscribe = await client.getSubscribe();
        expect(subscribe.subscribeUrl, 'https://pair_1.114432.xyz/sub/abc123');
      } finally {
        await server.close(force: true);
        await subscription.cancel();
      }
    });
  });
}
