# XBoard 账号管理集成规划

## 目标

在 Bettbox 中增加账号管理能力：用户输入 XBoard/V2Board 面板账号（邮箱）和密码完成登录，查看账号状态与流量信息，获取面板订阅并导入/更新为 Bettbox Profile，支持多账号保存、切换、退出和删除。

## 实施范围（用户确认后裁剪）

用户明确：**只绑定固定面板（kt.114432.xyz）、单账号、登录后自动导入订阅且支持更新**。不实现多账号列表、注册/找回密码、套餐购买等；订阅同步失败不阻断登录，保留旧 Profile。

## 实施决策（2026-08-28）

- **固定面板**：面板首页 `https://kt.114432.xyz`，API 基址 `https://pair_1.114432.xyz/api/v1`，订阅 host 白名单 `114432.xyz` 后缀。
- **单账号**：账号 id 固定为 `xboard_default`，登录自动覆盖旧会话。
- **无代码生成**：因本机无 Flutter SDK，新模型/Provider 全部手写（仿 `Traffic`/`StateProvider` 模式），不引入 freezed/build_runner；ARB 与 l10n 生成文件用脚本同步。
- **安全存储降级**：未引入 flutter_secure_storage（无法验证 pub get/构建），采用 `CredentialStore` 抽象 + SharedPreferences XOR 混淆实现；token 不落明文配置/备份，但**不是**平台级加密，未来替换实现即可升级。
- **自动导入订阅**：登录成功后自动创建/更新关联 Profile（label 取邮箱前缀），重复同步复用同一 Profile；未配置其他当前 Profile 时自动设为当前。
- **国际化**：7 个 ARB 文件新增 28 个 `xboard*` key，同步手动更新 `lib/l10n/l10n.dart` 与 `lib/l10n/intl/messages_*.dart`（生成器不可用时的临时方案，后续运行 intl_utils 可覆盖）。

## 当前状态

- Bettbox 是 Flutter 多平台客户端，根页面由 `PageLabel`、`NavigationItem` 和 Riverpod 状态组成。
- 当前没有用户账号、登录会话、Bearer/JWT、CookieJar 或 token refresh 实现。
- Profile 的订阅更新链路已经存在，但它假定输入是最终配置 URL，并直接把 URL 与订阅相关密钥写入配置/文件。
- 网络层有 Dio，但没有统一 JSON API 客户端、认证拦截器、业务响应解析或敏感日志脱敏。
- `SharedPreferences` 保存配置 JSON，现有 WebDAV 密码等敏感字段也可能明文落盘；不能直接仿照该方式保存面板密码/token。

## Android TLS 兼容修复（2026-08-30）

### 根因

- 面板公开 `config.js` 仍将 API 基址配置为 `https://pair_1.114432.xyz/api/v1`。
- API host 的首个 label 含下划线。下划线可用于 DNS label，但不符合标准 hostname 语法；Android/Dart 使用的 BoringSSL 会拒绝把通配符证书 `*.114432.xyz` 匹配到该 host，报 `CERTIFICATE_VERIFY_FAILED: Hostname mismatch`。macOS curl 当前会接受该匹配，因此问题表现存在平台差异，但 XBoard 客户端代码是各平台共享的。
- 当前证书链本身有效，证书覆盖 `*.114432.xyz` 且未过期；不能通过 `badCertificateCallback = true` 绕过校验，否则会把 hostname mismatch、伪造证书、过期证书和不受信任证书一并放行。

### 兼容策略

- canonical API 地址仍保留 `https://pair_1.114432.xyz/api/v1`，用于账号元数据与订阅 URL 语义，避免旧数据迁移和调用方行为变化。
- 实际 TLS 连接使用证书正常覆盖的面板 origin `https://kt.114432.xyz/api/v1`，请求的 HTTP `Host`/authority 仍设置为 `pair_1.114432.xyz`。2026-08-30 已用匿名公开接口分别验证 HTTP/1.1 与 HTTP/2 均能正确路由到 XBoard API。
- 该策略只封装在 `XBoardApiClient` 内；自定义 `baseUrl`（本地测试或未来其他面板适配）默认不注入固定 Host，调用方可显式提供 `requestHost`。严格系统证书校验与 `DIRECT` 控制面链路保持不变。
- 服务端若未来提供不含下划线的正式 API 域名，应优先切换 canonical API 地址并移除 Host 分离兼容；客户端兼容层不应扩散到全局网络层或 vendored Mihomo core。

### 修复验收

