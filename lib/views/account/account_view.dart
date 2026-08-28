import 'package:kitony_box/common/common.dart';
import 'package:kitony_box/enum/enum.dart';
import 'package:kitony_box/models/models.dart';
import 'package:kitony_box/providers/providers.dart';
import 'package:kitony_box/services/xboard/xboard_models.dart';
import 'package:kitony_box/state.dart';
import 'package:kitony_box/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 一级导航栏目形态的账号页面。
///
/// [AccountView] 本身只是 body：从 Tools 设置页打开时，标题栏由
/// `AdaptiveSheetScaffold` 提供。作为侧边栏/底部导航的一级页面时没有外层
/// 容器，需要像 `ProfilesView` 那样自带 [CommonScaffold]。
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: appLocalizations.xboardAccount,
      body: const AccountView(),
    );
  }
}

/// 固定面板的账号管理页面 body。
///
/// 从 Tools 设置页通过 `showExtend` + `AdaptiveSheetScaffold` 打开；
/// 内部根据账号状态切换登录表单与账号详情，跨桌面/移动/Android TV。
class AccountView extends ConsumerStatefulWidget {
  const AccountView({super.key});

  @override
  ConsumerState<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends ConsumerState<AccountView> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _obscurePassword = ValueNotifier<bool>(true);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _obscurePassword.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(xboardAccountProvider.notifier);
    final success = await notifier.login(
      email: _emailController.text,
      password: _passwordController.text,
    );
    if (success && mounted) {
      // 清空密码框，避免残留。
      _passwordController.clear();
    }
  }

  Future<void> _logout() async {
    final confirmed = await globalState.showMessage(
      title: appLocalizations.xboardLogout,
      message: TextSpan(text: appLocalizations.xboardLogoutConfirm),
    );
    if (confirmed != true) return;
    await ref.read(xboardAccountProvider.notifier).logout();
  }

  String _formatTraffic(int bytes) {
    if (bytes <= 0) return '0 B';
    return TrafficValue(value: bytes).shortShow;
  }

  String _formatExpire(int expireAt) {
    if (expireAt <= 0) return appLocalizations.xboardNeverExpires;
    final date = DateTime.fromMillisecondsSinceEpoch(expireAt * 1000);
    return date.show;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(xboardAccountProvider);
    return switch (state.status) {
      XBoardAuthStatus.initial ||
      XBoardAuthStatus.loading ||
      XBoardAuthStatus.unauthenticated ||
      XBoardAuthStatus.sessionExpired ||
      XBoardAuthStatus.error => _buildLogin(context, state),
      XBoardAuthStatus.authenticated => _buildDetail(context, state),
    };
  }

  Widget _buildLogin(BuildContext context, XBoardAccountState state) {
    final isLoading = state.status == XBoardAuthStatus.loading;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (state.status == XBoardAuthStatus.sessionExpired) ...[
          _buildNotice(
            context,
            icon: Icons.hourglass_disabled,
            message:
                '${state.errorMessage ?? appLocalizations.xboardSessionExpired}'
                '${state.account != null ? ' (${state.account!.email})' : ''}',
          ),
          const SizedBox(height: 12),
        ],
        if (state.status == XBoardAuthStatus.error) ...[
          _buildNotice(
            context,
            icon: Icons.error_outline,
            message: state.errorMessage ?? appLocalizations.xboardLoginFailed,
            isError: true,
          ),
          const SizedBox(height: 12),
        ],
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.mail_outline),
                  border: const OutlineInputBorder(),
                  labelText: appLocalizations.xboardEmail,
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return appLocalizations.xboardEmailNull;
                  }
                  final emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                  if (!emailRegExp.hasMatch(text)) {
                    return appLocalizations.xboardEmailInvalid;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<bool>(
                valueListenable: _obscurePassword,
                builder: (_, obscure, _) {
                  return TextFormField(
                    controller: _passwordController,
                    obscureText: obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => isLoading ? null : _login(),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.password),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          _obscurePassword.value = !obscure;
                        },
                      ),
                      labelText: appLocalizations.xboardPassword,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return appLocalizations.xboardPasswordNull;
                      }
                      return null;
                    },
                  );
                },
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: isLoading ? null : _login,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(appLocalizations.xboardLogin),
              ),
              const SizedBox(height: 12),
              Text(
                appLocalizations.xboardLoginHint,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotice(
    BuildContext context, {
    required IconData icon,
    required String message,
    bool isError = false,
  }) {
    final color = isError
        ? context.colorScheme.error
        : context.colorScheme.primary;
    return CommonCard(
      type: CommonCardType.filled,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: context.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetail(BuildContext context, XBoardAccountState state) {
    final account = state.account;
    final userInfo = state.userInfo;
    if (account == null) {
      // 理论不可达：已登录但无账号元数据。
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildNotice(
            context,
            icon: Icons.info_outline,
            message: appLocalizations.xboardNotLoggedIn,
          ),
        ],
      );
    }

    final errorMessage = state.errorMessage;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (errorMessage != null) ...[
          _buildNotice(
            context,
            icon: Icons.error_outline,
            message: errorMessage,
            isError: true,
          ),
          const SizedBox(height: 12),
        ],
        CommonCard(
          type: CommonCardType.filled,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  child: Text(
                    account.label.isEmpty
                        ? 'X'
                        : account.label.substring(0, 1).toUpperCase(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.email,
                        style: context.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${appLocalizations.xboardStatus}: ${appLocalizations.xboardSignedIn}',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (state.isSyncing)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (userInfo != null) ...[
          _buildTrafficCard(context, userInfo),
          const SizedBox(height: 12),
          _buildInfoCard(context, account, userInfo),
        ] else
          _buildInfoCard(context, account, null),
        const SizedBox(height: 12),
        _buildActions(context, state),
      ],
    );
  }

  Widget _buildTrafficCard(BuildContext context, XBoardUserInfo userInfo) {
    final used = userInfo.usedTraffic;
    final total = userInfo.totalTraffic;
    final hasTotal = total > 0;
    final progress = hasTotal ? (used / total).clamp(0.0, 1.0) : 0.0;
    final remaining = userInfo.remainingTraffic;

    return CommonCard(
      type: CommonCardType.filled,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appLocalizations.xboardTrafficUsage,
              style: context.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Container(
                height: 6,
                width: double.infinity,
                color: context.colorScheme.primary.opacity15,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Container(color: context.colorScheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _TrafficLabel(
                  label: appLocalizations.xboardTrafficUsage,
                  value: '${_formatTraffic(used)} / ${_formatTraffic(total)}',
                ),
                if (remaining != null)
                  _TrafficLabel(
                    label: appLocalizations.xboardTrafficRemaining,
                    value: userInfo.hasUnlimitedTraffic
                        ? '∞'
                        : _formatTraffic(remaining),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context,
    Account account,
    XBoardUserInfo? userInfo,
  ) {
    final appController = globalState.appController;
    final profileId = account.profileId;
    final profile = profileId == null
        ? null
        : appController.ref.read(profilesProvider).getProfile(profileId);

    return CommonCard(
      type: CommonCardType.filled,
      child: Column(
        children: [
          if (userInfo?.planName != null)
            _InfoRow(
              label: appLocalizations.xboardPlan,
              value: userInfo!.planName!,
            ),
          _InfoRow(
            label: appLocalizations.xboardExpireAt,
            value: userInfo == null
                ? appLocalizations.noInfo
                : _formatExpire(userInfo.expireAt),
          ),
          _InfoRow(
            label: appLocalizations.xboardLastSync,
            value: account.lastSyncTime == null
                ? appLocalizations.noInfo
                : account.lastSyncTime!.show,
          ),
          _InfoRow(
            label: appLocalizations.xboardLinkedProfile,
            value: profile?.label ?? profileId ?? appLocalizations.noInfo,
          ),
          _InfoRow(
            label: appLocalizations.xboardStatus,
            value: appLocalizations.xboardSignedIn,
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, XBoardAccountState state) {
    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: state.isSyncing
              ? null
              : () async {
                  final success = await ref
                      .read(xboardAccountProvider.notifier)
                      .syncSubscription();
                  if (success && mounted) {
                    globalState.showNotifier(
                      appLocalizations.xboardSyncSubscriptionSuccess,
                    );
                  }
                },
          icon: const Icon(Icons.sync),
          label: Text(appLocalizations.xboardSyncSubscription),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () =>
              ref.read(xboardAccountProvider.notifier).refreshUserInfo(),
          icon: const Icon(Icons.refresh),
          label: Text(appLocalizations.xboardRefreshInfo),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          label: Text(appLocalizations.xboardLogout),
        ),
      ],
    );
  }
}

class _TrafficLabel extends StatelessWidget {
  final String label;
  final String value;

  const _TrafficLabel({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: context.textTheme.bodyMedium),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style: context.textTheme.bodyMedium,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
