import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/sync/sync_client.dart';

import 'sync_merger_test.dart' show FakeStore;

/// 同步超时的测试。
///
/// ── 现场问题 ──
///
/// 手机点了「立即同步」,界面永远停在"正在同步…",
/// 既不成功也没有任何错误提示。
///
/// 根因:`HttpClient.connectionTimeout` **只限制建立连接**。
/// 连接建立后服务端不返回数据(卡住、防火墙静默丢包),
/// `await req.close()` 会无限期挂住。
///
/// `sync()` 也没有整体超时,所以三步串行只要有一处卡住就永远不返回。
///
/// 修复:
///   * 每次请求的 `req.close()` 和读 body 都带 8 秒 timeout
///   * `sync()` 整体 25 秒超时
///   * 任何异常都返回 null,由 UI 显示"连不上电脑"
void main() {
  group('请求超时', () {
    test('服务端接受连接但不响应 → 请求超时返回 null', () async {
      // 起一个"黑洞"服务器:接受连接,永远不写响应
      final hole = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      hole.listen((s) => sockets.add(s)); // 收下就不管

      final client = SyncClient(
        store: FakeStore(),
        baseUrl: 'http://127.0.0.1:${hole.port}',
        token: 'tok',
      );

      final sw = Stopwatch()..start();
      final result = await client.sync();
      sw.stop();

      expect(result, isNull, reason: '不该返回成功');
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 30)),
        reason: '必须在合理时间内放弃,不能无限挂住',
      );

      for (final s in sockets) {
        s.destroy();
      }
      await hole.close();
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('连不上的端口 → 快速失败', () async {
      final client = SyncClient(
        store: FakeStore(),
        baseUrl: 'http://127.0.0.1:1',
        token: 'tok',
      );

      final sw = Stopwatch()..start();
      final result = await client.sync();
      sw.stop();

      expect(result, isNull);
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 10)),
        reason: '端口没人监听应该立刻失败',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('服务器返回非 JSON → 不崩,返回 null', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.statusCode = 200;
        req.response.write('<html>不是 JSON</html>');
        await req.response.close();
      });

      final client = SyncClient(
        store: FakeStore(),
        baseUrl: 'http://127.0.0.1:${server.port}',
        token: 'tok',
      );

      final result = await client.sync();
      expect(result, isNull, reason: '解析失败应当作同步失败,不能抛异常');

      await server.close(force: true);
    });

    test('服务器返回 500 → 返回 null', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.statusCode = 500;
        req.response.write('{"ok":false}');
        await req.response.close();
      });

      final client = SyncClient(
        store: FakeStore(),
        baseUrl: 'http://127.0.0.1:${server.port}',
        token: 'tok',
      );

      final result = await client.sync();
      expect(result, isNull);

      await server.close(force: true);
    });

    test('慢响应（超过超时）→ 返回 null 而不是挂住', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        // 拖 15 秒才回 —— 超过单步 8 秒超时
        await Future<void>.delayed(const Duration(seconds: 15));
        try {
          req.response.write('{"ok":true,"payload":{}}');
          await req.response.close();
        } catch (_) {
          // 客户端已经断开,写会失败,忽略
        }
      });

      final client = SyncClient(
        store: FakeStore(),
        baseUrl: 'http://127.0.0.1:${server.port}',
        token: 'tok',
      );

      final sw = Stopwatch()..start();
      final result = await client.sync();
      sw.stop();

      expect(result, isNull);
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 30)),
        reason: '整体 25 秒超时必须生效',
      );

      await server.close(force: true);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}

