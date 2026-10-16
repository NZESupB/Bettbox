import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitony_box/common/constant.dart';
import 'package:kitony_box/common/request.dart';

class _UpdateAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) respond;
  final requests = <RequestOptions>[];

  _UpdateAdapter(this.respond);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Request createRequest(_UpdateAdapter adapter) {
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    return Request(dio: dio, versionProvider: () => '1.19.6');
  }

  _UpdateAdapter redirect(String? location) => _UpdateAdapter(
    (_) => ResponseBody.fromString(
      '',
      302,
      headers: {
        if (location != null) 'location': [location],
      },
    ),
  );

  test('更新检查请求及下载页始终属于本项目', () async {
    final adapter = redirect(
      'https://github.com/NZESupB/Bettbox/releases/tag/v1.19.7',
    );
    final result = await createRequest(adapter).checkForUpdate();

    expect(repository, 'NZESupB/Bettbox');
    expect(adapter.requests, hasLength(1));
    final options = adapter.requests.single;
    expect(options.uri.scheme, 'https');
    expect(options.uri.host, 'github.com');
    expect(options.uri.path, '/NZESupB/Bettbox/releases/latest');
    expect(options.uri.queryParameters['t'], isNotEmpty);
    expect(options.followRedirects, isFalse);
    expect(result?['tag_name'], 'v1.19.7');
    expect(
      result?['html_url'],
      'https://github.com/NZESupB/Bettbox/releases/latest',
    );
  });

  test('接受本仓库相对 Release 跳转', () async {
    final adapter = redirect('/NZESupB/Bettbox/releases/tag/v1.20.0');
    expect(
      (await createRequest(adapter).checkForUpdate())?['tag_name'],
      'v1.20.0',
    );
  });

  for (final version in ['v1.19.6', 'v1.19.5', 'v1.9.9']) {
    test('远端 $version 不高于当前版本时不提示', () async {
      final adapter = redirect(
        'https://github.com/NZESupB/Bettbox/releases/tag/$version',
      );
      expect(await createRequest(adapter).checkForUpdate(), isNull);
    });
  }

  for (final location in <String?>[
    null,
    'https://github.com/appshubcc/Bettbox/releases/tag/v9.0.0',
    'https://example.com/NZESupB/Bettbox/releases/tag/v9.0.0',
    'http://github.com/NZESupB/Bettbox/releases/tag/v9.0.0',
    'https://github.com:8443/NZESupB/Bettbox/releases/tag/v9.0.0',
    'https://user@github.com/NZESupB/Bettbox/releases/tag/v9.0.0',
    'https://github.com/NZESupB/Bettbox/releases',
    '/NZESupB/Bettbox/releases/tag/',
    '/NZESupB/Bettbox/releases/tag/v9.0.0/extra',
  ]) {
    test('拒绝无效或非本项目的跳转：$location', () async {
      final adapter = redirect(location);
      expect(await createRequest(adapter).checkForUpdate(), isNull);
      expect(adapter.requests, hasLength(1));
    });
  }

  for (final status in [200, 404, 500]) {
    test('HTTP $status 不产生更新提示', () async {
      final adapter = _UpdateAdapter(
        (_) => ResponseBody.fromString('', status),
      );
      expect(await createRequest(adapter).checkForUpdate(), isNull);
    });
  }

  test('网络失败不产生更新提示', () async {
    final adapter = _UpdateAdapter(
      (options) => throw DioException.connectionTimeout(
        timeout: const Duration(seconds: 1),
        requestOptions: options,
      ),
    );
    expect(await createRequest(adapter).checkForUpdate(), isNull);
  });
}
