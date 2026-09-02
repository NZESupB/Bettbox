# 代理文档索引

## 项目概览

当前项目是基于 Flutter、Riverpod 和 Mihomo 内核的多平台代理客户端。应用配置与 Profile 由现有配置状态管理，网络请求主要使用 Dio；目前没有面向 XBoard/V2Board 的业务认证模块。

## 前端文档

暂无独立前端架构文档。修改 Flutter 界面时应优先遵循现有 `CommonScaffold`、`AdaptiveSheetScaffold`、`ListItem`、`CommonCard` 和 Riverpod provider 模式，并通过 ARB 文件维护国际化。

## 后端文档

本项目没有自建后端。外部面板接口约束记录在当前任务文档中；任何 XBoard/V2Board 接入都必须把面板 API 当作不稳定的外部依赖处理。

## 当前任务文档

`workflow/260828-xboard-account-management.md` - 基于 XBoard/V2Board 面板的账号管理与登录功能开发规划、接口核验结果、安全边界和验收标准。

## 全局重要记忆

- `lib/common/http.dart` 的全局证书回调当前会接受任意证书；新增外部账号 API 前必须评估并收窄 TLS 信任范围，不能把该行为当作安全默认值。XBoard API 客户端已按此要求使用严格证书校验（`badCertificateCallback = null`）。
- `SharedPreferences` 中的配置和 Profile 文件可能包含密码、订阅 token、Clash secret 等敏感信息；账号凭据与会话 token 不应直接写入现有明文配置 JSON。
- XBoard/V2Board 的 HTTP 200 不代表业务成功，必须同时判断响应体中的 `status`、`message`、`data` 和 `error`，并区分 401/403、422、网络错误和面板 HTML fallback。
- 面板账号模块（`lib/providers/account.dart`、`lib/services/xboard/`、`lib/services/credentials/`）为固定面板 `kt.114432.xyz` 单账号设计；登录后自动导入/更新关联 Profile（固定 id `xboard_default`）。会话 token 经 `CredentialStore`（SharedPreferences XOR 混淆，受限降级）保存，账号元数据（脱敏邮箱）单独存 `xboard_account` key，与全局配置 JSON 解耦。
- 新模型与 Provider 采用手写实现（不引入 freezed/build_runner 生成步骤）；ARB 新增 key 后需同时更新 `lib/l10n/l10n.dart` 与 `lib/l10n/intl/messages_*.dart`（intl_utils 生成器不可用时的临时方案）。
- `AppController.updateProfile` 只有在 `profile.id == currentProfileId` 时才会 `applyProfileDebounce` 下发内核；任何“自动创建/导入并设为当前”的流程必须先设置 `currentProfileIdProvider`，再调用 `updateProfile`，并在下载/校验失败时撤销该占位，避免当前 Profile 悬空。
- `CredentialStore.saveSession/deleteSession` 与 `SharedPreferences.setString/remove` 均返回是否成功；账号模块的登录/登出必须检查返回值，持久化失败时不得宣称登录成功或已登出，否则会出现“登录后静默掉线”“登出后账号复活”。
- `XBoardUserInfo.remainingTraffic` 的语义：`null` = 面板未返回（未知，UI 不展示该行），`-1` = 面板显式声明无限制（展示 `∞`），其余为字节数；不得把缺失或 0 折叠成“无限”。
- `lib/common/mixin.dart` 的 `AutoDisposeNotifierMixin` 只定义了 `.value` 的 **setter**（`set value(T v)` 内部转 `state = v`），**没有 getter**。因此对任何使用了该 mixin 的 Notifier（如 `currentProfileIdProvider`），只能 `notifier.value = x` 写入，**读取必须用 `.state`**（Riverpod 基类），写成 `notifier.value == x` 会触发 `undefined_getter`。这是 2026-08-28 修复 [account.dart](lib/providers/account.dart#L356) 时发现的坑。
- **品牌与包名（2026-08-29 全量改版，对外发布级）**：全平台已彻底改名为 `KitonyBox`，**不再存在 `Bettbox` 内部标识**。统一为：Dart 包名 `kitony_box`；Android/macOS/Linux 应用 ID `com.appshub.kitonybox`；可执行名 `KitonyBox`/`KitonyBox.exe`；核心 `KitonyBoxCore`（dev 为 `KitonyBoxDevCore`）；Windows 服务 `KitonyBoxHelperService`、管道 `\\.\pipe\KitonyBox.Helper`、注册表 `Software\KitonyBox`；Linux 配置目录 `~/.config/kitonybox` 与 `KitonyBox.desktop`；URL scheme `kitonybox`；脚本兼容标记 `Compatible_With_KitonyBox`（**只认新标记，旧脚本失效**）。所有品牌标识统一由 `lib/common/identity.dart` 的 `AppIdentity` 派生，新增标识必须走该类而不是硬编码。
- **改名的三个例外，改动品牌时不得替换**：① `.github/workflows/build.yaml` 的 `project-slug: 'Bettbox'` 是外部签名服务标识；② `windows/packaging/exe/inno_setup.iss` 的卸载清理**有意同时匹配新旧品牌**，用于清理从 Bettbox 升级上来的用户残留；③ 默认 User-Agent 的 `.Bettbox` 后缀（机场识别依据，见下文 UA 条目）。（原第 ① 条「GitHub 仓库 URL 一律保持 `appshubcc/Bettbox`」已于 2026-09-02 撤销，见下文仓库归属条目。）
- **仓库归属：本项目所有自指 URL 都是 `NZESupB/Bettbox`（2026-09-02 用户决定，撤销原改名例外①）**。已改：`lib/common/constant.dart` 的 `repository` 常量（`lib/common/request.dart` 的 `checkForUpdate` 由它拼 `releases/latest`，现在读的是本仓库自己的最新 release）、`lib/views/about.dart` 的 Github Releases 链接（已改为 `'https://github.com/$repository'`，**不要再硬编码，统一从 `repository` 派生**）、7 个 README 的徽章/Releases/contributors 链接、2 个 issue 模板、`.github/release_template*.md` 的 15 条下载直链。**仍然指向 appshubcc 且属于故意保留的**：`appshubcc/bett-rules`（上游自有的 geox 规则仓库，`lib/models/clash_config.dart` 与 `lib/views/resources.dart`，跟随上游）、`windows/packaging/exe/make_config.yaml` 的 `publisher: appshub.cc` + `publisher_url`（发行方组织身份，成对保留）、`linux/packaging/{deb,rpm}` 的 `appshubcc@gmail.com`（打包者邮箱）、`lib/views/about.dart` 的两个 Telegram 链接（`appshub_chat`/`appshub_channel`，上游社区，release 正文里已删但 about 页保留）。
- **改名的已知代价（用户已确认接受，不做数据迁移）**：桌面端老用户升级后被视为全新应用，配置与订阅不迁移；Android 从 `com.appshub.bettbox` / `com.appshub.kitonyterm` 均无法覆盖升级。
- Android release 用正式 keystore（`android/app/keystore.jks`，已被 gitignore 忽略），密码从 gitignored 的 `android/local.properties` 读取（`storePassword`/`keyAlias`/`keyPassword`）。该文件不在 git 跟踪范围内，**全量改名没有波及它**，其中的占位密码需在正式构建前替换；本地 release 配置为占位密码时不得构建或发布，正式 release 由 Action 注入真实签名 Secrets。
- 本机构建 Android 需显式 `export JAVA_HOME=/opt/homebrew/opt/openjdk@17`，否则 Gradle 报 `Unable to locate a Java Runtime`。
- **XBoard 登录凭据的语义（2026-08-29 修复"登录后立刻失效"）**：`POST /passport/auth/login` 返回的 `token` 是**订阅 token**（上游 `AuthService::generateAuthData()` 里的 `$user->token`），**不是**认证凭据；`auth_data` 才是，且上游已把它拼成 `'Bearer ' . <sanctum token>`，**本身就是完整的 `Authorization` 头值**。因此客户端必须原样透传 `auth_data`，既不能改用 `token`，也不能再补 `Bearer ` 前缀（会变成 `Bearer Bearer ...`）。旧代码两者都踩了，导致登录后紧接着的 `/user/info`、`/user/getSubscribe` 全部 403 → `_handleSessionExpired()` 删除刚存下的 session。旧版 V2Board 的 `auth_data` 是原始凭据串、中间件同样原样读 header，所以"原样透传"对新旧版本都成立，不需要分支。
- `AuthSession` 持久化字段为 `authorization`（完整头值），不再有 `token`/`authData`。改名后旧 session JSON 解码得到空值 → `decode` 返回 null → 状态落到 `sessionExpired` 并保留账号元数据引导重新登录；旧 session 存的本就是错误凭据，**刻意不做迁移**，让失效自然收敛到既有路径。
- **PKCS12 keystore 不支持独立的 key 密码**：`keytool -genkeypair -storetype PKCS12` 会打印"正在忽略用户指定的 -keypass 值"，实际 key 密码等于 store 密码。所以 PKCS12 场景下 `local.properties` / CI Secrets 的 `keyPassword` 必须与 `storePassword` 一致；只有 JKS 格式才能两者不同。
- **CI 的 Android keystore 由 `.github/workflows/build.yaml` 的 `Setup Keystore (Android)` 从 `secrets.KEYSTORE`（base64）解码生成**，仓库里的 `android/app/keystore.jks` 被 gitignore、不会进 CI。该步骤已排在 `Setup Java (Android)` 之后并当场用 JDK API（`KeyStore.load` + `getEntry`，与 AGP 完全同路径）校验，失败立即报错；**不要用 `keytool` CLI 校验**，它对 PKCS12 会在 `-keypass` 失败时回退到 store 密码，检不出 key 密码错误。校验失败时按文件头分流提示：`30 82`/`fe ed fe ed` 开头说明文件合法、是密码/alias 问题，否则是 KEYSTORE secret 内容本身不对。
- **XBoard `/user/info` 不返回已用流量**：上游 `UserController::info` 的 `select()` 只有 email、transfer_enable、expired_at、plan_id 等，**没有 `u`/`d`，也没有 `plan` 详情**；这些只有 `/user/getSubscribe` 返回。`XBoardApiClient.getUserInfo()` 因此合并两个接口的响应（`{...info, ...subscribe}`），只读 `/user/info` 会让已用流量恒为 0、套餐名恒为空。订阅接口业务失败时降级为只用 `/user/info`，但认证失效必须继续上抛。
- **全局 `HttpOverrides` 会给所有 `HttpClient()` 装上代理**：`lib/common/http.dart` 的 `KitonyBoxHttpOverrides` 把 `findProxy` 改成核心运行时走 `PROXY localhost:mixedPort`。面板账号 API 属于控制面流量，必须能在没有可用代理时工作（登录才能拿到订阅），因此 `XBoardApiClient` 显式 `client.findProxy = (_) => 'DIRECT'`。否则登录成功后导入订阅、配置刚下发的瞬间代理状态翻转，后续请求突然改走代理而握手失败。**新建任何"必须与隧道状态无关"的 HTTP 客户端时都要显式设 findProxy**。
- **XBoard API 的 Android TLS 兼容边界**：canonical API 仍是 `https://pair_1.114432.xyz/api/v1`，但该 host 含下划线，Android/BoringSSL 不接受其与 `*.114432.xyz` 的通配符 hostname 匹配。默认 `XBoardApiClient` 必须用 `XBoardPanel.apiTransportBaseUrl`（`kt.114432.xyz`）完成严格 TLS 校验，再用 `Host: pair_1.114432.xyz` 路由 API；不得改回直接对 `pair_1` 握手，也不得设置 `badCertificateCallback = true`。自定义 `baseUrl` 默认不注入固定 Host，兼容层不得扩散到全局网络层或 Mihomo core；服务端提供合法 API 域名后优先移除该兼容。
- **诊断 DioException 必须读 `e.error`**：`DioExceptionType.unknown` 时 `response`/`statusCode` 都是 null，只打印 statusCode 会得到毫无信息的 `http error null`。`XBoardApiClient._describeTransportError` 的做法：`SocketException`/`TlsException` 可安全打印全文（只含 host/端口/系统错误），其它内层异常只打印 `runtimeType`——解析异常的 `toString()` 可能带响应片段，而登录响应里含 token。
- **`PageLabel` 没有生成的枚举映射表**：它在 `lib/models/generated/` 里只作为字段类型出现，没有 `_$PageLabelEnumMap`（`AppState` 只有 `part freezed.dart`，没有 `fromJson`）。因此**给 `PageLabel` 增删成员不需要跑 build_runner**。新增一级栏目的完整链路：`enum.dart` 的 `PageLabel` + `PageLabelExtension.localizedName` → `lib/common/navigation.dart` 的 `getItems()` 注册 `NavigationItem` → 页面自带 `CommonScaffold`（参照 `ProfilesView`）。导航项无持久化配置，不会因旧配置而不显示；但 Android TV 有白名单（`lib/providers/state.dart` 的 `currentNavigationItemsState`，只留 dashboard/proxies/profiles/tools），所以 TV 上新栏目不出现，Tools 设置里的入口需要保留。
- **本机 `dart run build_runner build -d` 会卡死且先删后建**：`-d` 先删除全部生成产物（`lib/models/generated/**`、`lib/providers/generated/*.g.dart`），本机实测它随后 0% CPU 空转不产出，导致项目无法编译。**生成文件是入库跟踪的**，恢复方式：`git ls-files --deleted` 列出被删文件后 `git checkout --` 精确恢复（**切勿 `git checkout -- .`，会连同未提交的改动一起覆盖**）。改动若不涉及新增 freezed 字段/JSON 枚举，优先直接从 git 恢复而不是重跑生成器。
- **发布 tag 与 `pubspec.yaml` 的 `version` 必须同步**：CI 由 `v*` tag 触发（`.github/workflows/build.yaml`），但产物文件名取自 `pubspec.yaml`（`flutter_distributor` 的 `{{build_name}}` = version 的 `+` 前半段），而 `.github/release_template*.md` 的下载链接按 tag 名拼 `vVERSION/KitonyBox-VERSION-*`。两者不一致会让 release 页所有下载链接 404。同时 `lib/common/request.dart` 的更新检查用 `compareVersions(远端tag, packageInfo.version)`，tag 高于内置版本会导致用户永久收到更新提示且点击下载失败。改 tag 前先改 pubspec。
- **release 模板的 owner 必须是发布仓库（2026-09-02 修正 v1.19.1 全链接 404）**：`.github/release_template*.md` 的 15 条下载直链只能指向 `NZESupB/Bettbox`——产物由本仓库的 Action 上传，指向上游 `appshubcc/Bettbox` 会让 release 页全部 404（版本号对齐也救不了）。模板已移除「Telegram 社区交流」与「Feedback / 问题反馈」两个区块（均属上游社区/仓库），**从上游合并 `.github/release_template*.md` 时必须重新剔除**。改动后的自检姿势：照 `build.yaml` 的 `Patch release.md` 跑同一条 `sed`（先 `BASE_VERSION` 后 `VERSION`），再对生成的每条 URL `curl -r 0-0` 看是否 206。
- **上游同步的固定姿势（2026-09-02 合并 v1.19.0 时定型）**：`upstream` remote 指向 `appshubcc/Bettbox`，其 push 地址被刻意设为 `DISABLED_UPSTREAM_PUSH_FORBIDDEN`，禁止对上游做任何写操作；合并一律在 `merge/upstream-<版本>` 分支上做，验证通过后再并入 `main`。**判断某个冲突文件能否直接取上游的可靠手法**：把本地版本反向去品牌（`KitonyBox→Bettbox` 等）后与合并基点 `diff -w -B`，若只剩换行重排则说明本地无实质改动，可安全 `git show upstream/main:<file>` 覆盖再正向改名。本 fork 对全部 Dart 文件跑 `dart format` 而上游不跑，**每次合并都必然产生一批纯重排冲突**，这是既有取舍，不要为消除它而放弃格式化要求。
- **`IPINFO_TOKEN` 是编译期注入**：`lib/common/constant.dart` 的 `ipInfoToken = String.fromEnvironment('IPINFO_TOKEN')` 需要 `--dart-define=IPINFO_TOKEN=...`；不配置时 IP 探测自动跳过 ipinfo.io 源，降级到 myip.la / ipip.net / cdn-cgi/trace，功能不阻塞。
- **默认 User-Agent 刻意保留 `Bettbox`，是改名的第 4 个例外**：`lib/common/package.dart` 的 `ua` 与 `core/Clash.Meta/config/config.go` 的 `GlobalUA` 必须同为 `FlClash/ClashMetaForAndroid/<内核版本>.Bettbox`。该 UA 经 `lib/common/request.dart` 落到订阅下载的 `HttpClient.userAgent`，**机场依赖它识别客户端**，改名会影响识别结果；两处不一致会让内核直连的规则/代理提供者与 App 自身请求呈现不同身份。跟随上游值还顺带避免了改动 `core/Clash.Meta` 带来的永久合并冲突点。
