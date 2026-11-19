import 'dart:convert';
import 'dart:io';

import '../ports/ports.dart';
import 'sync_mirror.dart';
import 'sync_protocol.dart';

/// 手机端的同步客户端。
///
/// 流程:
///   1. 用户扫码或手填 `IP:端口`,拿到配对码
///   2. `pair()` 用配对码换 token,存起来
///   3. 之后 `sync()` 直接用 token 走双向合并
///
/// 双向合并的顺序很重要:
///   a. 先**拉**桌面端数据,合并进本地(桌面端通常数据更全)
///   b. 再把本地数据**推**给桌面端,让它也拿到手机的更新
///
/// 为什么不是"只推不发":
/// 用户在桌面读了一半、在手机继续读 —— 两个方向都有新数据,
/// 单向同步会丢东西。
class SyncClient {
  SyncClient({
    required this.store,
    required this.baseUrl,
    this.token,
  });

  final LibraryStore store;

  /// 形如 `http://192.168.1.5:8080`。
  final String baseUrl;

  String? token;

  /// 健康检查:确认地址连得上、确实是 PageReader。
  ///
  /// 超时设短一点(3 秒):地址填错时不该让用户干等。
  Future<bool> ping() async {
    try {
      final r = await _get('/ping').timeout(const Duration(seconds: 3));
      return r['app'] == 'PageReader';
    } catch (_) {
      return false;
    }
  }

  /// 用配对码换 token。
  /// 用配对码换取长期 token。
  ///
  /// [deviceName] 会上报给桌面端,在「已配对的设备」列表里显示。
  /// 不给的话桌面端只能显示"手机" —— 有多台设备时无法区分。
  Future<bool> pair(String code, {String? deviceName}) async {
    try {
      final r = await _post('/pair', {
        'code': code,
        if (deviceName != null && deviceName.isNotEmpty)
          'deviceName': deviceName,
      });
      if (r['ok'] != true) return false;
      final t = r['token'] as String?;
      if (t == null || t.isEmpty) return false;
      token = t;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 执行一次完整同步。返回本地视角的改动统计。
  /// 执行一次同步。
  ///
  /// ── 策略:双向按操作时间取最新 ──
  ///
  /// 不偏向任何一端。逐项比较 `updatedAt`:谁动得更晚就用谁的状态,
  /// 删除也是动作。两端最终**完全一致**。
  ///
  /// ── 顺序:先推后拉 ──
  ///
  /// 先拉的话,本地的"空书架"会立刻被对端的书填满,
  /// 合并完成后本地就不再是空的 —— 对端始终不知道"你原来删光了"。
  ///
  /// 正确顺序:
  ///   1. 先把本地当前状态推给对端,让它知道"我这边有哪些、删了哪些"
  ///   2. 再拉对端合并后的完整状态,与本地对齐
  ///   3. 再推一次,让对端也拿到本地独有的东西(幂等)
  ///
  /// ── 快照 ──
  ///
  /// 同步成功后记录"这一刻的书架清单"。
  /// 下次同步靠它判断"对端没有这本书"到底是删除还是没同步过 ——
  /// 没有快照就只能猜,猜错就是误删用户的书。
  Future<SyncResult?> sync() async {
    if (token == null) return null;

    // 整体超时:三步串行(推、拉、再推),任何一步卡住都会让界面
    // 永远停在"正在同步"。这里兜住最坏情况 ——
    // 单步 8 秒 × 3 步,再加上处理时间,给 25 秒。
    try {
      return await _syncOnce().timeout(
        const Duration(seconds: 25),
        onTimeout: () => null,
      );
    } catch (_) {
      // 网络异常、JSON 解析失败等都当作"同步失败"。
      // 关键是不能让异常穿透到 UI —— 那样按钮会一直 disabled。
      return null;
    }
  }

  Future<SyncResult?> _syncOnce() async {
    final mirror = SyncMirror(store);

    // 1. 先推本地状态
    final outgoingBefore = await mirror.export();
    final pushed = await _post('/push', {
      'payload': outgoingBefore.toJson(),
    });
    if (pushed['ok'] != true) return null;

    // 2. 拉对端(已吸收本地变更后的)完整状态,与本地对齐
    final pulled = await _get('/pull');
    if (pulled['ok'] != true) return null;
    final payloadJson = pulled['payload'];
    if (payloadJson is! Map<String, dynamic>) return null;

    final localResult = await mirror.merge(
      SyncPayload.decode(jsonEncode(payloadJson)),
    );

    // 3. 再推一次,让对端拿到本地独有的东西
    final outgoingAfter = await mirror.export();
    await _post('/push', {'payload': outgoingAfter.toJson()});

    // 4. 记录本次同步后的完整清单(含墓碑 —— 墓碑也要算"曾经存在",
    //    否则下次会被当成"从没见过"重新处理一遍)。
    final all = await store.loadBooksIncludingDeleted();
    await store.saveSyncSnapshot(all.map((b) => b.id).toSet());

    return localResult;
  }

  /// 单次请求的超时。
  ///
  /// 必须显式给:HttpClient 的 `connectionTimeout` **只限制建立连接**。
  /// 连接建立后对方不返回数据(服务端卡住、数据包被防火墙静默丢弃),
  /// `await req.close()` 会**无限期挂住** —— 界面上就是永远"正在同步",
  /// 既不成功也不报错。现场踩过这个坑。
  ///
  /// 8 秒:内网同步正常在 1 秒内完成,留足余量又不至于让人等太久。
  static const _requestTimeout = Duration(seconds: 8);

  Future<Map<String, dynamic>> _get(String path) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl$path'));
      _addHeaders(req);
      final body = await _readBody(req);
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : {};
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.postUrl(Uri.parse('$baseUrl$path'));
      _addHeaders(req);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final raw = await _readBody(req);
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } finally {
      client.close(force: true);
    }
  }