- [x] 匿名核验证书链、SAN、公开 `config.js` 与 Android hostname 规则差异。
- [x] 匿名验证 `kt.114432.xyz` TLS + `Host: pair_1.114432.xyz` 能访问公开 XBoard API。
- [x] XBoard 默认客户端使用合法 TLS host，并向 API 虚拟主机发送正确 Host。
- [x] 自定义 `baseUrl` 不受固定面板 Host 覆盖影响；API 重定向默认拒绝且不转发认证请求。
- [x] 通过 format、analyze、test；Android debug APK 构建成功，macOS 宿主 Dart VM 的真实匿名 TLS/API 路由验证成功。

## 目标站已核验事实

只进行了公开、无凭据、无写操作的请求：

- `https://kt.114432.xyz/` 是 EZ SPA，公开 `config.js` 声明 `PANEL_TYPE: 'Xboard'`。
- 公开配置将 API 基址设为 `https://pair_1.114432.xyz/api/v1`，而不是首页域名的 `/api/v1`。
- `GET /guest/comm/config` 和 `GET /guest/plan/fetch` 返回 JSON 成功响应。
- `GET /user/info`、`GET /user/getSubscribe` 在未登录时返回 HTTP 403，业务体为 `status: fail`。
- `GET /passport/auth/login` 返回 HTTP 405，并声明 `Allow: POST`，因此登录必须使用 POST。
- XBoard 常见登录接口为 `POST /passport/auth/login`，字段通常是 `email`、`password`；成功数据包含 `token`、`auth_data`、`is_admin`。
- **凭据语义（2026-08-29 据上游源码 `app/Services/AuthService.php` 核验）**：`generateAuthData()` 返回 `'token' => $user->token`（**订阅** token）与 `'auth_data' => 'Bearer ' . <sanctum plainTextToken>`（**认证凭据，已含前缀**）；`app/Http/Middleware/User.php` 走 `Auth::guard('sanctum')`，读标准 `Authorization` 头。因此客户端把 `auth_data` 原样作为头值即可，不得改用 `token`、不得二次拼 `Bearer `。旧版 V2Board 的 `auth_data` 为原始凭据串、中间件同样原样读 header，故"原样透传"对新旧版本一致，不需要版本分支，也不需要把 token 放进 URL/query 或请求体。

## 范围与非目标

### 首期范围（MVP）

1. 面板地址配置与 HTTPS/host 校验。
2. 邮箱密码登录、错误提示、加载状态和退出登录。
3. 会话安全保存、启动恢复、失效清理和手动刷新。
4. 用户信息、套餐/过期时间、已用/总流量展示。
5. 获取订阅 URL，并以受控方式创建或更新 Bettbox Profile。
6. 多账号列表、当前账号切换、删除本地账号。
7. 国际化、单元测试和本地 mock API 测试。

### 首期不做

- 注册、找回密码、邮箱验证码、Google/Telegram/快捷登录。
- 购买套餐、优惠券、支付、订单取消等写接口。
- 自动调用 `resetSecurity`（该接口可能重置 UUID/token，具有破坏性）。
- 让账号功能替换现有 Profile 管理；账号和 Profile 是两个不同领域对象。
- 把面板网页嵌入 WebView 作为登录方案。

## 建议架构

### 目录与职责

建议新增以下边界，具体命名可按项目既有风格调整：

```text
lib/
  models/account.dart                 # Freezed/JSON 的非敏感账号元数据
  models/auth_session.dart             # token/auth_data 的运行时与过期信息
  services/xboard/
    xboard_api_client.dart             # HTTP、业务响应、版本兼容
    xboard_auth_repository.dart        # login/logout/restore/refresh
    xboard_models.dart                 # info/subscribe/config DTO
  services/credentials/
    credential_store.dart              # 平台安全存储接口
    secure_credential_store.dart       # 实际实现与迁移
  providers/account_provider.dart      # Riverpod 状态机
  views/account/
    accounts.dart                      # 账号列表与切换
    login.dart                         # 登录表单
    account_detail.dart                 # 用户/流量/订阅详情
```

账号对象只保留 `id`、面板 origin、脱敏邮箱、显示名、最后同步时间、关联 profile id、状态等非敏感字段。密码不长期保存；会话 token/auth_data 放入 `CredentialStore`，内存中使用后及时清理。

### API 客户端原则

- 统一通过一个 XBoard 专用 Dio 实例发送 JSON 请求，设置连接/接收超时、User-Agent、HTTPS 校验和重定向策略。
- 解析 `{status,message,data,error}`，并拒绝 `text/html` 的 SPA fallback。
- 用拦截器注入 `Authorization: Bearer <token>`；如目标旧版确实要求，再按接口白名单添加 `auth_data` body，而不是全局追加。
- 绝不记录密码、完整 token、订阅 URL；错误日志只保留 host、HTTP 状态和面板 message。
- 认证错误（401/403 或业务未登录）统一转为 `SessionExpired`，网络超时、TLS、解析失败和表单校验分别建模。
- 面板 origin 与 API base URL 分离保存，并用 `Uri` 解析/规范化；只允许 `https`（开发环境是否允许 `http` 必须显式开关）。

