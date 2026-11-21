import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// 让 WebView 的深色渲染跟随 app 内的主题设置。
///
/// ── 关键:必须在「文档开始之前」注入 ──
///
/// MDN 这类站点在解析 HTML 时就会根据 `prefers-color-scheme` 决定初始主题,
/// 把结果写进 `html[data-theme]` 和随后的 CSS。等 `onPageStarted`
/// (webview_flutter 能提供的最早时机)再注入,样式已经算完 ——
/// 覆写 matchMedia 不会触发重算,页面保持浅色。
///
/// 桌面端能生效,是因为用了 CDP 的 `Page.addScriptToEvaluateOnNewDocument`。
/// 手机上要复刻这个行为,只能用 `WebViewCompat.addDocumentStartJavaScript`
/// (androidx.webkit 1.9.0+),它在每次文档创建时、任何站点脚本之前执行。
/// 原生实现见 MainActivity.applyDocumentStart。
///
/// ── 试过但不可行的路(避免以后重走) ──
///
/// 1. 覆盖 Activity 的 uiMode(`applyOverrideConfiguration`)
///    必然崩溃:`getResources() has already been called`。
/// 2. `WebSettingsCompat.setAlgorithmicDarkeningAllowed`
///    返回 true 但无效 —— 华为 ROM 的 `HwForceDarkModeConfig` 覆盖了它。
/// 3. 在 `onPageStarted` 里 `runJavaScript` 覆写 matchMedia
///    时机太晚,站点样式已算完。
class WebViewTheme {
  const WebViewTheme._();

  static const _channel = MethodChannel('com.pagereader/theme');

  /// 设备是否支持文档开始前注入。
  static Future<bool> isSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'isDocumentStartSupported',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 一次完整的注入能力体检，供设置页展示。
  ///
  /// 光知道「支持/不支持」不够 —— 用户拿到 APK 之后要能自己判断
  /// 「我这款手机到底行不行」，所以连 WebView 版本一起报出来。
  static Future<InjectionCapability> probe() async {
    if (!Platform.isAndroid) {
      return const InjectionCapability(
        isAndroid: false,
        documentStart: false,
        webViewPackage: '',
        webViewVersion: '',
      );
    }
    var supported = false;
    try {
      supported =
          await _channel.invokeMethod<bool>('isDocumentStartSupported') ??
          false;
    } catch (_) {}

    var pkg = '';
    var ver = '';
    try {
      final info = await _channel.invokeMethod<Map<Object?, Object?>>(
        'webViewPackage',
      );
      pkg = (info?['package'] as String?) ?? '';
      ver = (info?['version'] as String?) ?? '';
    } catch (_) {}

    return InjectionCapability(
      isAndroid: true,
      documentStart: supported,
      webViewPackage: pkg,
      webViewVersion: ver,
    );
  }

  /// 给指定 WebView 注册「文档开始前执行」的脚本。
  ///
  /// [script] 由调用方拼好（预设 + 引擎全文），原生侧只负责执行时机。
  /// 返回是否注册成功；false 表示这台设备不支持 document-start，
  /// 调用方应该退回「页面加载完再注入」。
  static Future<bool> applyScript(
    PlatformWebViewController controller, {
    required String script,
  }) async {
    if (!Platform.isAndroid) return false;
    if (controller is! AndroidWebViewController) return false;
    try {
      final id = controller.webViewIdentifier;
      return await _channel.invokeMethod<bool>('addScript', {
            'webViewId': id,
            'script': script,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 把 Flutter 的 ThemeMode 解析成"当前是不是深色"。
  ///
  /// system 时看系统当前值。
  static bool resolveDark(ThemeMode mode, Brightness platformBrightness) {
    switch (mode) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return platformBrightness == Brightness.dark;
    }
  }
}

/// 注入能力体检结果。
class InjectionCapability {
  const InjectionCapability({
    required this.isAndroid,
    required this.documentStart,
    required this.webViewPackage,
    required this.webViewVersion,
  });

  final bool isAndroid;

  /// 是否支持在文档开始前注入脚本。
  ///
  /// 支持 → 深色主题在第一帧就生效，不闪。
  /// 不支持 → 只能等页面加载完再注入，会先看到原色闪一下。
  final bool documentStart;

  final String webViewPackage;
  final String webViewVersion;

  /// 给用户看的一句话结论。
  String get summary {
    if (!isAndroid) return '仅 Android 需要此项检查';
    if (documentStart) {
      return '支持 document-start 注入 —— 主题设置会立即生效，不闪';
    }
    return '不支持 document-start 注入 —— 主题设置会先闪一下原色再生效';
  }
}
