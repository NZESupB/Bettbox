# 合并上游 v1.19.0（appshubcc/Bettbox → 本地 KitonyBox fork）

## 边界约束（用户明确要求）

- 上游 `appshubcc/Bettbox` **只作为代码拉取源**，禁止对其做任何修改、推送或 PR。
- 所有改动只允许发生在 `NZESupB/Bettbox`（`origin`）。
- 机制保障：`upstream` remote 的 push 地址已设为 `DISABLED_UPSTREAM_PUSH_FORBIDDEN`，任何误推会直接失败。

## 现状

- 合并基点 `714130a3`（Optimize android battery logic）。
- 上游领先 11 个提交，至 `c3e9f86c Release v1.19.0`（`1.19.0+2026090201`）。
- 本地领先 1 个提交 `95b143bc 增加机场适配`：279 文件，内容为 KitonyBox 全量改名 + XBoard 账号模块。
- 本地从未改动 `core/Clash.Meta/`，Go 侧可整体取上游。
- `git merge-tree` 预演：25 个文件冲突。

## 冲突性质分类

fork 与上游的差异**主体是改名而非功能分叉**，且两侧都跑过同版本 `dart format`，因此多数冲突是「改名 + 相同的格式重排」，可直接取上游再回填 KitonyBox 标识。

| 类别 | 文件 | 处理方式 |
| --- | --- | --- |
| 纯改名/格式冲突 | `lib/common/{request,network_matcher,preferences}.dart`、`lib/state.dart`、`lib/models/selector.dart`、`lib/pages/editor.dart`、`lib/main.dart`、`lib/views/{developer,theme}.dart`、`lib/widgets/{chip,super_grid}.dart` | 取上游，回填 `kitony_box` / `KitonyBox*` |
| 追加区冲突 | 7 个 `arb/intl_*.arb`、`lib/l10n/l10n.dart` | 上游 15 个新 key 与本地自定义 key 并存；同时删除 `lightIcon`/`lightIconDesc` |
| 真结构性冲突 | `lib/pages/home.dart` | 上游删掉 `FocusTraversalGroup` 导致整块反缩进，与本地正缩进重排反向撞车，手工取上游结构 |
| 大删除 | `linux/my_application.cc` | 上游净删 326 行（桌面图标切换下线），取上游后只回填 socket 名与窗口标题 |
| 大改 + 新功能 | `windows/runner/flutter_window.cpp` | 上游删图标切换、加旧设置一次性清理、加剪贴板 `WM_PASTE` 转发；需改 `BETTBOX_REG_KEY`→`KITONYBOX_REG_KEY`、`kFlutterWindowProp` |
| rename/delete-modify | `android/.../plugins/{AppPlugin,VpnPlugin}.kt` | 目录已从 `com.appshub.bettbox` 迁至 `com.appshub.kitonybox`，git 无法自动搬，手工移植上游 hunk |
| 取本地 | `android/app/src/debug/AndroidManifest.xml` | 上游唯一改动（`tools:replace` 加 `android:icon`）本地已提前包含 |

## 上游语义改动（需跟进的功能）

- `38946a9b` 桌面端「切换应用图标」下线，只留 Android；Win 侧保留旧注册表/快捷方式一次性清理。`ThemeProps.useDarkIcon` 字段保留。
- `902e2f89` 新增 IP 归属地信息体系：多源并发探测 + 渐进合并 + 14 天缓存 + 详情弹窗（新文件 `lib/widgets/ip_detail_dialog.dart`）；`AppState.isScreenOn` 迁到 `GlobalState`；一批 Android TV 焦点/内边距修复；JNI 判空加固。
- `16577ba8` Material3 主题细化、`generateSection` 统一包裹设置页、`AccessSortType` 枚举重构 + `AccessControl.manualList` 新字段、Preferences 解析加 try/catch。
- `bf9063f4` 智能停止规则支持 `gateway:` 前缀匹配；`protect(fd)` 最多重试 5 次；VPN 权限申请加固。
- `3340cc9a` Windows 剪贴板历史（Win+V）转发到 Dart，新增 `lib/plugins/clipboard_ext.dart`。
- `1e847f0b` `IpInfo.merge` 引入权威源概念，避免跨国/跨 IP 数据串味。
- `c5490411` 删除 `GeoXUrl.geoip` 与 `geoIpFileName`；geox 源改 GitHub Releases；资源页加「全部重置」。
- `f15242df` 文案修订（ru 大批重译）。`535f9e1d` 纯 Go 内核。`d1d17295` 仅 macOS 托盘插件。`c3e9f86c` 版本号。

