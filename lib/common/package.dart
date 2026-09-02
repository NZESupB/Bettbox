import 'package:package_info_plus/package_info_plus.dart';

extension PackageInfoExtension on PackageInfo {
  // 机场依赖该 UA 识别客户端，刻意保留上游 Bettbox 标识，不随品牌改名。
  String get ua => ['FlClash/ClashMetaForAndroid/2.11.33.Bettbox'].join(' ');
}
