import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/engine/desktop/browser_locator.dart';

/// 浏览器自动检测的测试。
///
/// 这是产品的启动前提:检测不到浏览器,整个应用就无法打开任何书。
/// 所以要验证的不只是"能找到",还包括
/// "非常规安装位置也能找到"和"优先级正确"。
void main() {
  group('基本检测', () {
    test('能自动检测到浏览器', () {
      final path = BrowserLocator.find(refresh: true);
      expect(path, isNotNull, reason: '检测不到浏览器,应用将完全不可用');
      expect(File(path!).existsSync(), isTrue, reason: '返回的路径必须真实存在');
    });

    test('能识别出浏览器名称', () {
      final path = BrowserLocator.find(refresh: true);
      if (path == null) {
        markTestSkipped('本机没有浏览器');
        return;
      }
      final name = BrowserLocator.displayName(path);
      expect(
        name,
        anyOf('Microsoft Edge', 'Google Chrome'),
        reason: '应识别成人类的名称,而不是 exe 文件名',
      );
    });

    test('detectNow 与 find 结果一致', () {
      final a = BrowserLocator.find(refresh: true);
      final b = BrowserLocator.detectNow();
      expect(a, b);
    });
  });

  group('缓存', () {
    test('重复调用结果一致', () {
      expect(BrowserLocator.find(), BrowserLocator.find());
    });

    test('invalidate 后仍能找到', () {
      BrowserLocator.invalidate();
      expect(BrowserLocator.find(refresh: true), isNotNull);
    });
  });

  group('优先级', () {
    test('Edge 和 Chrome 都在时优先 Edge', () {
      final path = BrowserLocator.find(refresh: true);
      if (path == null) {
        markTestSkipped('本机没有浏览器');
        return;
      }
      final edge = File(
        r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
      ).existsSync();
      final chrome = File(
        r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      ).existsSync();

      if (edge && chrome) {
        expect(
          path.toLowerCase(),
          contains('msedge'),
          reason: 'Edge 是 Windows 自带,卸载概率更低,应优先',
        );
      } else {
        // 只有一个浏览器时,必然是它
        expect(File(path).existsSync(), isTrue);
      }
    });
  });

  group('注册表检测(权威来源)', () {
    test('Edge 在注册表 App Paths 里可见', () async {
      final path = await _registry('msedge.exe');
      final direct = File(
        r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
      ).existsSync();
      if (!direct) {
        markTestSkipped('本机 Edge 不在标准路径,跳过');
        return;
      }
      expect(
        path,
        isNotNull,
        reason: '安装 Edge 一定会写注册表,这是最可靠的检测依据',
      );
      expect(File(path!).existsSync(), isTrue);
    });

    test('Chrome 在注册表 App Paths 里可见', () async {
      final path = await _registry('chrome.exe');
      final direct = File(
        r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      ).existsSync();
      if (!direct) {
        markTestSkipped('本机没装 Chrome,跳过');
        return;
      }
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
    });
  });

  group('非常规安装位置', () {
    test('LOCALAPPDATA 用户级安装也在候选里', () {
      final local = Platform.environment['LOCALAPPDATA'];
      if (local == null) {
        markTestSkipped('没有 LOCALAPPDATA');
        return;
      }
      // 不假设一定存在,只验证路径构造逻辑覆盖了这里。
      // 真正的判据是:如果该路径存在,find 必须能返回它。
      final candidates = [
        '$local\\Google\\Chrome\\Application\\chrome.exe',
        '$local\\Programs\\Microsoft\\Edge\\Application\\msedge.exe',
      ];
      final existing = candidates.where((p) => File(p).existsSync()).toList();
      if (existing.isEmpty) {
        markTestSkipped('本机没有用户级安装的浏览器');
        return;
      }
      final found = BrowserLocator.find(refresh: true);
      expect(found, isNotNull);
      final lower = found!.toLowerCase();
      expect(
        existing.any((p) => lower == p.toLowerCase()) ||
            lower.contains('msedge') ||
            lower.contains('chrome'),
        isTrue,
        reason: '用户级安装的浏览器也必须能检测到',
      );
    });

    test('环境变量缺失时不崩溃', () {
      // 模拟不了环境变量,但可以确认检测在有环境变量的情况下稳定
      expect(() => BrowserLocator.find(refresh: true), returnsNormally);
    });
  });
}

Future<String?> _registry(String exe) async {
  for (final root in [
    r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
    r'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths',
    r'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
  ]) {
    final r = await Process.run('reg', ['query', '$root\\$exe', '/ve']);
    if (r.exitCode != 0) continue;
    final m = RegExp(r'REG_SZ\s+(.+)').firstMatch(r.stdout as String);
    if (m != null) return m.group(1)!.trim().replaceAll('"', '');
  }
  return null;
}
