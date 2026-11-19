import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../ports/ports.dart';
import 'sync_merger.dart';
import 'sync_mirror.dart';
import 'paired_device.dart';
import 'sync_protocol.dart';

/// 桌面端的同步服务。
///
/// 架构(已定):桌面开服务、手机连过来。
///
/// 为什么是这个方向:
///   * 手机息屏后后台服务容易被系统杀掉,做服务端不可靠;
///   * 桌面端本来就是长期开机、数据更全的那一端。
///
/// 安全设计:
///   * 绑定 0.0.0.0 才能被同一局域网访问,但不做鉴权就等于谁都能读 ——
///     所以加**配对码**:桌面端随机生成 6 位,手机首次连接必须带上。
///   * 配对成功后返回一个长期 token,之后不必每次输码。
///   * 通讯是明文 HTTP(局域网内可接受),不做全局暴露,只在显式开启时监听。
class SyncServer {
  SyncServer({required this.store, this.devices});

  final LibraryStore store;

  /// 已配对设备的持久化存储。
  ///
  /// 为空时退化成"不记录设备"(纯测试场景)。真实运行必须传 ——
  /// 否则每次重启电脑,手机上的 token 就失效了,用户要重新扫码。
  final PairedDeviceStore? devices;

  HttpServer? _server;
  int _port = 0;

  /// 当前配对码。一次性使用,配对成功后自动换新的。
  String _pairingCode = '';

  bool get isRunning => _server != null;
  int get port => _port;
  String get pairingCode => _pairingCode;

  /// 当前已配对的设备(给界面展示)。
  List<PairedDevice> get pairedDevices => devices?.load() ?? const [];

  /// 断开一台设备:移除它的 token,手机端下次同步会被拒绝。
  Future<void> unpair(String token) async {
    await devices?.remove(token);
  }

