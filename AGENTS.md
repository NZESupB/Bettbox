# KitonyBox 代理开发约束

## 文档读取

- 开始跨模块或涉及长期约束的任务前，先阅读 `.agentdocs/index.md`，再按索引读取相关文档。
- 复杂任务应在 `.agentdocs/workflow/` 建立任务文档，记录阶段、TODO、关键决策与验收标准；完成后更新 TODO 并按索引规则归档。
- 文档、代码注释和与用户沟通默认使用中文，代码标识符及必要专业名词保留英文。

## Flutter/Dart 质量要求

- 只修改需求涉及的文件，优先复用已有 Riverpod、Widget、Model 和网络层模式。
- 修改 Dart 文件后运行 `dart format --set-exit-if-changed lib test`；仅格式化实际受影响范围也可以，但提交前必须保证全量检查通过。
- 运行 `flutter analyze`，不得新增 analyzer 或 lint 错误。
- 运行 `flutter test`；新增功能必须补充对应单元测试，涉及状态流转时补 provider/controller 测试，涉及关键交互时补 widget 测试。
- 使用 Freezed、JSON Serializable 或 Riverpod Generator 时，运行 `dart run build_runner build -d`，并检查生成文件与源模型一致。
- 网络集成测试使用本地 `HttpServer` 或 mock adapter，不得依赖真实用户凭据、生产面板或产生远端写操作。
- 涉及平台插件、持久化、网络认证或启动流程时，除单元测试外至少抽样验证一个桌面平台和一个移动平台的构建或运行路径。

## 敏感数据

- 密码、认证 token、订阅 token、完整订阅 URL 和密钥不得写入日志、测试快照或普通明文配置。
- 外部 API 必须校验 HTTPS、响应类型、重定向目标与业务状态；不得依赖全局忽略证书错误作为正常工作条件。

## 本地构建环境（本机）

本机 Flutter SDK 与 Android Java 不在默认 `PATH`，构建前需显式设置或写入 shell 配置：

```bash
export PATH="/Users/nzesupb/Public/FlutterSDK/flutter/bin:$PATH"          # flutter/dart
export ANDROID_HOME=/Users/nzesupb/Library/Android/sdk
export ANDROID_SDK_ROOT=/Users/nzesupb/Library/Android/sdk
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home   # Homebrew openjdk@17
```

- `flutter` 当前为 3.47.2 stable；Android 项目的 Kotlin 已对齐为 `2.2.20`（`android/settings.gradle.kts` 与 `android/gradle.properties` 一致）。Gradle(8.14)/AGP(8.12.2) 仍低于新版 Flutter 最低支持，Android 构建需追加 `--android-skip-build-dependency-validation`。
- Android 构建（Android 单包注意）：全平台 debug `flutter build apk --debug`；release 用 `flutter build apk --release`（自动用正式 keystore）。本机无 Xcode，macOS/iOS 不能在本机构建；iOS 目录未生成。

### Android 签名（release）

- 正式 keystore：`android/app/keystore.jks`（已提交路径，但文件已被 gitignore 忽略、不入库）。
- 密码从 `android/local.properties` 读取（该文件已被 gitignore 忽略）：`storePassword` / `keyAlias` / `keyPassword` 三键。**构建 release 前必须用真实密码替换占位密码 `kitonybox_release_pw`**，替换后建议重新生成或妥善保管，切勿提交。
- `android/app/build.gradle.kts` 中 `isRelease` 判断 `keystore.jks` 存在且三键齐全，才走 `release` signingConfig，否则回退 debug 签名（仅本地验证用，不可发布）。
- 包名/namespace 为 `com.appshub.kitonybox`（app 与 core 两个模块），显示名为 `KitonyBox`；`com.appshub.kitonybox` 已作废。**Android 升级要求同包名+同签名**，改包名后旧包无法覆盖升级。
