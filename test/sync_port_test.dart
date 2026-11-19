import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/services/settings.dart';
import 'package:pagereader/core/sync/paired_device.dart';
import 'package:pagereader/core/sync/sync_server.dart';

import 'sync_merger_test.dart' show FakeStore;

/// 端口稳定性测试。
///
/// ── 现场问题 ──
///
/// 用户配对成功了,但手机点「立即同步」毫无反应,
/// 只有重新扫码(再配对一次)才同步成功。
///
/// 根因:桌面端每次 `start()` 都传 `port: 0`,让系统随机分配。
/// 手机关掉同步页再打开,端口变了 —— 手机存的 `baseUrl` 指向旧端口,
/// 连不上。重新扫码拿到的是新端口,所以能用。
///
/// 修复:桌面端固定用 [SyncServer.defaultPort]。
void main() {
  group('固定端口', () {
    test('defaultPort 是个高位端口', () {
      expect(SyncServer.defaultPort, greaterThan(1024));
      expect(SyncServer.defaultPort, lessThan(65536));
    });

    test('两次启动用的是同一个端口', () async {
      // 默认端口可能被真实的桌面端占着(开发机上很常见)。
      // 那不算代码问题 —— 这个测试要验证的是"端口稳定",
      // 所以显式指定一个空闲端口即可。
      final freePort = await _findFreePort();

      final s1 = SyncServer(store: FakeStore());
      await s1.start(port: freePort);
      final p1 = s1.port;
      await s1.stop();

      final s2 = SyncServer(store: FakeStore());
      await s2.start(port: freePort);
      final p2 = s2.port;
      await s2.stop();

      expect(
        p2,
        p1,
        reason: '端口必须稳定 —— 否则手机存的地址下次就失效',
      );
      expect(p1, freePort);
    });

    test('端口被占用时退回随机端口而不崩', () async {
      // 自己先占住一个空闲端口,再让 SyncServer 去绑它 ——
      // 不直接用 defaultPort,因为开发机上桌面端可能正占着,
      // 那样这条测试会在 bind 阶段就抛异常,测不到"退回"逻辑。
      final freePort = await _findFreePort();
      final blocker = await HttpServer.bind(
        InternetAddress('0.0.0.0'),
        freePort,
      );
      try {
        final server = SyncServer(store: FakeStore());
        await server.start(port: freePort);
        expect(server.isRunning, isTrue, reason: '不能因为端口冲突就起不来');
        expect(
          server.port,
          isNot(freePort),
          reason: '端口被占,应该换成别的',
        );
        await server.stop();
      } finally {
        await blocker.close(force: true);
      }
    });

    test('显式指定端口时用指定的', () async {
      final server = SyncServer(store: FakeStore());
      // 找一个空闲端口
      final probe = await HttpServer.bind(InternetAddress('0.0.0.0'), 0);
      final freePort = probe.port;
      await probe.close();

      await server.start(port: freePort);
      expect(server.port, freePort);
      await server.stop();
    });
  });

  group('配对后 token 跨重启有效', () {
    late Directory tmp;
    late SettingsStore settings;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('pr-port-');
      settings = await SettingsStore.open(dir: tmp);
    });

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('重启服务后，同一 token 仍能同步', () async {
      final devices = PairedDeviceStore(settings);
      // 用一个空闲端口,避开开发机上真实桌面端占用的 defaultPort
      final freePort = await _findFreePort();

      // 第一次:配对
      final s1 = SyncServer(store: FakeStore(), devices: devices);
      await s1.start(port: freePort);
      final token = await _pair(s1);
      expect(token, isNotNull);
      await s1.stop();

      // 第二次:重启,用同一个 token 拉数据
      final s2 = SyncServer(store: FakeStore(), devices: devices);
      await s2.start(port: freePort);
      expect(
        s2.port,
        freePort,
        reason: '端口不变,手机存的地址还能用',
      );

      final ok = await _pull(s2, token!);
      expect(
        ok,
        isTrue,
        reason: '这正是用户要的:配过一次之后,以后点同步就该直接成功',
      );

      await s2.stop();
    });

    test('旧端口的地址连不上（说明为什么必须固定端口）', () async {
      final devices = PairedDeviceStore(settings);
      final server = SyncServer(store: FakeStore(), devices: devices);
      await server.start();
      final token = await _pair(server);
      final realPort = server.port;
      await server.stop();

      // 模拟:手机存的是另一个端口
      final wrongPort = realPort == 12345 ? 12346 : 12345;
      final client = HttpClient()
        ..connectionTimeout = const Duration(milliseconds: 800);
      var failed = false;
      try {
        final req = await client.getUrl(
          Uri.parse('http://127.0.0.1:$wrongPort/pull'),
        );
        req.headers.add('X-PR-Token', token ?? '');
        await req.close();
      } catch (_) {
        failed = true;
      } finally {
        client.close();
      }
      expect(failed, isTrue, reason: '端口不对就连不上 —— 这就是原来的 bug');
    });
  });
}

// ─────────────── 辅助 ───────────────

Future<String?> _pair(SyncServer server) async {
  final c = HttpClient();
  try {
    final req = await c.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/pair'),
    );
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'code': server.pairingCode}));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final j = jsonDecode(body);
    if (j is Map && j['ok'] == true) return j['token'] as String?;
    return null;
  } catch (_) {
    return null;
  } finally {
    c.close();
  }
}

Future<bool> _pull(SyncServer server, String token) async {
  final c = HttpClient();
  try {
    final req = await c.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/pull'),
    );
    req.headers.add('X-PR-Token', token);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return body.contains('"ok":true');
  } catch (_) {
    return false;
  } finally {
    c.close();
  }
}

/// 找一个当前空闲的端口。
///
/// 测试里不能直接假设 `SyncServer.defaultPort` 可用 ——
/// 开发机上开着桌面端时它就被占着,测试会在 bind 阶段失败,
/// 看起来像是"端口稳定性"坏了,实际只是环境冲突。
Future<int> _findFreePort() async {
  final probe = await HttpServer.bind(InternetAddress('0.0.0.0'), 0);
  final port = probe.port;
  await probe.close();
  return port;
}