import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/anchor_script.dart';
import 'package:pagereader/engine/android/webview_engine.dart';

/// 两端注入脚本的完整性检查。
///
/// 桌面端(CDP)和 Android 端(WebView)用的是**不同**的注入包:
///   * 桌面:anchorBootstrapScript + positionReportScript
///   * Android:bridge + theme + gesture + anchor + positionReport
///
/// 两套都必须是合法 JS —— 一旦语法错误,注入会静默失败,
/// 表现就是"进度完全不记录",而且很难定位。
void main() {
  group('桌面端注入脚本', () {
    test('包含锚点采集与恢复', () {
      expect(anchorBootstrapScript.contains('function collect'), isTrue);
      expect(anchorBootstrapScript.contains('function pickAnchor'), isTrue);
      expect(anchorBootstrapScript.contains('function restore'), isTrue);
    });

    test('包含位置上报', () {
      expect(positionReportScript.contains('__prReport'), isTrue);
      expect(positionReportScript.contains('scroll'), isTrue);
    });

    test('能被 node 解析', () async {
      final f = File('${Directory.systemTemp.path}/desk_bundle.js');
      f.writeAsStringSync('$anchorBootstrapScript\n$positionReportScript');
      final r = await Process.run('node', ['--check', f.path]);
      expect(r.exitCode, 0, reason: '桌面端脚本语法错误:${r.stderr}');
      f.deleteSync();
    });
  });

  group('Android 注入脚本', () {
    test('五个组成部分都在', () {
      final b = WebViewEngine.debugBundle;
      expect(b.contains('__prBridgeInstalled'), isTrue, reason: '缺上报桥');
      expect(b.contains('__prGestureInstalled'), isTrue, reason: '缺手势检测');
      expect(b.contains('PRReport.postMessage'), isTrue, reason: '缺上报通道');
      expect(b.contains('PRGesture.postMessage'), isTrue, reason: '缺手势通道');
      expect(b.contains('function collect'), isTrue, reason: '缺锚点采集');
    });

    test('能被 node 解析', () async {
      final f = File('${Directory.systemTemp.path}/android_bundle.js');
      f.writeAsStringSync(WebViewEngine.debugBundle);
      final r = await Process.run('node', ['--check', f.path]);
      expect(r.exitCode, 0, reason: 'Android 端脚本语法错误:${r.stderr}');
      f.deleteSync();
    });
  });
}
