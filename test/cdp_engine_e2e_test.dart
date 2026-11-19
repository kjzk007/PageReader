import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/core/domain/url_normalizer.dart';
import 'package:pagereader/engine/desktop/browser_locator.dart';
import 'package:pagereader/engine/desktop/cdp_engine.dart';

/// 真浏览器联调:headless Edge + 真实站点。
/// 网络不通时自动跳过,不阻塞本地开发。
void main() {
  final browser = BrowserLocator.find();

  // 注意:「窗口最大化」不在这里测。
  // headless 模式没有真实窗口,Browser.getWindowForTarget 返回 null,
  // 无法验证 windowState。那条路径由 tool/verify_window.dart 在
  // 有界面的真实环境里验证。
  test('真浏览器:开书 → 采集 → 按比例恢复', () async {
    if (browser == null) {
      markTestSkipped('本机没有 Edge/Chrome');
      return;
    }

    final profile = Directory.systemTemp.createTempSync('pr-e2e-');
    final engine = CdpEngine(
      browserPath: browser,
      profileDir: profile,
      headless: true,
    );

    final now = DateTime.now();
    final book = Book(
      id: 'b1',
      title: 'Rust Book',
      entryUrl: 'https://doc.rust-lang.org/book/ch03-02-data-types.html',
      scopePrefix: 'https://doc.rust-lang.org/book',
      createdAt: now,
      updatedAt: now,
    );

    try {
      await engine.launch(book);
      await Future<void>.delayed(const Duration(seconds: 2));

      final first = await engine.collect('b1');
      expect(first, isNotNull, reason: '采集失败');
      expect(first!.pageTitle, contains('Data Types'));
      expect(first.anchor, isNotNull);
      expect(
        UrlNormalizer.normalize(first.url),
        'https://doc.rust-lang.org/book/ch03-02-data-types.html',
      );

      await engine.restoreAnchor(
        'b1',
        const Anchor(
          cssPath: '',
          textFingerprint: '',
          textLength: 0,
          offsetPx: 0,
          docRatio: 0.8,
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 1));

      final second = await engine.collect('b1');
      expect(second, isNotNull);
      expect(
        second!.anchor!.docRatio,
        greaterThan(0.7),
        reason: '按比例恢复后应该停在后半页',
      );

      final flushed = await engine.flushAll();
      expect(flushed.length, 1);
      expect(engine.openBooks, contains('b1'));
    } finally {
      await engine.shutdown();
      // Edge 退出后文件句柄不是立刻释放,删不掉就算了,不因此判定测试失败。
      for (var i = 0; i < 5; i++) {
        try {
          profile.deleteSync(recursive: true);
          break;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

}
