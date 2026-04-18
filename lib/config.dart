import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

String get baseUrl => AppConfig.baseUrl;

class AppConfig {
  static const String lanIP = "15th-nreac.idt.rmutr.ac.th";
  static const String project = "reshub";

  static const bool useEmulator =
      bool.fromEnvironment('USE_EMULATOR', defaultValue: false);

  static String get baseUrl {
    if (kIsWeb) {
      return "https://$lanIP/$project/";
    }

    if (useEmulator) {
      if (Platform.isAndroid) return "https://$lanIP/$project/";
      if (Platform.isIOS) return "https://$lanIP/$project/";
    }

    // มือถือจริง / APK
    return "https://$lanIP/$project/";
  }

  static String url(String path) {
    final p = path.startsWith('/') ? path.substring(1) : path;
    return baseUrl.endsWith('/') ? "$baseUrl$p" : "$baseUrl/$p";
  }
}