### 会话策略

- 登录成功后保存 `auth_data`/Bearer token、面板 origin、签发/保存时间及可选服务端过期时间。
- 启动时恢复会话，但不要因为恢复失败阻塞核心代理功能；账号状态显示为“需要重新登录”。
- 首期不实现猜测式 refresh。收到认证失败时清除会话并要求重新登录；如果目标面板提供明确 refresh endpoint，再单独增加能力。
- 登出需同时清除安全存储中的会话和内存 provider 状态；是否调用远端注销接口取决于目标版本，不应伪造不存在的 endpoint。
- 多账号切换只切换当前 session，不把多个 token 混写到同一个 Profile；切换后重新拉取 info/subscribe 并更新关联 Profile。

### 订阅绑定策略

1. 登录后调用 `/user/getSubscribe`，校验 `subscribe_url`/`token` 是 HTTPS 绝对 URL，并且 host 符合面板允许范围或用户明确确认。
2. 优先使用面板返回的 Clash/Mihomo 格式 URL；若只有 token，按 XBoard 版本约定构造 URL，并在适配层集中处理 `?flag=clash` 等参数。
3. 复用 `Profile.normal` 和现有 `Profile.update`，但在接入前增加响应格式、`subscription-userinfo` 容错和重定向凭据保护。
4. 以稳定的 `accountId` 关联 Profile，重复同步时更新原 Profile，不重复创建；用户手工编辑的 Profile 不应被静默覆盖。
5. 订阅 token/URL 在 UI 只显示脱敏值，复制操作需要明确用户动作并给出敏感信息提示。

## 分阶段实施

### 阶段 0：协议冻结与风险基线（0.5~1 天）

- [x] 用匿名 mock/目标公开接口确认登录成功与失败响应的真实样本（不提交真实凭据）。
- [x] 确认部署方是否允许客户端直连 `pair_1.114432.xyz`，是否存在 API 域名变化、Cloudflare/WAF、地区限制。
- [x] 明确 V2Board 兼容范围：只支持目标 XBoard，还是支持用户自定义面板；这会决定是否需要版本探测和适配器。
- [x] 记录 TLS、日志、备份、剪贴板和崩溃报告中的敏感数据处理规则。

### 阶段 1：数据模型与安全存储（1~2 天）

- [x] 新增 `Account`、`AuthSession`、API DTO，补齐 Freezed/JSON 生成流程。
- [x] 引入并评估平台安全存储实现（Android Keystore/iOS Keychain/macOS Keychain/Windows Credential Manager/Linux Secret Service）；若依赖不可用，提供受限降级策略并明确告警。
- [ ] 设计从旧明文配置迁移的版本号、幂等迁移、失败回滚和删除旧字段流程。
- [x] 为 token 设置最小权限、内存生命周期和脱敏 `toString`；禁止把密码放进 `Account` 或普通配置 JSON。

### 阶段 2：XBoard API 适配层（1~2 天）

- [x] 实现 `POST /passport/auth/login`，严格校验邮箱和密码长度，处理 HTTP/业务错误。
- [x] 实现 `/user/info`、`/user/getSubscribe`、必要的 `/guest/comm/config`；所有响应先做 schema 容错和字段类型转换。
- [x] 认证凭据取 `auth_data` 并原样作为 `Authorization` 头值（上游已含 `Bearer ` 前缀）；`token` 只当订阅 token。**2026-08-29 修复**：原实现优先取 `token` 且额外拼 `Bearer `，导致登录后所有 `/user/*` 请求 403、会话被立即清除。
- [ ] 加入请求取消、超时、有限重试（仅网络错误，禁止重试登录和写请求）、重定向 host 校验。
- [x] 建立错误码到用户文案的映射，避免复用 Profile 导入错误文案。

### 阶段 3：Riverpod 会话状态与生命周期（1~2 天）

- [x] 新增 `AuthState`：`initial/loading/authenticated/unauthenticated/sessionExpired/error`。
- [x] 启动后异步恢复会话；应用回前台时按节流策略刷新用户信息，不阻塞 VPN/核心启动。
- [x] 登录、退出、切换、删除账号实现并发互斥，避免快速点击产生多个 token 或重复 Profile。
- [x] 统一处理 403：清除失效 session、保留非敏感账号元数据、引导重新登录。
- [x] 将账号状态持久化与现有 `GlobalState.config` 解耦，确保正常退出、崩溃和后台服务场景都不会丢状态。

### 阶段 4：UI 与 Profile 集成（2~3 天）

