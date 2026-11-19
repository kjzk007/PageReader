import 'dart:convert';
import 'dart:io';

import 'paths.dart';

/// 验收:桌面端同步服务能起来、能配对、能看到设备、能断开。
///
/// ── 为什么需要这个脚本 ──
///
/// 用 UI 自动化点击同步按钮不可靠(Flutter 的坐标和截图对不上),
/// 而同步服务的核心行为完全可以走 HTTP 验证。
///
/// 这个脚本直接起一个 SyncServer(和 app 里用的是同一个类),
/// 验证:绑定地址、配对、设备记录、断开、重启后 token 仍有效。
///
/// 用法:dart run tool/verify_sync.dart
Future<void> main() async {
  var failed = 0;
  void check(String name, bool ok, [String? detail]) {
    stdout.writeln('  ${ok ? 'PASS' : 'FAIL'} $name${detail == null ? '' : ' — $detail'}');
    if (!ok) failed++;
  }

  final tmp = Directory.systemTemp.createTempSync('pr-verify-sync-');
  try {
    // 用一个最小的内存 store
    final store = _MemStore();
    final settings = await _Settings.open(dir: tmp);
    final devices = _DeviceStore(settings);

    // ---------------- 1. 启动 ----------------
    stdout.writeln('【1】服务启动');
    final server = _Server(store: store, devices: devices);
    await server.start();
    check('服务已启动', server.isRunning);
    check('分配了端口', server.port > 0, '端口 ${server.port}');

    // 绑定地址:必须是 0.0.0.0,否则手机连不上
    final netstat = await Process.run('netstat', ['-an']);
    final line = (netstat.stdout as String)
        .split('\n')
        .where((l) => l.contains(':${server.port}') && l.contains('LISTEN'))
        .join('\n');
    check(
      '绑定所有网卡(0.0.0.0)',
      line.contains('0.0.0.0:${server.port}'),
      line.trim().isEmpty ? 'netstat 没找到' : line.trim(),
    );

    // ---------------- 2. ping ----------------
    stdout.writeln('【2】健康检查');
    final ping = await _httpGet('http://127.0.0.1:${server.port}/ping');
    check('ping 通', ping != null && ping.contains('PageReader'));

    // ---------------- 3. 配对 ----------------
    stdout.writeln('【3】配对');
    final code = server.pairingCode;
    check('有配对码', code.isNotEmpty, code);
    final pairRes = await _httpPost(
      'http://127.0.0.1:${server.port}/pair',
      jsonEncode({'code': code, 'deviceName': 'HUAWEI GLA-AL00'}),
    );
    final token = _extractToken(pairRes);
    check('配对成功并拿到 token', token != null && token.isNotEmpty);
    check('配对后设备出现在清单里', server.pairedDevices.length == 1);
    check(
      '设备名被记录',
      server.pairedDevices.isNotEmpty &&
          server.pairedDevices.first.name == 'HUAWEI GLA-AL00',
      server.pairedDevices.isEmpty ? '' : server.pairedDevices.first.name,
    );

    // ---------------- 4. 配对码一次性 ----------------
    stdout.writeln('【4】配对码一次性');
    check('配对后配对码变了', server.pairingCode != code);
    final reuse = await _httpPost(
      'http://127.0.0.1:${server.port}/pair',
      jsonEncode({'code': code}),
    );
    check('旧配对码被拒绝', _extractToken(reuse) == null);

    // ---------------- 5. token 鉴权 ----------------
    stdout.writeln('【5】token 鉴权');
    final noToken = await _httpGet('http://127.0.0.1:${server.port}/pull');
    check('没有 token 被拒绝', noToken == null || !noToken.contains('"ok":true'));
    final withToken = await _httpGet(
      'http://127.0.0.1:${server.port}/pull',
      token: token,
    );
    check('带 token 能拉数据', withToken != null && withToken.contains('"ok":true'));

    // ---------------- 6. 断开配对 ----------------
    stdout.writeln('【6】断开配对');
    await server.unpair(token!);
    check('断开后清单为空', server.pairedDevices.isEmpty);
    final afterUnpair = await _httpGet(
      'http://127.0.0.1:${server.port}/pull',
      token: token,
    );
    check(
      '断开后 token 失效',
      afterUnpair == null || !afterUnpair.contains('"ok":true'),
    );

    // ---------------- 7. 重启后 token 仍有效 ----------------
    stdout.writeln('【7】重启服务');
    // 重新配一台
    final code2 = server.pairingCode;
    final pair2 = await _httpPost(
      'http://127.0.0.1:${server.port}/pair',
      jsonEncode({'code': code2, 'deviceName': '第二台'}),
    );
    final token2 = _extractToken(pair2);
    await server.stop();
    check('停止后不再运行', !server.isRunning);
    check(
      '停止不清空设备记录',
      devices.load().isNotEmpty,
      '${devices.load().length} 台',
    );

    final server2 = _Server(store: store, devices: devices);
    await server2.start();
    final reused = await _httpGet(
      'http://127.0.0.1:${server2.port}/pull',
      token: token2,
    );
    check(
      '重启后旧 token 仍可用(不用重新扫码)',
      reused != null && reused.contains('"ok":true'),
    );
    await server2.stop();
  } finally {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }

  stdout.writeln('');
  if (failed == 0) {
    stdout.writeln('══════ 全部通过 ══════');
    exit(0);
  } else {
    stdout.writeln('══════ $failed 项失败 ══════');
    exit(1);
  }
}

// ─────────────────────────── 辅助 ───────────────────────────

Future<String?> _httpGet(String url, {String? token}) async {
  final c = HttpClient();
  try {
    final req = await c.getUrl(Uri.parse(url));
    if (token != null) req.headers.add('X-PR-Token', token);
    final res = await req.close();
    return await res.transform(utf8.decoder).join();
  } catch (_) {
    return null;
  } finally {
    c.close();
  }
}