  /// 发出请求并读完响应体,整体带超时。
  ///
  /// 超时抛 TimeoutException,由调用方当作"失败"处理。
  Future<String> _readBody(HttpClientRequest req) async {
    final res = await req.close().timeout(_requestTimeout);
    return utf8.decoder.bind(res).join().timeout(_requestTimeout);
  }

  void _addHeaders(HttpClientRequest req) {
    if (token != null) {
      req.headers.add('X-PR-Token', token!);
    }
  }
}

/// 把扫码得到的文本解析成 baseUrl 与配对码。
///
/// 支持的格式(容忍用户手输):
///   * `pagereader://pair?host=192.168.1.5&port=8080&code=123456`
///   * `http://192.168.1.5:8080#123456`
///   * `192.168.1.5:8080 123456`
///   * `192.168.1.5:8080`
///
/// 手输的情况很多(扫码失败、复制粘贴),所以解析要宽容。
({String baseUrl, String? code})? parseSyncTarget(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  // 形式 1:自定义 scheme
  if (text.startsWith('pagereader://')) {
    try {
      final uri = Uri.parse(text);
      final host = uri.queryParameters['host'];
      final port = uri.queryParameters['port'];
      final code = uri.queryParameters['code'];
      if (host == null || host.isEmpty) return null;
      final p = port == null || port.isEmpty ? '8080' : port;
      return (baseUrl: 'http://$host:$p', code: code);
    } catch (_) {
      return null;
    }
  }

  // 形式 2:http URL,配对码可能在 fragment 里
  if (text.startsWith('http://') || text.startsWith('https://')) {
    try {
      final uri = Uri.parse(text);
      if (uri.host.isEmpty) return null;
      final port = uri.hasPort ? uri.port : 8080;
      final code = uri.fragment.isEmpty ? null : uri.fragment;
      // 去掉 query 和 fragment,只留 origin。
      return (baseUrl: 'http://${uri.host}:$port', code: code);
    } catch (_) {
      return null;
    }
  }

  // 形式 3/4:手输 `host:port [code]`
  final parts = text.split(RegExp(r'\s+'));
  final hostPort = parts.first;
  final code = parts.length > 1 ? parts[1] : null;

  final hp = hostPort.split(':');
  if (hp.length < 2) {
    // 只给了 IP,用默认端口。
    if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(hostPort)) {
      return (baseUrl: 'http://$hostPort:8080', code: code);
    }
    return null;
  }
  final host = hp[0];
  final port = int.tryParse(hp[1]);
  if (host.isEmpty || port == null) return null;
  return (baseUrl: 'http://$host:$port', code: code);
}

/// 生成扫码用的配对链接(桌面端展示二维码时用)。
String buildPairLink({
  required String host,
  required int port,
  required String code,
}) {
  return 'pagereader://pair?host=$host&port=$port&code=$code';
}