- [x] 在 Tools 设置分组增加”账号管理”入口；除非产品明确要求，否则不扩展一级导航 `PageLabel`。
- [x] **2026-08-29 产品明确要求**：账号已提升为一级导航栏目 `PageLabel.account`（`AccountPage` 自带 `CommonScaffold`）。Android TV 因导航白名单不显示该栏目，故 Tools 设置里的入口保留不删。
- [x] 使用 `AdaptiveSheetScaffold`/`showExtend` 实现跨桌面、移动端和 Android TV 的登录页。
- [ ] 账号列表复用 `CommonCard(isSelected)`、`ListItem`、`CommonPopupMenu`，支持当前账号、重新登录、同步订阅、删除。
- [x] 账号详情展示邮箱（脱敏）、面板、套餐、到期时间、流量进度、最后同步状态；加载/空态/错误态完整覆盖。
- [x] 登录成功提供“导入并设为当前 Profile”“仅保存账号”“稍后导入”明确选项，避免隐式改动用户代理配置。
- [x] 订阅同步失败时保留旧 Profile 可用，并显示上次成功同步时间；不删除旧配置。
- [x] 七个 ARB 文件同步增加登录、退出、会话失效、同步失败等文案，再运行生成工具。

### 阶段 5：测试、审计与发布（1~2 天）

- [x] 模型测试：JSON、可选字段、过期判断、脱敏输出和迁移兼容。
- [x] API 测试：成功/业务失败/403/422/HTML fallback/超时/错误 JSON/旧 V2Board auth_data 样本。
- [ ] provider 测试：状态转移、并发登录、切换、退出、token 失效和持久化失败。
- [ ] Widget 测试：表单校验、重复提交、错误态、账号切换和删除确认；桌面/移动布局至少覆盖窄宽度。
- [x] 本地 `HttpServer` 或 Dio adapter mock 测试，禁止测试依赖真实账号和目标站。
- [ ] 完成 `dart format`、`flutter analyze`、`flutter test`，并在可用 Flutter SDK 上执行构建矩阵抽样。
- [ ] 做一次敏感数据审计：日志、剪贴板、备份 ZIP、崩溃信息、URL 分享、代理重定向和证书校验。

## 关键验收标准

- 输入错误密码时不会保存密码/token，界面显示可理解的面板错误；快速连续点击不会发送重复登录请求。
- 重启应用后可恢复已保存会话；服务端使 token 失效后，下一次 API 调用会清理 token 并保留旧 Profile。
- 登录成功只创建一个与账号关联的 Profile；重复同步更新同一 Profile，手工 Profile 不被覆盖。
- API 返回 HTML、非 HTTPS 订阅 URL、未知字段类型或异常重定向时，应用拒绝导入并给出可操作错误。
- 全部支持平台不在普通 `SharedPreferences`/备份 JSON 中出现完整密码或 auth token。
- 关闭账号功能或 API 不可达时，原有代理、Profile、启动和更新功能保持可用。

## 待用户/产品确认（2026-08-28 已确认）

- 只绑定 `kt.114432.xyz`（含 `pair_1.114432.xyz` API 域名与 `114432.xyz` 订阅 host 白名单）。
- 单账号登录（固定 id `xboard_default`），不实现多账号列表。
- 登录成功后自动导入订阅并设为当前 Profile（未配置其他当前时）；提供手动同步按钮。
- 不实现注册、验证码、找回密码、套餐/订单/支付。
- 暂未新增平台安全存储依赖（无法验证 pub get/构建）；`CredentialStore` 用 SharedPreferences XOR 混淆实现，属受限降级，后续可无缝替换。
- 允许客户端直连 `pair_1.114432.xyz`；已核验该域名为公开配置声明的 API 基址。

## 参考代码位置

- 应用与导航：`lib/application.dart`、`lib/main.dart`、`lib/common/navigation.dart`、`lib/enum/enum.dart`。
- 网络请求：`lib/common/request.dart`、`lib/common/http.dart`。
- 配置持久化：`lib/common/preferences.dart`、`lib/state.dart`、`lib/models/config.dart`。
- Profile/订阅：`lib/models/profile.dart`、`lib/controller.dart`、`lib/views/profiles/`。
- UI 复用：`lib/widgets/list.dart`、`lib/widgets/sheet.dart`、`lib/widgets/dialog.dart`、`lib/widgets/card.dart`。
- 测试约束：`analysis_options.yaml`、`test/`、`.github/workflows/build.yaml`。
- 新增账号模块：`lib/models/account.dart`、`lib/models/auth_session.dart`、`lib/services/xboard/`、`lib/services/credentials/`、`lib/providers/account.dart`、`lib/views/account/`、`test/services/`、`test/models/account_test.dart`。
