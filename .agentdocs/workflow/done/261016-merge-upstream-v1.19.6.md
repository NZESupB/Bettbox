# 合并上游 v1.19.6

## 目标与边界

- 基线：本项目 `9140f8b1`，上游合并基点 `c3e9f86c`（v1.19.0）。
- 目标：上游 `8ae54f3f1a6e30abfc3d5aa9d246ac31176f04d5`（v1.19.6），197 个新增提交。
- 已批准在 `merge/upstream-v1.19.6` 完成本地合并、验证、提交并快进 `main`；不推送、不打 tag、不发布。
- 保留未跟踪的 `.agents/`，不修改签名凭据和无关文件；upstream push 保持禁用。

## 实施约束与决策

- 同步上游 Flutter/Riverpod、Go core、Rust 脚本引擎和平台变更，保留 KitonyBox 品牌与 XBoard 单账号功能。
- 更新、下载、关于页和发布模板统一归属 `NZESupB/Bettbox`；产物前缀 `KitonyBox-`。
- 保留既有 UA、规则仓库和外部签名服务标识例外；Android 路径继续使用 `com/appshub/kitonybox`。
- 应用版本 `1.19.6+2026101601`；生成文件先保护再有界生成。
- 本机无 Xcode，无法完整构建 macOS/iOS；Windows/Linux 原生构建需对应环境。验证宿主 Dart/Rust/Go 与 Android 构建路径。

## 阶段与 TODO

- [x] 复核批准计划、分支、工作区和治理文档。
- [x] 无 tag 拉取 origin/upstream，创建独立合并分支。
- [x] 分析并解决合并冲突，移植 Android 路径变更。
- [x] 适配账号、导航、生命周期和生成代码。
- [x] 核验更新及发布下载链接，增加 mock 更新检查测试。
- [x] 完成 format、analyze、Flutter/Go/Rust 测试。
- [x] 完成 debug bundle 与 Android APK 构建，并记录其他平台验证边界。
- [x] 自查差异并完成归档前检查；Git 收尾按已批准方案执行本地合并提交与 main 快进。

## 冲突与兼容要点

- 179 个冲突文件；先将三方统一品牌和 Dart 格式再逐文件合并，未添加重写上游历史的中间提交。确认 227 个本地改动文件只有品牌/格式差异。
- 保留账号一级导航、Tools 搜索/设置入口、会话 Notifier、单账号订阅同步与严格 TLS/Host 兼容。
- 保留 core/provider 启动异常传播、10 秒 preload 超时、Isolate 异常捕获及桌面 Dev 数据目录规则。
- 新版底栏直接使用 PageLabel.localizedName；Windows portable 下载前缀继续使用 KitonyBox，安装器 Helper 管道与服务一致。
- Linux polkit 规则文件同步更名为 90-kitonybox.rules，与 DEB/RPM 配置一致。
- ARB 缺失的 xboardPersistFailed 从旧译文补回七种语言；intl_utils 与 build_runner 已成功重建生成文件。
- 更新请求注入 Dio/版本提供器供 mock 使用；仅接受本仓库 HTTPS Release tag 重定向。正式/预览模板各 14 条本项目直链，包含 portable 包。

## 验证记录

- 已通过：依赖解析、build_runner、intl_utils、Dart 全量格式检查、主项目 flutter analyze、运行时插件 analyze、debug bundle。
- 已通过：Go core 测试、Rust 45 项测试、Rust 格式检查、宿主 Rust release 动态库、Android arm64 Go core 交叉编译。
- 已通过：发布链接静态核验、Bash 脚本语法、macOS plist/工程文件语法、Android 包名/JNI 标识检查。
- 首次完整 Flutter 测试 532 通过/1 失败：上游进程图标占位变更未更新测试断言，已按当前行为修正。
- 第二次完整测试 532 通过/1 失败：编辑器 150ms 真实时间窗口用例受并行构建负载影响；单项复测通过，原生构建完成后将单并发完整复测。
- 最终完整 `flutter test --concurrency 1`：533/533 通过；更新检查含 18 个 mock 用例。编辑器的实时窗口代码保持与目标上游相同，未为测试改变产品逻辑。
- 已通过：Android debug APK（`--target-platform android-arm64`，719 秒）、macOS arm64 Go core、打包命令入口及打包器静态分析；9 份 YAML、CI 步骤引用和 Linux extra_files 路径检查通过。
- APK 已核验：版本名 1.19.6、版本号 2026101601、包名 com.appshub.kitonybox.debug，包含新版 libmeta/JNI/code_forge 库。
- 平台边界：未执行完整 macOS/iOS 应用构建（无 Xcode），Windows/Linux 应用原生构建未执行；无代码合并阻塞。
- 操作边界：仅本地合并与提交，不推送、不打 tag、不发布；用户未跟踪的 .agents/ 保持原样。
- git diff --check HEAD 仅报告导入上游的尾随空格/空行；vendored core/Clash.Meta 保持与目标上游完全一致，不为纯空白改动制造分叉。

