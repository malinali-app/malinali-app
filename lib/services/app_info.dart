import 'package:package_info_plus/package_info_plus.dart';

class AppInfo {
  static String version = '';
  static String buildNumber = '';

  static Future<void> init() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      version = packageInfo.version;
      buildNumber = packageInfo.buildNumber;
    } catch (e) {
      // Fallback to pubspec default if failed
    }
  }
}
