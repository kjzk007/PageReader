import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/services/settings.dart';
import 'package:pagereader/core/sync/paired_device.dart';

import 'sync_merger_test.dart' show FakeStore;
import 'package:pagereader/core/sync/sync_server.dart';

/// 已配对设备管理测试。
///
/// 用户要的:桌面端能看到哪些设备配对过,并且能主动断开某一台。
///
/// 关键点:token 必须**持久化**。之前放在内存 Map 里,
/// 服务一重启手机就掉了,用户每次开电脑都要重新扫码。
void main() {
  late Directory tmp;
  late SettingsStore settings;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('pr-devices-');
    settings = await SettingsStore.open(dir: tmp);
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('持久化', () {
    test('新增设备后能读回来', () async {
      final store = PairedDeviceStore(settings);
      await store.add(
        PairedDevice(
          token: 't1',
          name: 'HUAWEI GLA-AL00',
          pairedAt: DateTime(2026, 11, 19),
        ),
      );

      final all = store.load();
      expect(all, hasLength(1));
      expect(all.first.token, 't1');
      expect(all.first.name, 'HUAWEI GLA-AL00');
    });

    test('重新打开设置也能读到（模拟重启应用）', () async {
      final store1 = PairedDeviceStore(settings);
      await store1.add(
        PairedDevice(token: 't1', name: '手机', pairedAt: DateTime.now()),
      );

      // 用同一个目录重新打开
      final settings2 = await SettingsStore.open(dir: tmp);
      final store2 = PairedDeviceStore(settings2);
      expect(store2.load(), hasLength(1));
    });

    test('多台设备都记下来', () async {
      final store = PairedDeviceStore(settings);
      await store.add(
        PairedDevice(token: 't1', name: '手机A', pairedAt: DateTime.now()),
      );
      await store.add(
        PairedDevice(token: 't2', name: '手机B', pairedAt: DateTime.now()),
      );
      expect(store.load(), hasLength(2));
    });

    test('同一 token 不会重复添加', () async {
      final store = PairedDeviceStore(settings);
      final d = PairedDevice(
        token: 't1',
        name: '手机',
        pairedAt: DateTime.now(),
      );
      await store.add(d);
      await store.add(d);
      expect(store.load(), hasLength(1));
    });
  });

  group('断开配对', () {
    test('移除后清单里没有它', () async {
      final store = PairedDeviceStore(settings);
      await store.add(
        PairedDevice(token: 't1', name: '手机A', pairedAt: DateTime.now()),
      );
      await store.add(
        PairedDevice(token: 't2', name: '手机B', pairedAt: DateTime.now()),
      );

      await store.remove('t1');

      final all = store.load();
      expect(all, hasLength(1));
      expect(all.first.token, 't2');
    });

    test('移除不存在的 token 不报错', () async {
      final store = PairedDeviceStore(settings);
      await store.remove('nope');
      expect(store.load(), isEmpty);
    });

    test('移除后 contains 返回 false', () async {
      final store = PairedDeviceStore(settings);
      await store.add(
        PairedDevice(token: 't1', name: '手机', pairedAt: DateTime.now()),
      );
      expect(store.contains('t1'), isTrue);
      await store.remove('t1');
      expect(store.contains('t1'), isFalse);
    });
  });

  group('最近活跃时间', () {
    test('touch 会更新 lastSeenAt', () async {
      final store = PairedDeviceStore(settings);
      await store.add(
        PairedDevice(token: 't1', name: '手机', pairedAt: DateTime.now()),
      );
      expect(store.load().first.lastSeenAt, isNull);

      await store.touch('t1');

      expect(store.load().first.lastSeenAt, isNotNull);
    });

    test('touch 不存在的 token 不报错', () async {
      final store = PairedDeviceStore(settings);
      await store.touch('nope');
      expect(store.load(), isEmpty);
    });
  });

  group('JSON 容错', () {
    test('空设置返回空清单', () async {
      final store = PairedDeviceStore(settings);
      expect(store.load(), isEmpty);
    });

    test('损坏的 JSON 返回空清单而不崩', () async {
      await settings.writeString('sync.pairedDevices', '{{{ 坏的');
      final store = PairedDeviceStore(settings);
      expect(store.load(), isEmpty);
    });

    test('缺字段的条目被跳过', () async {
      await settings.writeString(
        'sync.pairedDevices',
        '[{"token":"ok","name":"手机","pairedAt":1},'
            '{"name":"没 token"},{}]',
      );
      final store = PairedDeviceStore(settings);
      final all = store.load();
      expect(all, hasLength(1));
      expect(all.first.token, 'ok');
    });
  });

  group('服务端集成', () {
    test('配对后能看到设备', () async {
      final deviceStore = PairedDeviceStore(settings);
      final server = SyncServer(
        store: FakeStore(),
        devices: deviceStore,
      );
      await server.start();
      final code = server.pairingCode;

      // 模拟手机配对
      final client = HttpClient();
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:${server.port}/pair'),
      );
      req.headers.contentType = ContentType.json;
      req.write('{"code":"$code","deviceName":"HUAWEI GLA-AL00"}');
      final res = await req.close();
      final body = await res.transform(
        const SystemEncoding().decoder,
      ).join();
      client.close();
      expect(body, contains('"ok":true'));

      final devices = server.pairedDevices;
      expect(devices, hasLength(1));
      expect(devices.first.name, 'HUAWEI GLA-AL00');

      await server.stop();
    });

    test('断开后 token 失效', () async {
      final deviceStore = PairedDeviceStore(settings);
      final server = SyncServer(
        store: FakeStore(),
        devices: deviceStore,
      );
      await server.start();

      // 直接塞一个已配对设备
      await deviceStore.add(
        PairedDevice(
          token: 'abc',
          name: '手机',
          pairedAt: DateTime.now(),
        ),
      );

      await server.unpair('abc');

      expect(server.pairedDevices, isEmpty);

      await server.stop();
    });

    test('停止服务不清空设备', () async {
      final deviceStore = PairedDeviceStore(settings);
      final server = SyncServer(
        store: FakeStore(),
        devices: deviceStore,
      );
      await server.start();
      await deviceStore.add(
        PairedDevice(token: 'abc', name: '手机', pairedAt: DateTime.now()),
      );

      await server.stop();

      expect(
        deviceStore.load(),
        hasLength(1),
        reason: '重启服务后手机应该还能用,不用重新扫码',
      );
    });
  });
}