  /// 本机在局域网里的 IP,给二维码用。
  Future<List<String>> localAddresses() async {
    final out = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final i in interfaces) {
        for (final a in i.addresses) {
          // 169.254.x.x 是链路本地地址,连不通,排除。
          if (a.address.startsWith('169.254.')) continue;
          out.add(a.address);
        }
      }
    } catch (_) {
      // 拿不到网卡列表就返回空,UI 会提示用户检查网络。
    }
    return out;
  }

  /// 启动服务。端口 0 表示让系统分配。
  /// 默认端口。
  ///
  /// ── 为什么必须固定 ──
  ///
  /// 手机端配对时保存了 `baseUrl`(含端口)。如果桌面端每次启动都用
  /// `port: 0` 让系统随机分配,下次开同步页端口就变了 ——
  /// 手机上"立即同步"直接连不上,只有重新扫码(拿到新端口)才行。
  ///
  /// 现场就是这样:用户配对成功了,但点同步毫无反应,
  /// 非得重新扫码才同步一次。
  ///
  /// 选 47321:高位端口,冲突概率低;不是常见服务端口。
  static const defaultPort = 47321;

  /// 启动服务。端口固定用 [defaultPort],被占用时才退回随机端口。
  Future<void> start({int? port}) async {
    if (_server != null) return;

    final wantPort = port ?? defaultPort;
    HttpServer? server;

    // 1. 优先绑固定端口 —— 这样手机存的地址下次还能用。
    try {
      server = await HttpServer.bind(InternetAddress('0.0.0.0'), wantPort);
    } catch (_) {
      server = null;
    }
    // 2. 固定端口被占(比如上次没退干净),退回随机端口。
    //    UI 会显示实际端口,用户重新扫码即可。
    server ??= await HttpServer.bind(InternetAddress.anyIPv4, 0);

    _server = server;
    _port = server.port;
    _pairingCode = _generateCode();

    unawaited(_serve(server));
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
    // 刻意不清空已配对设备:token 落盘了,重启服务后手机应该还能用。
    // 否则用户每次开电脑都得重新扫码。
  }

  /// 重新生成配对码(用户手动刷新时用)。
  String refreshPairingCode() {
    _pairingCode = _generateCode();
    return _pairingCode;
  }

  String _generateCode() {
    // 6 位数字,去掉容易混淆的 0/1。
    const digits = '23456789';
    final r = Random.secure();
    return List.generate(
      6,
      (_) => digits[r.nextInt(digits.length)],
    ).join();
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      // CORS:手机端起请求时不带 Origin(原生 HTTP 客户端),
      // 但用浏览器调试时需要。这里一律放开。
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add(
        'Access-Control-Allow-Headers',
        'Content-Type, X-PR-Token',
      );
      request.response.headers.add(
        'Access-Control-Allow-Methods',
        'GET, POST, OPTIONS',
      );

      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }

      final path = request.uri.path;

      // 健康检查:手机用它确认地址对不对,不需要鉴权。
      if (path == '/ping') {
        await _json(request.response, {
          'app': 'PageReader',
          'version': 1,
          'pairingRequired': true,
        });
        return;
      }

      // 配对:用配对码换 token。
      if (path == '/pair' && request.method == 'POST') {
        final body = await _readJson(request);
        final code = (body['code'] as String? ?? '').trim();
        if (code != _pairingCode) {
          await _json(
            request.response,
            {'ok': false, 'error': '配对码不对'},
            status: HttpStatus.forbidden,
          );
          return;
        }
        final token = _newToken();
        // 记录设备,让界面能看到"哪些设备配对过"。
        final deviceName = (body['deviceName'] as String?)?.trim();
        await devices?.add(
          PairedDevice(
            token: token,
            name: (deviceName != null && deviceName.isNotEmpty)
                ? deviceName
                : '手机',
            pairedAt: DateTime.now(),
          ),
        );
        // 配对码一次性:用掉就换新的,避免被重放。
        _pairingCode = _generateCode();
        await _json(request.response, {'ok': true, 'token': token});
        return;
      }

      // 以下接口都要 token。
      if (!_authorized(request)) {
        await _json(
          request.response,
          {'ok': false, 'error': '未配对'},
          status: HttpStatus.unauthorized,
        );
        return;
      }

      // 拉取桌面端数据。
      if (path == '/pull') {
        final merger = SyncMerger(store);
        final payload = await merger.export();
        await _json(request.response, {
          'ok': true,
          'payload': payload.toJson(),
        });
        return;
      }

      // 推送手机端数据。
      //
      // 两种模式:
      //   * mode = mirror（默认）—— 手机是权威端。桌面端书架被改写成
      //     与手机完全一致。用户在手机上删了书,桌面端也会删掉。
      //   * mode = merge —— 旧的合并逻辑(取并集 + 时间戳仲裁)。
      //     保留是为了兼容,实际不用。
      if (path == '/push' && request.method == 'POST') {
        final body = await _readJson(request);
        final payloadJson = body['payload'];
        if (payloadJson is! Map<String, dynamic>) {
          await _json(
            request.response,
            {'ok': false, 'error': '缺少 payload'},
            status: HttpStatus.badRequest,
          );
          return;
        }
        final incoming = SyncPayload.decode(jsonEncode(payloadJson));

        // 双向按操作时间取最新。不偏向任何一端。
        final result = await SyncMirror(store).merge(incoming);

        await _json(request.response, {
          'ok': true,
          'added': result.booksAdded,
          'updated': result.booksUpdated,
          'removed': result.booksRemoved,
          'progress': result.progressUpdated,
        });
        return;
      }

      await _json(
        request.response,
        {'ok': false, 'error': '未知路径'},
        status: HttpStatus.notFound,
      );
    } catch (e) {
      // 单个请求失败不能拖垮服务。
      try {
        await _json(
          request.response,
          {'ok': false, 'error': '$e'},
          status: HttpStatus.internalServerError,
        );
      } catch (_) {}
    }
  }

  bool _authorized(HttpRequest request) {
    final token = request.headers.value('X-PR-Token');
    if (token == null || token.isEmpty) return false;
    // devices 为空(纯测试场景)时退化成"任何 token 都放行",
    // 保证老测试不用改。
    final store = devices;
    if (store == null) return true;
    final ok = store.contains(token);
    // 记一次活跃时间。
    //
    // 不 await:鉴权在请求热路径上,不能因为写文件拖慢响应。
    // 写失败也不影响本次请求 —— 只是界面上"最近同步"晚一点更新。
    if (ok) unawaited(store.touch(token));
    return ok;
  }

  String _newToken() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    if (raw.trim().isEmpty) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  Future<void> _json(
    HttpResponse response,
    Map<String, Object?> body, {
    int status = HttpStatus.ok,
  }) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }
}
