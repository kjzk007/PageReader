import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/diagnostics.dart';
import 'package:pagereader/engine/desktop/browser_locator.dart';
import 'package:pagereader/engine/desktop/cdp_engine.dart';

/// 诊断数据模型的语义测试。
///
/// 面板本身是纯展示,真正要保证的是 healthy 的判断逻辑正确 ——
/// 否则出问题时用户看着面板也查不出原因。
void main() {
  group('healthy 判定', () {
    DiagnosticsSnapshot make({
      bool running = true,
      int? port = 9222,
      int reports = 0,
      String? error,
      Set<String> degraded = const {},
    }) => DiagnosticsSnapshot(
      engineRunning: running,
      browserPath: 'msedge.exe',
      profilePath: '/tmp/p',
      port: port,
      pageCount: 1,
      pageUrls: const ['https://a.dev/x'],
      mappedBooks: const {'b1': 't1'},
      lastReportAt: reports > 0 ? DateTime(2026, 1, 1) : null,
      lastReportReason: reports > 0 ? 'scroll' : null,
      reportCount: reports,
      lastError: error,
      degradedBooks: degraded,
    );

    test('连上浏览器、无错误、无降级 → 健康', () {
      expect(make().healthy, isTrue);
    });

    test('没连上 → 不健康', () {
      expect(make(running: false, port: null).healthy, isFalse);
    });

    test('有错误 → 不健康', () {
      expect(make(error: '连接失败').healthy, isFalse);
    });

    test('有降级书 → 不健康', () {
      expect(make(degraded: {'b1'}).healthy, isFalse);
    });

    test('还没上报过也算健康(刚启动时正常)', () {
      // 刚打开应用、还没滚动过,不该显示为故障。
      expect(make(reports: 0).healthy, isTrue);
    });

    test('未启动时端口为空', () {
      expect(make(running: false, port: null).port, isNull);
    });

    test('上报次数与时间一致', () {
      final d = make(reports: 5);
      expect(d.reportCount, 5);
      expect(d.lastReportAt, isNotNull);
      expect(d.lastReportReason, 'scroll');
    });
  });

  group('降级标记', () {
    test('初始无降级', () async {
      final browser = BrowserLocator.find();
      final profile = Directory.systemTemp.createTempSync('pr-dg-');
      final engine = CdpEngine(
        browserPath: browser ?? 'none.exe',
        profileDir: profile,
        headless: true,
      );
      try {
        expect(engine.hasDegraded, isFalse);
        expect(engine.isDegraded('b1'), isFalse);
        engine.clearDegraded('b1');
        await engine.shutdown();
      } finally {
        try {
          profile.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });
}

