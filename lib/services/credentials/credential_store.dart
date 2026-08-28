import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:kitony_box/common/common.dart';
import 'package:kitony_box/models/auth_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 会话凭证安全存储抽象。
///
/// 设计目标：完整 token 不落入普通配置 JSON / 备份 ZIP。
/// 实现应尽量使用平台安全存储（Android Keystore / iOS/macOS Keychain /
/// Windows Credential Manager / Linux Secret Service）。
///
/// 注意：当前实现是基于 `crypto` 的受限混淆存储，仅能避免 token
/// 以明文形式出现在 SharedPreferences/备份中，**不等于**平台级加密。
/// 未来引入 flutter_secure_storage 后，只需替换 [CredentialStore] 的
/// 实现并保持接口不变，即可无缝升级。
abstract class CredentialStore {
  Future<bool> saveSession(String accountId, AuthSession session);

  Future<AuthSession?> readSession(String accountId);

  /// 返回是否确实完成删除；存储不可用时为 false，调用方需据此提示用户。
  Future<bool> deleteSession(String accountId);
}

const _sessionKeyPrefix = 'xboard_session_';

/// 基于 SharedPreferences 的受限实现。
///
/// 混淆策略：以应用内固定的派生密钥对明文做异或混淆（XOR obfuscation），
/// 派生密钥来自账号 id 的 SHA-256 摘要。
/// 这不是密码学强度加密——它只保证 token 不以可读明文落盘，
/// 适用于当前"固定面板、单账号"的 MVP；生产替换见 [CredentialStore]。
///
/// [SharedPreferences] 可通过 `prefsProvider` 注入，便于测试；
/// 默认使用项目全局 `preferences` 单例。
class SharedPreferencesCredentialStore implements CredentialStore {
  /// 返回 SharedPreferences 的提供者；默认取项目全局单例。
  final Future<SharedPreferences?> Function() _prefsProvider;

  SharedPreferencesCredentialStore({
    Future<SharedPreferences?> Function()? prefsProvider,
  }) : _prefsProvider =
           prefsProvider ??
           (() => preferences.sharedPreferencesCompleter.future);

  static String _key(String accountId) => '$_sessionKeyPrefix$accountId';

  /// 派生密钥：由固定盐 + 账号 id 派生，避免与常见密码哈希冲突。
  static List<int> _deriveKey(String accountId) {
    return sha256.convert(utf8.encode('kitonybox_xboard_v1:$accountId')).bytes;
  }

  /// XOR 混淆；密钥与明文等长循环展开。
  static String _obfuscate(String plain, List<int> key) {
    final bytes = utf8.encode(plain);
    final out = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      out[i] = bytes[i] ^ key[i % key.length];
    }
    return base64Encode(out);
  }

  static String _deobfuscate(String encoded, List<int> key) {
    final bytes = base64Decode(encoded);
    final out = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      out[i] = bytes[i] ^ key[i % key.length];
    }
    return utf8.decode(out);
  }

  @override
  Future<bool> saveSession(String accountId, AuthSession session) async {
    final prefs = await _prefsProvider();
    if (prefs == null) return false;
    final key = _deriveKey(accountId);
    final obfuscated = _obfuscate(session.encode(), key);
    return await prefs.setString(_key(accountId), obfuscated);
  }

  @override
  Future<AuthSession?> readSession(String accountId) async {
    final prefs = await _prefsProvider();
    if (prefs == null) return null;
    final encoded = prefs.getString(_key(accountId));
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final key = _deriveKey(accountId);
      final plain = _deobfuscate(encoded, key);
      return AuthSession.decode(plain);
    } catch (_) {
      // 数据损坏或密钥不匹配时视为无会话，避免崩溃。
      return null;
    }
  }

  @override
  Future<bool> deleteSession(String accountId) async {
    final prefs = await _prefsProvider();
    if (prefs == null) return false;
    return await prefs.remove(_key(accountId));
  }
}

/// 全局单例；替换平台安全实现时仅改此引用。
final credentialStore = SharedPreferencesCredentialStore();