## 必须成套同步的破坏性改动（漏一处就编译不过）

1. `AppState.isScreenOn` 删除 → `lib/models/app.dart` + `lib/controller.dart` + `lib/plugins/vpn.dart` + `lib/state.dart`。
2. `AccessSortType` 枚举 `name`/`time` → `installTime`/`updateTime` → `lib/enum/enum.dart` + `lib/models/config.dart`（含 `compatibleFromJson` 迁移块）+ `lib/models/selector.dart` + `lib/views/access.dart`。
3. `AccessControl.manualList` / `Package.firstInstallTime` 新增 → `lib/models/config.dart` + `lib/models/common.dart` + Kotlin `models/Package.kt` + `plugins/AppPlugin.kt`。
4. `GeoXUrl.geoip` 删除 → `lib/models/clash_config.dart` + `lib/common/constant.dart`。
5. `getLocalGateways` 新增链路 → Kotlin `VpnPlugin.kt` + `ServicePlugin.kt` + Dart `lib/plugins/{service,vpn}.dart` + `lib/main.dart`。

## 关键决策

- **不采用「先把上游整支改名再合并」的取巧路径**。那样能把冲突降到近零，但引入一个非上游的中间提交，且改名脚本与本地手工改名结果一旦不一致会埋下隐性偏差。25 个冲突有完整改动地图，手工解更可审计。
- **在独立分支上合并**（`merge/upstream-v1.19.0`），验证通过后再由用户决定是否并入 `main`，避免直接在默认分支上产生大型合并提交。
- 上游把 geox 规则源换成 `github.com/appshubcc/bett-rules/releases`，属于上游自有规则仓库，**跟随上游不做改名**。
- `ipInfoToken` 走 `--dart-define=IPINFO_TOKEN` 编译期注入，不配置时自动跳过 ipinfo.io 源，不阻塞功能；本 fork 暂不配置。
- `PackageInfoExtension.ua` **跟随上游保留 `2.11.33.Bettbox`**（用户 2026-09-02 决定）。该 UA 是机场识别客户端的依据，改名会影响识别；`core/Clash.Meta/config/config.go` 的 `GlobalUA` 同样保留上游值，因此内核代码零改动、不产生永久合并冲突点。

## 改名例外（合并时不得替换，沿用既有记忆）

1. ~~GitHub 仓库仍是 `appshubcc/Bettbox`：`repository` 常量、更新检查 URL、about 链接、README 徽章、issue 模板一律保持。~~ **2026-09-02 用户撤销此条**：本项目所有自指 URL 全部改为 `NZESupB/Bettbox`，见「仓库归属收敛」。
2. `.github/workflows/build.yaml` 的 `project-slug: 'Bettbox'` 是外部签名服务标识。
3. `windows/packaging/exe/inno_setup.iss` 的卸载清理有意同时匹配新旧品牌。
4. 默认 User-Agent 的 `.Bettbox` 后缀（本次合并新确立的例外，机场识别依据）。

## 验证结果

| 项目 | 结果 |
| --- | --- |
| `dart format --set-exit-if-changed lib test` | 通过（合并后有 26 个文件需重排，已格式化；上游未对全部文件跑新版 formatter） |
| `flutter analyze` | No issues found |
| `flutter test` | 40/40 通过 |
| `flutter build bundle --debug` | 成功（完整编译 `main.dart` 可达的全部 Dart 代码） |
| `flutter build apk --debug` | 成功（覆盖 Kotlin 插件与 JNI C++ 改动） |
| macOS/iOS 构建 | 本机无 Xcode，无法验证 |

合并提交打 tag `v1.19.1`，双亲为 `95b143bc`（本地）与 `c3e9f86c`（上游），上游祖先链完整保留，后续 `git merge upstream/main` 不会重复合入。`pubspec.yaml` 同步为 `1.19.1+2026090201`，与 tag 对齐。

## release 正文收尾（2026-09-02，用户决定）

首个 v1.19.1 release 发布后暴露的问题：`.github/release_template*.md` 的 15 条下载直链沿用上游 `appshubcc/Bettbox`，而产物只上传到 `NZESupB/Bettbox`，因此 release 页所有下载链接全部 404。这是「改名例外①（仓库 URL 保持 appshubcc）」与「fork 自行发布」两条约束首次正面冲突。

