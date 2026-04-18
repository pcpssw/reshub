import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

String get baseUrl => AppConfig.baseUrl;

class AppConfig {
  static const String lanIP = "203.158.223.154";
  static const String project = "reshub";

  static const bool useEmulator =
      bool.fromEnvironment('USE_EMULATOR', defaultValue: false);

  static String get baseUrl {
    if (kIsWeb) {
      return "http://$lanIP/$project";
    }

    if (useEmulator) {
      if (Platform.isAndroid) return "http://$lanIP/$project";
      if (Platform.isIOS) return "http://$lanIP/$project";
    }

    // มือถือจริง / APK
    return "http://$lanIP/$project";
  }

  static String url(String path) {
    final p = path.startsWith('/') ? path.substring(1) : path;
    return "$baseUrl/$p";
  }
}