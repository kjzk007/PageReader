import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/engine/android/webview_engine.dart';

/// 站点深色主题注入脚本的测试。
///
/// 背景:之前的版本除了覆写 matchMedia,还主动改 DOM 属性
/// (data-theme / classList.add('dark')),并且 apply() 被调了四次。
/// 站点自己的主题逻辑与注入脚本反复互相覆盖,
/// 用户看到的是深浅来回闪烁。
///
/// 实测证明:只覆写 matchMedia 就够 —— 站点会自己根据查询结果选主题
/// (MDN:700ms 时背景透明,1400ms 变 rgb(24,25,27),之后一直稳定)。
///
/// 这里把"只覆写、不碰 DOM"锁死,防止以后又加回去。
void main() {
  final bundle = WebViewEngine.debugBundle;

  group('只覆写 matchMedia', () {
    test('包含 matchMedia 覆写', () {
      expect(bundle.contains('window.matchMedia ='), isTrue);
      expect(bundle.contains('prefers-color-scheme'), isTrue);
    });

    test('不主动修改 DOM 主题属性', () {
      // 这些是导致闪烁的直接原因:站点和脚本互相覆盖。
      expect(
        bundle.contains('setAttribute'),
        isFalse,
        reason: '不该主动改 data-theme 等属性 —— 站点自己会做',
      );
      expect(
        bundle.contains('classList.add'),
        isFalse,
        reason: '不该主动加 dark 类 —— 会让站点与脚本争夺控制权',
      );
      expect(bundle.contains('classList.remove'), isFalse);
    });

    test('不注入 color-scheme 覆盖', () {
      // 覆盖 color-scheme 会让 WebView 认为页面已自行处理深色,
      // 反而关掉它自己的兜底逻辑。
      expect(bundle.contains('colorScheme ='), isFalse);
    });

    test('不做全局 filter 反转', () {
      expect(bundle.contains('invert('), isFalse);
      expect(bundle.contains('hue-rotate'), isFalse);
    });
  });

  group('不重复执行', () {
    test('有幂等标记', () {
      expect(
        bundle.contains('__prMatchMediaPatched'),
        isTrue,
        reason: '重复覆写会层层包裹 matchMedia',
      );
    });

    test('不受 setTimeout 反复调用', () {
      // 之前 apply() 在 400ms / 1200ms 被再次调用,正是抖动的来源。
      expect(
        bundle.contains('setTimeout(apply'),
        isFalse,
        reason: '不该延时重复应用 —— 一次注入即可',
      );
    });

    test('不监听 DOMContentLoaded 重复应用', () {
      expect(
        bundle.contains("addEventListener('DOMContentLoaded', apply)"),
        isFalse,
      );
    });
  });

  group('system 模式不干预', () {
    test('mode 为 system 时直接返回', () {
      expect(
        bundle.contains("mode === 'system'"),
        isTrue,
        reason: '跟随系统时应完全交给系统',
      );
    });
  });

  group('语法正确', () {
    test('能被 node 解析', () async {
      final f = File('${Directory.systemTemp.path}/pr_theme_check2.js');
      f.writeAsStringSync(bundle);
      final r = await Process.run('node', ['--check', f.path]);
      expect(r.exitCode, 0, reason: '语法错误:${r.stderr}');
      f.deleteSync();
    });
  });
}
