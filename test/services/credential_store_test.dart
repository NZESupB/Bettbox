import 'package:kitony_box/models/auth_session.dart';
import 'package:kitony_box/services/credentials/credential_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SharedPreferencesCredentialStore buildStore() {
    return SharedPreferencesCredentialStore(
      prefsProvider: () async => SharedPreferences.getInstance(),
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('保存后能读取会话，且持久化内容不含明文凭据', () async {
    final store = buildStore();
    final session = AuthSession(
      authorization: 'Bearer secret-token-abcdef',
      origin: 'https://kt.114432.xyz',
      savedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    await store.saveSession('xboard_default', session);

    final restored = await store.readSession('xboard_default');
    expect(restored, isNotNull);
    expect(restored!.authorization, 'Bearer secret-token-abcdef');
    expect(restored.origin, 'https://kt.114432.xyz');

    // 落盘内容不得包含明文凭据。
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('xboard_session_xboard_default');
    expect(stored, isNotNull);
    expect(stored, isNot(contains('secret-token-abcdef')));
  });

  test('删除会话后读取返回 null', () async {
    final store = buildStore();
    final session = AuthSession(
      authorization: 't',
      origin: '',
      savedAt: DateTime.now(),
    );
    await store.saveSession('xboard_default', session);
    await store.deleteSession('xboard_default');
    expect(await store.readSession('xboard_default'), isNull);
  });

  test('未保存的账号返回 null', () async {
    final store = buildStore();
    expect(await store.readSession('nonexistent'), isNull);
  });

  test('损坏数据返回 null 不崩溃', () async {
    final store = buildStore();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('xboard_session_bad', '!!!not-valid!!!');
    expect(await store.readSession('bad'), isNull);
  });
}
