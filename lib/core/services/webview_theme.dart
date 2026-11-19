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

  /// 给指定 WebView 注册文档开始前脚本。
  ///
  /// [dark] 决定向站点报告 dark 还是 light。
  /// 返回是否注册成功;失败时页面会保持站点默认主题(通常是浅色)。
  static Future<bool> apply(
    PlatformWebViewController controller, {
    required bool dark,
  }) async {
    if (!Platform.isAndroid) return false;
    if (controller is! AndroidWebViewController) return false;
    try {
      final id = controller.webViewIdentifier;
      return await _channel.invokeMethod<bool>('setThemeMode', {
            'webViewId': id,
            'dark': dark,
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
