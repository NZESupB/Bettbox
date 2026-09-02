# KitonyBox 全量改名（含内部标识）

## 目标

把上一轮仅限「Android 包名 + 对外显示名」的改名，扩展为全平台彻底改名：桌面端内部标识、Dart 包名、Android 包名与类名、打包产物名、README 与 release 模板全部迁移到 KitonyBox。

## 用户已确认的决策

- 桌面端（macOS/Windows/Linux）**彻底改名，含内部标识**：Bundle ID、可执行名、核心进程名、Windows 服务名与管道名、注册表键、Linux 配置目录、`.desktop` 文件名、打包产物名全部迁移。
  - 已知代价：macOS/Windows/Linux 老用户升级后被视为全新应用，配置与订阅数据不迁移。用户接受，不额外编写数据迁移逻辑。
- Android 包名从 `com.appshub.kitonyterm` 修正为 `com.appshub.kitonybox`，Kotlin 类名同步改为 `KitonyBox*`。
  - 已知代价：已安装 `kitonyterm` 预览版的用户无法覆盖升级。
- 脚本兼容标记 `Compatible_With_Bettbox` → `Compatible_With_KitonyBox`，**只支持新标记**，存量用户脚本失效。
- Telegram 徽章文案、机场优惠码、AUR 包名全部同步改名（`KitonyBox-Chat`/`KitonyBox-Channel`、`kitonybox68`、`kitonybox-bin`、`kitonybox-compatible-bin`）。

## 必须保持不变的外部资源

- ~~**GitHub 仓库名仍是 `appshubcc/Bettbox`**（用户确认未在 GitHub 上重命名）。`repository` 常量、更新检查 URL 前缀、about 页链接、README 徽章 URL、issue 模板链接中的 `appshubcc/Bettbox` 一律不得替换。~~
  - **2026-09-02 本条已被用户整条撤销**：`repository` 常量、about 页链接、7 个 README、2 个 issue 模板、release 模板下载直链全部改为 `NZESupB/Bettbox`。仍保留 appshubcc 的只有上游规则仓库 `appshubcc/bett-rules`、Windows `publisher`/`publisher_url`、Linux 打包者邮箱。详见 `260902-merge-upstream-v1.19.0.md` 的「仓库归属收敛」。
- CI 签名服务的 `project-slug: 'Bettbox'` 属外部服务标识，用户未要求改动，保持。
- Telegram 实际跳转链接 `appshub_chat` / `appshub_channel` 不含品牌名，无需改动。
  - 2026-09-02 修正：release 模板中的 Telegram 区块已整体移除（上游社区，与本 fork 无关）。

## 命名映射（替换顺序：先长后短）

| 原 | 新 |
|---|---|
| `kitonyterm` / `KitonyTerm` | `kitonybox` / `KitonyBox` |
| `bett_box` | `kitony_box` |
| `Bettbox` / `BettBox` | `KitonyBox` |
| `BETTBOX` | `KITONYBOX` |
| `bettbox` | `kitonybox` |

替换后必须回滚 `appshubcc/KitonyBox` → `appshubcc/Bettbox`、`project-slug: 'KitonyBox'` → `'Bettbox'`。

## 阶段与 TODO

- [x] 阶段 1：Dart 层 —— `AppIdentity` 常量、pubspec 包名 `bett_box` → `kitony_box`、163 个文件的 `package:` import、硬编码文案与内部标识
- [x] 阶段 2：Android —— 包名目录 `kitonyterm` → `kitonybox`、Kotlin 类重命名、AndroidManifest、`core.cpp` JNI 符号与 FindClass 路径、gradle、strings.xml
- [x] 阶段 3：macOS —— xcconfig（PRODUCT_NAME / Bundle ID）、Info.plist、MainMenu.xib customModule、xcscheme、pbxproj、dmg 打包配置
- [x] 阶段 4：Windows —— CMakeLists、runner（注册表键、窗口类名、Runner.rc）、inno_setup.iss、package_windows.dart、make_config.yaml
- [x] 阶段 5：Linux —— CMakeLists（BINARY_NAME / APPLICATION_ID）、my_application.cc（配置目录、.desktop、control.sock）、deb/rpm/appimage 配置
- [x] 阶段 6：构建与发布层 —— `setup.dart`、`distribute_options.yaml`、`Makefile`、`.github/workflows/build.yaml`、release 模板、issue 模板
- [x] 阶段 7：文档 —— README.md 与 `readme/` 六个语言版本、`AGENTS.md`
- [x] 阶段 8：回滚保护项（`appshubcc/Bettbox`、`project-slug`），验证 `dart format` / `flutter analyze` / `flutter test`，以及 Android debug 构建

## 验证结果

- `flutter pub get`、`dart format`、`flutter analyze`（No issues found）、`flutter test`（35 passed）全部通过。
- `flutter build apk --debug` 通过（含 code_forge 四架构 JNI 编译）。本机需显式设置 `JAVA_HOME=/opt/homebrew/opt/openjdk@17`，否则 Gradle 报 `Unable to locate a Java Runtime`。
- macOS / Windows / Linux+CI 三份独立核验均确认无重命名引入的语义断裂：macOS Swift module 名由 `PRODUCT_NAME` 派生，与 MainMenu.xib 的 `customModule="KitonyBox"` 一致；Windows `KITONYBOX_DEV` 宏定义与全部 `#ifdef` 使用处成对改动，Rust helper 的服务名/管道名与 Dart `WindowsHelperIdentity` 字面一致；Linux `.desktop` 候选首项 `KitonyBox.desktop` 与 deb/rpm/appimage 实际产物一致。

## 有意保留的旧品牌（唯一残留）

`windows/packaging/exe/inno_setup.iss` 的卸载清理逻辑同时匹配新旧品牌：网络适配器清理（原逻辑本就在清理 `LiClash` 等历史品牌）、注册表键 `Software\com.appshub.bettbox`、用户数据目录 `%appdata%\com.appshub.bettbox`。从 Bettbox 升级上来的用户卸载时才能清干净。

## 遗留的既有问题（非本次改名引入，未处理）

- `windows/runner/flutter_window.cpp` 运行时写入 `HKCU\Software\KitonyBox`，而 inno_setup 卸载只清理 `Software\com.appshub.*`，两者不匹配，卸载清不掉运行时注册表数据。改名前即如此。
- `windows/packaging/exe/make_config.yaml` 的 `APP_ID` GUID `728B3532-C74B-4870-9068-BE70FE1LITES` 含非十六进制字符，不是合法 GUID。
- `linux/packaging/*/make_config.yaml` 声明的 `startup_wm_class` 未被任何 maker 写入生成的 `.desktop`。