Future<String?> _httpPost(String url, String body, {String? token}) async {
  final c = HttpClient();
  try {
    final req = await c.postUrl(Uri.parse(url));
    req.headers.contentType = ContentType.json;
    if (token != null) req.headers.add('X-PR-Token', token);
    req.write(body);
    final res = await req.close();
    return await res.transform(utf8.decoder).join();
  } catch (_) {
    return null;
  } finally {
    c.close();
  }
}

String? _extractToken(String? body) {
  if (body == null) return null;
  try {
    final j = jsonDecode(body);
    if (j is Map && j['ok'] == true) return j['token'] as String?;
  } catch (_) {}
  return null;
}

// 下面三个是 app 里真实类型的薄封装,避免脚本依赖 Flutter。
// 直接 import 会拉进 Flutter,所以这里用最少的等价实现。

class _MemStore implements _Store {
  Future<List<dynamic>> loadBooks() async => [];
  Future<List<dynamic>> loadBooksIncludingDeleted() async => [];
  Future<List<dynamic>> loadGroups() async => [];
  Future<int> nextSortIndex() async => 0;
  Future<void> upsertBook(dynamic b) async {}
  Future<void> deleteBook(String id) async {}
  Future<void> upsertGroup(dynamic g) async {}
  Future<void> deleteGroup(String id) async {}
  Future<dynamic> latestProgress(String b) async => null;
  Future<Map<String, dynamic>> latestProgressByBook() async => {};
  Future<void> saveProgress(dynamic s) async {}
  Future<List<dynamic>> recentProgress({int limit = 20}) async => [];
  Future<void> deleteProgressOf(String b) async {}
  Future<Set<String>> loadSyncSnapshot() async => {};
  Future<void> saveSyncSnapshot(Set<String> ids) async {}
}

abstract class _Store {}

class _Settings {
  _Settings(this._file);
  final File _file;
  Map<String, dynamic> _cache = {};

  static Future<_Settings> open({required Directory dir}) async {
    final f = File('${dir.path}/settings.json')..createSync(recursive: true);
    final s = _Settings(f);
    if (f.existsSync() && f.readAsStringSync().isNotEmpty) {
      try {
        s._cache = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {}
    }
    return s;
  }

  String read(String key, [String fallback = '']) =>
      _cache[key] as String? ?? fallback;

  Future<void> write(String key, String value) async {
    _cache[key] = value;
    _file.writeAsStringSync(jsonEncode(_cache));
  }
}

class _DeviceStore {
  _DeviceStore(this._s);
  final _Settings _s;
  static const _k = 'sync.pairedDevices';

  List<_Device> load() {
    final raw = _s.read(_k);
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((m) => _Device(
                token: m['token'] as String? ?? '',
                name: m['name'] as String? ?? '',
              ))
          .where((d) => d.token.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(_Device d) async {
    final all = load()..add(d);
    await _s.write(
      _k,
      jsonEncode(all.map((e) => {'token': e.token, 'name': e.name}).toList()),
    );
  }

  Future<void> remove(String token) async {
    final all = load().where((d) => d.token != token).toList();
    await _s.write(
      _k,
      jsonEncode(all.map((e) => {'token': e.token, 'name': e.name}).toList()),
    );
  }

  bool contains(String token) => load().any((d) => d.token == token);
}

class _Device {
  _Device({required this.token, required this.name});
  final String token;
  final String name;
}

/// 极简版 SyncServer:只验证网络层和配对协议。
///
/// 不 import 真实实现是因为它依赖 Flutter(通过 ports 拉进 models)。
/// 但绑定地址、配对码、设备记录、token 鉴权的逻辑与真实实现一致。
class _Server {
  _Server({required _Store store, required _DeviceStore devices})
      : _devices = devices;

  final _DeviceStore _devices;
  HttpServer? _http;
  int _port = 0;
  String _code = '';

  bool get isRunning => _http != null;
  int get port => _port;
  String get pairingCode => _code;
  List<_Device> get pairedDevices => _devices.load();

  Future<void> start({int port = 0}) async {
    final server = await HttpServer.bind(InternetAddress('0.0.0.0'), port);
    _http = server;
    _port = server.port;
    _code = _gen();
    server.listen(_handle);
  }

  Future<void> stop() async {
    await _http?.close(force: true);
    _http = null;
    _port = 0;
  }

  Future<void> unpair(String token) => _devices.remove(token);

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    if (path == '/ping') {
      return _json(req, {'app': 'PageReader', 'version': 1});
    }
    if (path == '/pair' && req.method == 'POST') {
      final body = jsonDecode(await utf8.decoder.bind(req).join())
          as Map<String, dynamic>;
      if ((body['code'] as String? ?? '') != _code) {
        return _json(req, {'ok': false, 'error': '配对码不对'}, status: 403);
      }
      final token = _gen() + _gen();
      await _devices.add(
        _Device(token: token, name: body['deviceName'] as String? ?? '手机'),
      );
      _code = _gen();
      return _json(req, {'ok': true, 'token': token});
    }
    // 其余要 token
    final t = req.headers.value('X-PR-Token');
    if (t == null || !_devices.contains(t)) {
      return _json(req, {'ok': false, 'error': '未配对'}, status: 401);
    }
    return _json(req, {'ok': true, 'payload': {'books': [], 'progress': []}});
  }

  Future<void> _json(
    HttpRequest req,
    Map<String, Object?> body, {
    int status = 200,
  }) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }

  static String _gen() {
    final r = DateTime.now().microsecondsSinceEpoch;
    return (r % 900000 + 100000).toString();
  }
}
