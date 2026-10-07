import 'dart:io';

class NetworkIdentity {
  static String get platformUserAgent {
    if (Platform.isAndroid) {
      return 'DATunes/2.0.0 (Android; Mobile)';
    } else if (Platform.isWindows) {
      return 'DATunes/2.0.0 (Windows NT; x64)';
    } else if (Platform.isLinux) {
      return 'DATunes/2.0.0 (Linux; x86_64)';
    } else if (Platform.isMacOS) {
      return 'DATunes/2.0.0 (macOS)';
    } else if (Platform.isIOS) {
      return 'DATunes/2.0.0 (iOS)';
    }
    return 'DATunes/2.0.0';
  }

  static const String lrclibUserAgent = 'DATunes/2.0.0 (https://github.com/VikrantRuhela/DA-Tunes)';
}
