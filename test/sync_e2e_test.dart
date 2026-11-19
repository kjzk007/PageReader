import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/core/sync/sync_client.dart';
import 'package:pagereader/core/sync/sync_server.dart';

import 'sync_merger_test.dart' show FakeStore, book;

/// 同步服务的端到端测试。
///
/// 真的启动一个 HTTP 服务、真的走网络请求 ——
/// 只测纯函数是不够的,HTTP 层最容易出错(路径、头、JSON 编码)。
void main() {
  group('地址解析', () {
    test('自定义 scheme', () {
      final r = parseSyncTarget(
        'pagereader://pair?host=192.168.1.5&port=8080&code=123456',
      );
      expect(r?.baseUrl, 'http://192.168.1.5:8080');
      expect(r?.code, '123456');
    });

    test('http URL 带 fragment', () {
      final r = parseSyncTarget('http://192.168.1.5:9000#654321');
      expect(r?.baseUrl, 'http://192.168.1.5:9000');
      expect(r?.code, '654321');
    });

    test('手输 host:port code', () {
      final r = parseSyncTarget('192.168.1.5:8080 123456');
      expect(r?.baseUrl, 'http://192.168.1.5:8080');
      expect(r?.code, '123456');
    });

    test('只有 IP 时用默认端口', () {
      final r = parseSyncTarget('192.168.1.5');
      expect(r?.baseUrl, 'http://192.168.1.5:8080');
    });

    test('空串返回 null', () {
      expect(parseSyncTarget(''), isNull);
      expect(parseSyncTarget('   '), isNull);
    });

    test('乱写返回 null', () {
      expect(parseSyncTarget('随便什么'), isNull);
    });
  });

  group('配对链接', () {
    test('生成的链接能被自己解析回来', () {
      final link = buildPairLink(
        host: '10.0.0.3',
        port: 8080,
        code: '112233',
      );
      final r = parseSyncTarget(link);
      expect(r?.baseUrl, 'http://10.0.0.3:8080');
      expect(r?.code, '112233');
    });
  });

  group('服务端', () {
    late SyncServer server;

    setUp(() {
      server = SyncServer(store: FakeStore());
    });

    tearDown(() async {
      await server.stop();
    });

    test('启动后能 ping 通', () async {
      await server.start();
      expect(server.isRunning, isTrue);
      expect(server.port, greaterThan(0));

      final client = SyncClient(
        store: FakeStore(),
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      expect(await client.ping(), isTrue);
    });

    test('配对码正确能换到 token', () async {
      await server.start();
      final client = SyncClient(
        store: FakeStore(),
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      expect(await client.pair(server.pairingCode), isTrue);
      expect(client.token, isNotNull);
    });

    test('配对码错误被拒绝', () async {
      await server.start();
      final client = SyncClient(
        store: FakeStore(),
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      expect(await client.pair('000000'), isFalse);
      expect(client.token, isNull);
    });

    test('配对码一次性:用过就失效', () async {
      await server.start();
      final code = server.pairingCode;
      final c1 = SyncClient(
        store: FakeStore(),
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      expect(await c1.pair(code), isTrue);

      // 同一个码再用一次应该失败。
      final c2 = SyncClient(
        store: FakeStore(),
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      expect(await c2.pair(code), isFalse);
    });

    test('没有 token 时 /pull 返回 401', () async {
      await server.start();
      final client = SyncClient(
        store: FakeStore(),
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      // 没配对就同步,应该返回 null。
      expect(await client.sync(), isNull);
    });
  });

  group('完整同步流程（镜像模式）', () {
    test('两端最终完全一致', () async {
      final desktopStore = FakeStore(
        books: [book('d1', title: '桌面书', updatedAt: DateTime(2026, 1))],
      );
      final server = SyncServer(store: desktopStore);
      await server.start();

      final phoneStore = FakeStore(
        books: [book('p1', title: '手机书', updatedAt: DateTime(2026, 2))],
      );
      final client = SyncClient(
        store: phoneStore,
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      await client.pair(server.pairingCode);
      await client.sync();

      final desktopIds =
          (await desktopStore.loadBooks()).map((b) => b.id).toSet();
      final phoneIds = (await phoneStore.loadBooks()).map((b) => b.id).toSet();
      expect(desktopIds, phoneIds, reason: '两端书架必须一模一样');
      expect(desktopIds, {'d1', 'p1'}, reason: '各自独有的书都该保留');

      await server.stop();
    });
    test('两边各删一本 → 两端都少那两本', () async {
      final desktopStore = FakeStore(
        books: [book('keep', updatedAt: DateTime(2026, 1))],
      );
      // 上次同步时两端都有 keep 和 gone1，现在 gone1 两边都没有了
      await desktopStore.saveSyncSnapshot({'keep', 'gone1'});
      final server = SyncServer(store: desktopStore);
      await server.start();

      final phoneStore = FakeStore(
        books: [book('keep', updatedAt: DateTime(2026, 1))],
      );
      await phoneStore.saveSyncSnapshot({'keep', 'gone1'});
      final client = SyncClient(
        store: phoneStore,
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      await client.pair(server.pairingCode);
      await client.sync();

      expect(
        (await desktopStore.loadBooks()).map((b) => b.id).toSet(),
        {'keep'},
      );
      expect(
        (await phoneStore.loadBooks()).map((b) => b.id).toSet(),
        {'keep'},
      );

      await server.stop();
    });

    test('手机端删得更晚 → 桌面端也删', () async {
      final desktopStore = FakeStore(
        books: [
          book('a', updatedAt: DateTime(2026, 1)),
          book('b', updatedAt: DateTime(2026, 1)),
        ],
      );
      // 上次同步时两端都有这两本。这次手机端清单为空 = 删光了。
      await desktopStore.saveSyncSnapshot({'a', 'b'});
      final server = SyncServer(store: desktopStore);
      await server.start();

      final phoneStore = FakeStore();
      final client = SyncClient(
        store: phoneStore,
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      await client.pair(server.pairingCode);
      await client.sync();

      expect(
        await desktopStore.loadBooks(),
        isEmpty,
        reason: '手机端清单为空 = 删光了,桌面端也该删',
      );

      await server.stop();
    });
    test('两端一致后再同步不重复写', () async {
      final desktopStore = FakeStore(books: [book('a')]);
      final server = SyncServer(store: desktopStore);
      await server.start();

      final phoneStore = FakeStore(books: [book('a')]);
      final client = SyncClient(
        store: phoneStore,
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      await client.pair(server.pairingCode);

      await client.sync();
      await client.sync();
      await client.sync();

      expect(await phoneStore.loadBooks(), hasLength(1));
      expect(await desktopStore.loadBooks(), hasLength(1));

      await server.stop();
    });

    test('进度也一起镜像', () async {
      final desktopStore = FakeStore(books: [book('a')]);
      await desktopStore.saveProgress(
        ProgressSnapshot(
          bookId: 'a',
          url: 'old',
          pageTitle: '桌面旧位置',
          updatedAt: DateTime(2026, 1),
          deviceId: 'desktop',
        ),
      );
      final server = SyncServer(store: desktopStore);
      await server.start();

      final phoneStore = FakeStore(books: [book('a')]);
      await phoneStore.saveProgress(
        ProgressSnapshot(
          bookId: 'a',
          url: 'new',
          pageTitle: '手机新位置',
          anchor: const Anchor(
            cssPath: 'x',
            textFingerprint: 'y',
            textLength: 1,
            offsetPx: 100,
            docRatio: 0.75,
          ),
          updatedAt: DateTime(2026, 6),
          deviceId: 'phone',
        ),
      );

      final client = SyncClient(
        store: phoneStore,
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      await client.pair(server.pairingCode);
      await client.sync();

      final p = await desktopStore.latestProgress('a');
      expect(p?.url, 'new', reason: '手机为准，进度也该是手机的');

      await server.stop();
    });
  });
}