- 15 条直链的 owner 改为 `NZESupB`，文件名规则 `KitonyBox-VERSION-*` / `KitonyBox-BASE_VERSION-*` 不动（与 `pubspec.yaml` 的 `build_name` 对齐，已核验 17 个产物名匹配）。
- 移除「✈️ Telegram 社区交流」区块（`t.me/appshub_chat`、`t.me/appshub_channel` 均为上游社区）。
- 移除「🐛 Feedback / 问题反馈」区块与预览版本顶部的 `[[反馈]]` 链接（用户决定：反馈入口直接删掉，不改指本仓库）。
- 校验方式：按 `build.yaml` 的 `Patch release.md` 原样跑 `sed -e s|BASE_VERSION|..| -e s|VERSION|..|`，再对生成的 15 条 URL 逐条 `curl -r 0-0`，全部 206。
- 修复以 `git commit --amend` 并入合并提交 `dfacbba3`（双亲不变），`v1.19.1` 附注 tag 原样重打并 force-push；同时用 `gh release edit --notes-file` 立即替换已发布正文，不等 CI 重跑。

## 仓库归属收敛（2026-09-02，用户决定撤销改名例外①）

`repository` 常量指向上游会让 fork 用户在上游发新版时被引导去下载上游产物，因此把**所有自指 URL** 统一到 `NZESupB/Bettbox`：

- `lib/common/constant.dart` 的 `repository`；`lib/common/request.dart:171` 的 `checkForUpdate` 由它拼 `releases/latest`（跟 302 取 tag 名）与 `html_url`，改常量即全链路生效。
- `lib/views/about.dart` 的 Github Releases 链接改为从 `repository` 插值（`'https://github.com/$repository'`），消掉重复的硬编码 owner。
- 7 个 README（`README.md` + `readme/README_{zh,en,ja,ko,ru,fa}.md`）的 release 徽章、Releases 页链接、contributors 链接，各 3 处。
- 2 个 issue 模板的「搜索现有 Issue」链接——模板只会在本仓库的 New issue 页渲染，指向上游无论 issues 是否开启都是错的。
- 故意保留 appshubcc 的：`appshubcc/bett-rules`（上游 geox 规则仓库，跟随上游）、`make_config.yaml` 的 `publisher: appshub.cc` + `publisher_url`（发行方组织身份，成对保留）、`linux/packaging` 的打包者邮箱、`about.dart` 的两个 Telegram 链接（上游社区，用户只要求从 release 正文移除）。
- 本次改动波及运行时代码（`constant.dart` 进二进制），因此 v1.19.1 的产物必须由 CI 重新构建，不能只改 release 正文。

## 遗留与风险

- `lib/common/request.dart` 的 `queryIpDetail` 走明文 `http://ip-api.com`（上游行为）。Flutter 的 `dart:io HttpClient` 基于原始 socket，不受 Android `usesCleartextTraffic` 与 macOS ATS 约束，因此无需平台配置即可工作；但查询目标 IP 在链路上可见。该请求受全局 `HttpOverrides` 影响，内核运行时会走本地混合端口。
- `core/Clash.Meta` 保持与上游逐字节一致（UA 例外确立后已无本地改动），后续 `Update core` 可直接取上游。
- 上游 `arb/intl_ru.arb` 自身仍保留已废弃的 `lightIcon`/`lightIconDesc`（其余 6 种语言已删）；本地跟随上游不做额外清理，避免制造新的合并分歧。
- `protect(fd)` 上游改为最多 5 次、间隔 60ms 重试，最坏阻塞约 300ms，调用方是内核 JNI 回调线程。

## TODO

- [x] 添加 `upstream` remote 并禁用其 push
- [x] 拉取上游、确认差异与冲突面
- [x] 派子代理测绘上游语义改动
- [x] 测绘上游品牌标识泄漏面
- [x] 建分支并执行 `git merge upstream/main`
- [x] 解决 25 个冲突
- [x] 移植 Android 两个插件的 rename 冲突 hunk
- [x] 成套同步 5 组破坏性改动（均由 git 自动合并完成，已逐组核验）
- [x] 品牌标识清扫（含上游 4 个新文件）
- [x] 校验生成物（freezed / json_serializable）与源模型一致
- [x] `dart format` / `flutter analyze` / `flutter test` 全绿
- [x] 抽样构建验证（`build bundle` + Android APK）
- [x] 由用户决定是否将 `merge/upstream-v1.19.0` 并入 `main` 并推送 `origin`（已并入 `main`，tag `v1.19.1` 已发布）
- [x] 修正 release 模板下载直链的 owner，并移除 Telegram / 反馈区块
- [x] 逐条核验 15 条下载 URL 可用（全部 206）
- [x] amend `dfacbba3`、重打并 force-push `v1.19.1`、修正已发布 release 正文
- [x] 把 `repository` 与全部自指 URL 收敛到 `NZESupB/Bettbox`，amend 进 `e190c2b6` 后重打 tag

