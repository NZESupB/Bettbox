import 'dart:async';

import 'package:kitony_box/common/common.dart';
import 'package:kitony_box/models/models.dart';
import 'package:kitony_box/providers/providers.dart';
import 'package:kitony_box/services/credentials/credential_store.dart';
import 'package:kitony_box/services/xboard/xboard_api_client.dart';
import 'package:kitony_box/services/xboard/xboard_models.dart';
import 'package:kitony_box/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 账号持久化 key（非敏感元数据；与全局配置 JSON 解耦）。
const xboardAccountPrefsKey = 'xboard_account';

/// 账号登录/会话状态。
enum XBoardAuthStatus {
  /// 尚未初始化（启动恢复中）。
  initial,

  /// 未登录。
  unauthenticated,

  /// 登录/恢复中。
  loading,

  /// 已登录且会话可用。
  authenticated,

  /// 会话失效，需要重新登录（保留账号元数据与关联 Profile）。
  sessionExpired,

  /// 发生错误（展示在 UI）。
  error,
}

/// 账号模块的完整状态。
class XBoardAccountState {
  /// 非敏感账号元数据；未登录时为 null。
  final Account? account;

  /// 内存中的会话（含 token）；使用后应尽快替换为 null。
  final AuthSession? session;

  final XBoardAuthStatus status;

  /// 用户信息（流量/套餐），登录后拉取。
  final XBoardUserInfo? userInfo;

  /// 订阅同步中标记。
  final bool isSyncing;

  /// 错误信息（面板 message 或本地校验提示）。
  final String? errorMessage;

  const XBoardAccountState({
    this.account,
    this.session,
    this.status = XBoardAuthStatus.initial,
    this.userInfo,
    this.isSyncing = false,
    this.errorMessage,
  });

