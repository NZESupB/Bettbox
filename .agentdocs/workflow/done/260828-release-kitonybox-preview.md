# KitonyBox 预览版发布

## 目标

提交并推送当前工作区的最新代码，修复品牌与 Android 包名迁移中的发布阻断问题，并通过新的 `v1.19.0-pre*` 标签触发 GitHub Actions 全平台编译。

## 关键决策

- Android `applicationId`、namespace、Kotlin/Java/JNI 包名统一为 `com.appshub.kitonyterm`。
- 对外显示品牌使用 `KitonyBox`，但 Windows/macOS/Linux 的既有可执行名、核心名、数据目录和服务标识继续使用 `Bettbox`，避免破坏桌面升级与运行时路径。
- `distribute_options.yaml` 的 `app_name` 属于桌面打包身份而非界面显示名，继续使用 `Bettbox`，避免 RPM/DMG 目录与实际可执行文件不一致。
- Action 只监听 `v*` 标签；使用未占用的新预览标签触发构建和 prerelease。

## 验收标准

- Android JNI 导出符号和 `FindClass` 路径与迁移后的 Kotlin 类一致。
- Dart 显示名为 `KitonyBox`，桌面内部标识仍为 `Bettbox`。
- `dart format`、`flutter analyze`、`flutter test` 通过。
- Android debug 构建与 arm64 JNI native 编译通过；本地 release 配置为占位密码时不得构建或发布，正式 release 由 Action 注入真实签名 Secrets 验证。
- `main` 与新预览标签均指向同一个最新提交，标签 push 成功触发 Action。

## CI 故障记录

`v1.19.0-pre3` 的 Android job 因 GitHub-hosted runner 磁盘耗尽失败，日志报错为 `No space left on device`。Android 矩阵不需要预装的多余 NDK、模拟器、.NET、Haskell 和 PowerShell，也不应恢复 Gradle、Go、Flutter 缓存；工作流在 checkout 后清理这些内容并打印剩余磁盘空间，Android job 关闭三类缓存以降低峰值占用。

之后的 Android job 编译仍失败：`Failed to apply plugin 'dev.flutter.flutter-gradle-plugin'`，报错为「项目 Kotlin 版本 (2.1.0) 低于 Flutter 最低支持 2.2.20」。根因是 `android/settings.gradle.kts` 中 `org.jetbrains.kotlin.android` 版本在提交 `f60abee` 被从 `2.2.10` 下降为 `2.1.0`，而 `android/gradle.properties` 里 `kotlin_version` 仍为 `2.2.20`，两者不一致。修复：将 `settings.gradle.kts` 的 Kotlin 版本对齐为 `2.2.20`，与 `gradle.properties` 一致。已验证 `flutter build apk --debug` 与 `flutter build apk --release --split-per-abi` 均构建通过（含 ARM64 JNI 与 proguard）。本机 Flutter 3.47.2 下 `flutter_distributor` 0.3.7 与新版 Flutter 存在 `FLUTTER_BUILD_NAME` 保留字冲突，属本地工具链版本差异，CI 的 Flutter 3.44.9 不受影响。

## TODO

- [x] 修复 Android JNI 旧包名引用。
- [x] 拆分显示品牌与桌面内部标识，修正全局包名常量。
- [x] 运行格式化、静态分析、测试和 Android 构建验证。
- [x] 提交并推送 `main`。
- [x] 创建并推送新预览标签。
- [x] 复核远端分支、标签和工作区状态。
