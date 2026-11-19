import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/ports/ports.dart';
import '../../core/services/settings.dart';
import '../../core/sync/sync_client.dart';
import '../../core/sync/sync_protocol.dart';
import '../../core/sync/sync_server.dart';
import '../../main.dart' show shelfReloadProvider;

/// 手机端的同步页:扫码配对 + 一键同步。
///
/// 流程:
///   1. 扫桌面端二维码 → 解析出地址和配对码
///   2. 配对成功 → token 存进设置,下次不用再扫
///   3. 点同步 → 双向合并
class SyncPhonePage extends ConsumerStatefulWidget {
  const SyncPhonePage({super.key, required this.store});

  final LibraryStore store;

  @override
  ConsumerState<SyncPhonePage> createState() => _SyncPhonePageState();
}

class _SyncPhonePageState extends ConsumerState<SyncPhonePage> {
  bool _scanning = false;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  static const _channel = MethodChannel('com.pagereader/device');

  /// 读本机机型,配对时上报给桌面端。
  ///
  /// 只是为了让桌面端的「已配对的设备」能区分是哪台手机。
  /// 读不到就返回空 —— 桌面端会显示默认名,不影响功能。
  Future<String> _deviceName() async {
    try {
      final v = await _channel.invokeMethod<String>('deviceModel');
      return (v ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _handleScan(String raw) async {
    if (_busy) return;
    setState(() {
      _scanning = false;
      _busy = true;
      _message = '正在配对…';
      _messageIsError = false;
    });

    final target = parseSyncTarget(raw);
    if (target == null) {
      setState(() {
        _busy = false;
        _message = '二维码内容无法识别';
        _messageIsError = true;
      });
      return;
    }

    final client = SyncClient(
      store: widget.store,
      baseUrl: target.baseUrl,
    );
    final reachable = await client.ping();
    if (!reachable) {
      setState(() {
        _busy = false;
        _message = '连不上 ${target.baseUrl}\n'
            '请确认电脑和手机在同一个 Wi-Fi，且桌面端已开启同步服务。';
        _messageIsError = true;
      });
      return;
    }

    final code = target.code;
    if (code == null || code.isEmpty) {
      setState(() {
        _busy = false;
        _message = '二维码里没有配对码，请在电脑上重新生成';
        _messageIsError = true;
      });
      return;
    }

    // 上报机型,桌面端的「已配对的设备」里能区分是哪台。
    final ok = await client.pair(code, deviceName: await _deviceName());
    if (!ok) {
      setState(() {
        _busy = false;
        _message = '配对失败，配对码可能已过期';
        _messageIsError = true;
      });
      return;
    }

    // 配对成功:把地址和 token 存下来。
    final store = ref.read(settingsStoreProvider);
    await store?.writeString('sync.baseUrl', target.baseUrl);
    await store?.writeString('sync.token', client.token ?? '');

    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = '配对成功，正在同步…';
      _messageIsError = false;
    });
    await _doSync();
  }

  Future<void> _doSync() async {
    final store = ref.read(settingsStoreProvider);
    final baseUrl = store?.readString('sync.baseUrl') ?? '';
    final token = store?.readString('sync.token') ?? '';

    if (baseUrl.isEmpty || token.isEmpty) {
      setState(() {
        _message = '还没配对，请先扫码连接电脑';
        _messageIsError = true;
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = '正在同步…';
      _messageIsError = false;
    });

    final client = SyncClient(
      store: widget.store,
      baseUrl: baseUrl,
      token: token,
    );

    SyncResult? result;
    try {
      result = await client.sync();
    } catch (_) {
      // sync() 内部已经兜了超时和异常,这里再保一层 ——
      // 绝对不能让 _busy 停在 true,否则按钮永久禁用、界面卡在"正在同步"。
      result = null;
    }

    // 连不上时,试一下"同一个 IP + 默认端口"。
    //
    // 历史遗留问题:早期桌面端用随机端口,手机存下的端口在电脑重开
    // 同步页后就失效了,表现为"配对过但点同步毫无反应"。
    // 现在桌面端已固定端口(47321),但用户可能还存着旧端口,
    // 或者电脑上还有别的版本在跑。这里兜一下,省得让人重新扫码。
    if (result == null) {
      final fallback = _withDefaultPort(baseUrl);
      if (fallback != null) {
        final retry = SyncClient(
          store: widget.store,
          baseUrl: fallback,
          token: token,
        );
        try {
          result = await retry.sync();
        } catch (_) {
          result = null;
        }
        if (result != null) {
          // 兜底成功:把地址改成能用的那个,下次直接用。
          await store?.writeString('sync.baseUrl', fallback);
        }
      }
    }

    if (!mounted) return;
    if (result == null) {
      setState(() {
        _busy = false;
        _message = '连不上电脑。请确认：\n'
            '· 电脑上 PageReader 正开着同步页\n'
            '· 两台设备在同一 Wi-Fi\n'
            '· 电脑 IP 没变（变了要重新扫码）';
        _messageIsError = true;
      });
      return;
    }

    // 同步后书架数据变了,通知书架刷新。
    // 不刷新的话用户看到的是旧界面,会以为"同步没生效"。
    ref.read(shelfReloadProvider).value++;

    setState(() {
      _busy = false;
      _message = '同步完成：${result!.describe()}';
      _messageIsError = false;
    });
  }

  /// 把 baseUrl 的端口换成默认端口。
  ///
  /// `http://192.168.0.103:12345` → `http://192.168.0.103:47321`
  /// 解析不出 IP 时返回 null。
  String? _withDefaultPort(String baseUrl) {
    try {
      final uri = Uri.parse(baseUrl);
      final host = uri.host;
      if (host.isEmpty) return null;
      final fixed = uri.replace(port: SyncServer.defaultPort);
      final result = fixed.toString();
      return result == baseUrl ? null : result;
    } catch (_) {
      return null;
    }
  }

  Future<void> _unpair() async {
    final store = ref.read(settingsStoreProvider);
    await store?.writeString('sync.baseUrl', '');
    await store?.writeString('sync.token', '');
    if (!mounted) return;
    setState(() {
      _message = '已解除配对';
      _messageIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(settingsStoreProvider);
    final baseUrl = store?.readString('sync.baseUrl') ?? '';
    final paired = baseUrl.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0F12),
        elevation: 0,
        title: const Text(
          '与桌面端同步',
          style: TextStyle(
            color: Color(0xFFF2F3F5),
            fontSize: 18,
            fontFamily: 'Microsoft YaHei',
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF9AA0A6)),
      ),
      body: _scanning
          ? _buildScanner()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF191B1F),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            paired
                                ? Icons.link
                                : Icons.link_off_outlined,
                            size: 18,
                            color: paired
                                ? const Color(0xFF5AC8FA)
                                : const Color(0xFF5F656C),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            paired ? '已配对' : '未配对',
                            style: TextStyle(
                              color: paired
                                  ? const Color(0xFFE3E5E8)
                                  : const Color(0xFF9AA0A6),
                              fontSize: 14,
                              fontFamily: 'Microsoft YaHei',
                            ),
                          ),
                        ],
                      ),
                      if (paired) ...[
                        const SizedBox(height: 6),
                        Text(
                          baseUrl,
                          style: const TextStyle(
                            color: Color(0xFF5F656C),
                            fontSize: 12,
                            fontFamily: 'Consolas',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_message != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _messageIsError
                          ? const Color(0xFF2A1818)
                          : const Color(0xFF16251A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _message!,
                      style: TextStyle(
                        color: _messageIsError
                            ? const Color(0xFFFF9A9A)
                            : const Color(0xFF9AD9AC),
                        fontSize: 12,
                        fontFamily: 'Microsoft YaHei',
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (paired) ...[
                  FilledButton(
                    onPressed: _busy ? null : _doSync,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF5AC8FA),
                      foregroundColor: const Color(0xFF0E0F12),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      _busy ? '正在同步…' : '立即同步',
                      style: const TextStyle(
                        fontSize: 14,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _busy ? null : () => setState(() => _scanning = true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF9AA0A6),
                      side: const BorderSide(color: Color(0xFF2A2E35)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      '重新扫码配对',
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _busy ? null : _unpair,
                    child: const Text(
                      '解除配对',
                      style: TextStyle(
                        color: Color(0xFF7C8188),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ] else ...[
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _scanning = true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF5AC8FA),
                      foregroundColor: const Color(0xFF0E0F12),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      '扫码连接电脑',
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  '在电脑上打开 PageReader → 同步 → 开启同步服务，'
                  '然后用这里扫码。\n'
                  '手机和电脑要在同一个 Wi-Fi 下。',
                  style: TextStyle(
                    color: Color(0xFF4A4F56),
                    fontSize: 11,
                    fontFamily: 'Microsoft YaHei',
                    height: 1.7,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            final barcodes = capture.barcodes;
            if (barcodes.isEmpty) return;
            final raw = barcodes.first.rawValue;
            if (raw == null || raw.isEmpty) return;
            _handleScan(raw);
          },
        ),
        // 取景框
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF5AC8FA), width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    '把电脑上的二维码放进框里',
                    style: TextStyle(
                      color: Color(0xFFE3E5E8),
                      fontSize: 14,
                      fontFamily: 'Microsoft YaHei',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(() => _scanning = false),
                    child: const Text(
                      '取消',
                      style: TextStyle(color: Color(0xFF5AC8FA)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