  XBoardAccountState copyWith({
    Account? account,
    AuthSession? session,
    XBoardAuthStatus? status,
    XBoardUserInfo? userInfo,
    bool? isSyncing,
    String? errorMessage,
    bool clearSession = false,
    bool clearUserInfo = false,
    bool clearErrorMessage = false,
  }) {
    return XBoardAccountState(
      account: account ?? this.account,
      session: clearSession ? null : session ?? this.session,
      status: status ?? this.status,
      userInfo: clearUserInfo ? null : userInfo ?? this.userInfo,
      isSyncing: isSyncing ?? this.isSyncing,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

class XBoardAccountNotifier extends Notifier<XBoardAccountState> {
  /// 登录互斥锁，避免快速点击重复提交。
  bool _isLoginInProgress = false;
  bool _isRestoring = false;

  @override
  XBoardAccountState build() {
    // 启动后异步恢复会话；不阻塞核心启动。
    Future.microtask(() {
      unawaited(restoreSession());
    });
    return const XBoardAccountState();
  }

  /// 从安全存储恢复账号与会话。
  Future<void> restoreSession() async {
    if (_isRestoring) return;
    _isRestoring = true;
    try {
      final accountJson = await _readAccountJson();
      final account = Account.decode(accountJson);
      if (account == null) {
        state = const XBoardAccountState(
          status: XBoardAuthStatus.unauthenticated,
        );
        return;
      }
      final session = await credentialStore.readSession(account.id);
      if (session == null || session.hasExpired) {
        // 会话不存在或已过期：保留账号元数据，标记需重新登录。
        state = XBoardAccountState(
          account: account,
          status: XBoardAuthStatus.sessionExpired,
        );
        return;
      }
      state = XBoardAccountState(
        account: account,
        session: session,
        status: XBoardAuthStatus.authenticated,
      );
      xboardApiClient.setAuthorization(session.authorization);
      // 后台刷新用户信息；失败不阻塞，由 UI 引导重新登录。
      unawaited(_refreshUserInfoSafe());
    } finally {
      _isRestoring = false;
    }
  }

  Future<String?> _readAccountJson() async {
    final prefs = await preferences.sharedPreferencesCompleter.future;
    return prefs?.getString(xboardAccountPrefsKey);
  }

  Future<bool> _writeAccount(Account account) async {
    final prefs = await preferences.sharedPreferencesCompleter.future;
    if (prefs == null) return false;
    return await prefs.setString(xboardAccountPrefsKey, account.encode());
  }

  /// 登录：校验 → 请求 → 保存会话 → 拉取信息 → 自动导入订阅。
  Future<bool> login({required String email, required String password}) async {
    if (_isLoginInProgress) return false;
    _isLoginInProgress = true;
    state = state.copyWith(
      status: XBoardAuthStatus.loading,
      clearErrorMessage: true,
    );
    try {
      final loginData = await xboardApiClient.login(
        email: email,
        password: password,
      );
      final session = AuthSession(
        authorization: loginData.authorization,
        origin: XBoardPanel.origin,
        savedAt: DateTime.now(),
      );

      // 固定面板单账号：统一使用固定 id，避免重复账号。
      const accountId = 'xboard_default';
      final rawEmail = email.trim();
      final account = Account(
        id: accountId,
        origin: XBoardPanel.origin,
        apiBaseUrl: XBoardPanel.apiBaseUrl,
        email: Account.maskEmail(rawEmail),
        label: _defaultLabel(rawEmail),
      );

      // 持久化必须成功，否则下次启动会话丢失、账号被静默判为失效。
      final savedSession = await credentialStore.saveSession(
        accountId,
        session,
      );
      final savedAccount = await _writeAccount(account);
      if (!savedSession || !savedAccount) {
        await credentialStore.deleteSession(accountId);
        throw XBoardException(appLocalizations.xboardPersistFailed);
      }
      xboardApiClient.setAuthorization(session.authorization);

      state = XBoardAccountState(
        account: account,
        session: session,
        status: XBoardAuthStatus.authenticated,
      );

      // 后台拉取用户信息。
      unawaited(_refreshUserInfoSafe());

      // 自动导入并更新订阅；失败只写入提示，由 _syncSubscription 统一处理。
      // 仅当会话失效（status 被改写）时才判定登录失败。
      await _syncSubscription(account);
      return state.status == XBoardAuthStatus.authenticated;
    } on XBoardSessionExpiredException catch (e) {
      state = state.copyWith(
        status: XBoardAuthStatus.sessionExpired,
        errorMessage: e.message,
      );
      return false;
    } on XBoardException catch (e) {
      state = state.copyWith(
        status: XBoardAuthStatus.error,
        errorMessage: e.message,
      );
      return false;
    } on Object catch (e) {
      state = state.copyWith(
        status: XBoardAuthStatus.error,
        errorMessage: e.formatError,
      );
      return false;
    } finally {
      _isLoginInProgress = false;
    }
  }

  /// 拉取用户信息（已登录时）。
  Future<void> _refreshUserInfoSafe() async {
    try {
      final userInfo = await xboardApiClient.getUserInfo();
      // 会话仍有效则更新；否则保持当前状态由 sessionExpired 接管。
      if (state.status == XBoardAuthStatus.authenticated ||
          state.session != null) {
        state = state.copyWith(userInfo: userInfo, clearErrorMessage: true);
      }
    } on XBoardSessionExpiredException {
      await _handleSessionExpired();
    } on Object catch (e) {
      commonPrint.log('[XBoard] refresh user info failed: ${e.formatError}');
    }
  }

  /// 刷新用户信息（UI 手动触发）。
  Future<void> refreshUserInfo() => _refreshUserInfoSafe();

  /// 会话失效处理：保留账号元数据，清除 token，标记需重新登录。
  Future<void> _handleSessionExpired() async {
    final account = state.account;
    if (account != null) {
      await credentialStore.deleteSession(account.id);
    }
    xboardApiClient.setAuthorization(null);
    state = state.copyWith(
      session: null,
      status: XBoardAuthStatus.sessionExpired,
      errorMessage: appLocalizations.xboardSessionExpired,
      clearSession: true,
    );
  }

  /// 退出登录：清除安全存储中的会话与本地账号元数据。
  ///
  /// 清除失败时不置为未登录——否则下次启动会把已登出的账号恢复回来。
  Future<bool> logout() async {
    final account = state.account;
    final removedSession =
        account == null || await credentialStore.deleteSession(account.id);
    final prefs = await preferences.sharedPreferencesCompleter.future;
    final removedAccount =
        prefs != null && await prefs.remove(xboardAccountPrefsKey);
    xboardApiClient.setAuthorization(null);
    if (!removedSession || !removedAccount) {
      state = state.copyWith(
        status: XBoardAuthStatus.error,
        errorMessage: appLocalizations.xboardPersistFailed,
        clearSession: true,
        clearUserInfo: true,
      );
      return false;
    }
    state = const XBoardAccountState(status: XBoardAuthStatus.unauthenticated);
    return true;
  }

  /// 手动同步订阅（更新关联 Profile）。
  Future<bool> syncSubscription() async {
    final account = state.account;
    if (account == null || state.session == null) return false;
    state = state.copyWith(isSyncing: true, clearErrorMessage: true);
    try {
      return await _syncSubscription(account);
    } finally {
      state = state.copyWith(isSyncing: false);
    }
  }

  /// 从面板获取订阅 URL，创建或更新关联 Profile。
  ///
  /// 所有失败都在此收敛为 `false` + errorMessage：调用方无需再分类异常。
  Future<bool> _syncSubscription(Account account) async {
    try {
      final subscribe = await xboardApiClient.getSubscribe();
      final url = _buildValidatedSubscribeUrl(subscribe);
      final profileId = account.profileId;
      final existing = profileId == null
          ? null
          : ref.read(profilesProvider).getProfile(profileId);

      final String targetProfileId;
      if (existing != null) {
        // 复用已有 Profile，避免重复创建；profile 被删除时走重建分支。
        final target = existing.copyWith(url: url, autoUpdate: true);
        _ensureCurrentProfile(target.id);
        await globalState.appController.updateProfile(target);
        targetProfileId = target.id;
      } else {
        targetProfileId = await _createProfile(account, url);
      }

      final newAccount = account.copyWith(
        profileId: targetProfileId,
        lastSyncTime: DateTime.now(),
      );
      await _writeAccount(newAccount);
      state = state.copyWith(account: newAccount, clearErrorMessage: true);
      return true;
    } on XBoardSessionExpiredException {
      await _handleSessionExpired();
      return false;
    } on Object catch (e) {
      // updateProfile 可能抛出 String（校验失败）或 DioException（网络失败）。
      final message = e is XBoardException ? e.message : e.formatError;
      commonPrint.log('[XBoard] sync subscription failed: $message');
      state = state.copyWith(
        errorMessage: message.isEmpty
            ? appLocalizations.xboardSyncSubscriptionFailed
            : message,
      );
      return false;
    }
  }

  Future<String> _createProfile(Account account, String url) async {
    final profile = Profile.normal(label: account.label, url: url);
    // 先占位为当前 Profile，updateProfile 才会在写入后触发配置下发。
    _ensureCurrentProfile(profile.id);
    try {
      // updateProfile 会调用 profile.update() 下载并校验订阅文件，
      // 然后通过 setProfile 写入 profilesProvider；id 保持不变。
      await globalState.appController.updateProfile(profile);
    } on Object {
      // 下载/校验失败时 profile 未落盘，撤销占位避免当前 Profile 悬空。
      final currentProfileId = globalState.appController.ref.read(
        currentProfileIdProvider.notifier,
      );
      if (currentProfileId.state == profile.id) {
        currentProfileId.value = null;
      }
      rethrow;
    }
    return profile.id;
  }

  /// 单账号固定面板场景：无当前 Profile 时自动设为当前。
  ///
  /// 必须在 `updateProfile` 之前调用——后者仅在 profile 已是当前时才会
  /// `applyProfileDebounce`，否则配置写入了却不会下发到内核。
  void _ensureCurrentProfile(String profileId) {
    final appController = globalState.appController;
    if (appController.ref.read(currentProfileIdProvider) == null) {
      appController.ref.read(currentProfileIdProvider.notifier).value =
          profileId;
    }
  }

  String _buildValidatedSubscribeUrl(XBoardSubscribeData subscribe) {
    final rawUrl = subscribe.subscribeUrl ?? '';
    if (rawUrl.isEmpty) {
      // 只有 token 时按固定面板版本约定构造（?flag=clash）。
      final token = subscribe.token;
      if (token != null && token.isNotEmpty) {
        return '${XBoardPanel.apiBaseUrl}/user/getSubscribe?token=$token&flag=clash';
      }
      throw const XBoardException('subscribe url unavailable');
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !XBoardPanel.isAllowedSubscribeHost(uri.host)) {
      throw const XBoardException('subscribe url is invalid');
    }
    return rawUrl;
  }

  String _defaultLabel(String email) {
    final atIndex = email.indexOf('@');
    final prefix = atIndex > 0 ? email.substring(0, atIndex) : email;
    return prefix.isEmpty ? 'XBoard' : prefix;
  }
}

final xboardAccountProvider =
    NotifierProvider<XBoardAccountNotifier, XBoardAccountState>(
      XBoardAccountNotifier.new,
    );
