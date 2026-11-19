import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/ports/ports.dart';
import '../../core/services/settings.dart';
import '../../core/sync/paired_device.dart';
import '../../core/sync/sync_client.dart';
import '../../core/sync/sync_server.dart';

/// 桌面端的同步页。
///
/// ── 为什么自动启动 ──
///
/// 之前要先点「开启同步服务」才显示二维码。用户反馈不合理 ——
/// 点同步按钮的目的就是同步,不是再来一次开关。
/// 所以进页面就启动,直接展示二维码和配对码。
///
/// 服务在页面销毁时关闭(见 dispose)。手机端已配对的 token 落盘了,
/// 下次再开页面还能用,不用重新扫码。
class SyncDesktopPage extends ConsumerStatefulWidget {
  const SyncDesktopPage({super.key, required this.store});

  final LibraryStore store;

  @override
  ConsumerState<SyncDesktopPage> createState() => _SyncDesktopPageState();
}

class _SyncDesktopPageState extends ConsumerState<SyncDesktopPage> {
  SyncServer? _server;
  List<String> _addresses = const [];
  List<PairedDevice> _devices = const [];
  bool _starting = true;
  String? _error;

  /// 设备列表的轮询器。
  ///
  /// 手机扫码配对的瞬间,桌面端没有任何事件通知 ——
  /// 服务只是收到一个 /pair 请求,页面不知道。
  /// 用户看到的就成了"配对成功了但列表还是空的,要手动点刷新"。
  ///
  /// 用轮询解决:每 1.5 秒比对一次设备清单的指纹,
  /// 变了就重建界面。开销极小(读一个本地 JSON),
  /// 而且不需要给 SyncServer 加监听器接口。
  Timer? _devicePoller;
  String _deviceFingerprint = '';

  @override
  void initState() {
    super.initState();
    // 进来就启动,不需要用户再点一次。
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _devicePoller?.cancel();
    _server?.stop();
    super.dispose();
  }

  /// 开始盯设备清单的变化。
  void _startDevicePolling() {
    _devicePoller?.cancel();
    _deviceFingerprint = _fingerprintOf(_devices);
    _devicePoller = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      final server = _server;
      if (server == null || !mounted) return;
      final latest = server.pairedDevices;
      final fp = _fingerprintOf(latest);
      if (fp == _deviceFingerprint) return;
      _deviceFingerprint = fp;
      setState(() => _devices = latest);
    });
  }

  /// 用 token + 最近同步时间做指纹。
  ///
  /// 只看 token 不够:同一台设备再同步一次,列表里的"最近同步"要更新。
  static String _fingerprintOf(List<PairedDevice> list) => list
      .map((d) => '${d.token}:${d.lastSeenAt?.millisecondsSinceEpoch ?? 0}')
      .join('|');

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final settings = ref.read(settingsStoreProvider);
      final server = SyncServer(
        store: widget.store,
        devices: settings == null ? null : PairedDeviceStore(settings),
      );
      await server.start();
      final addrs = await server.localAddresses();
      if (!mounted) return;
      setState(() {
        _server = server;
        _addresses = addrs;
        _devices = server.pairedDevices;
        _starting = false;
      });
      // 启动后开始盯设备变化
      _startDevicePolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '启动失败：$e';
        _starting = false;
      });
    }
  }

  void _refreshDevices() {
    final server = _server;
    if (server == null) return;
    setState(() => _devices = server.pairedDevices);
  }

  Future<void> _unpair(PairedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191B1F),
        title: const Text(
          '断开配对',
          style: TextStyle(
            color: Color(0xFFF2F3F5),
            fontFamily: 'Microsoft YaHei',
          ),
        ),
        content: Text(
          '断开「${device.name}」后，这台设备需要重新扫码才能同步。\n'
          '两端已有的书和进度不受影响。',
          style: const TextStyle(
            color: Color(0xFF9AA0A6),
            fontFamily: 'Microsoft YaHei',
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              '取消',
              style: TextStyle(
                color: Color(0xFF9AA0A6),
                fontFamily: 'Microsoft YaHei',
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '断开',
              style: TextStyle(
                color: Color(0xFFFF9A9A),
                fontFamily: 'Microsoft YaHei',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _server?.unpair(device.token);
    if (!mounted) return;
    _refreshDevices();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已断开「${device.name}」'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 优先用 192.168.x / 10.x 这类常见内网地址。
  String? _bestAddress() {
    if (_addresses.isEmpty) return null;
    for (final a in _addresses) {
      if (a.startsWith('192.168.')) return a;
    }
    for (final a in _addresses) {
      if (a.startsWith('10.')) return a;
    }
    for (final a in _addresses) {
      if (a.startsWith('172.')) {
        final parts = a.split('.');
        if (parts.length > 1) {
          final n = int.tryParse(parts[1]);
          if (n != null && n >= 16 && n <= 31) return a;
        }
      }
    }
    return _addresses.first;
  }

  @override
  Widget build(BuildContext context) {
    final server = _server;
    final host = _bestAddress();

    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0F12),
        elevation: 0,
        title: const Text(
          '与手机同步',
          style: TextStyle(
            color: Color(0xFFF2F3F5),
            fontSize: 18,
            fontFamily: 'Microsoft YaHei',
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF9AA0A6)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (_starting) ...[
            const SizedBox(height: 80),
            const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF5AC8FA),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                '正在启动同步服务…',
                style: TextStyle(
                  color: Color(0xFF5F656C),
                  fontSize: 13,
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
            ),
          ] else if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1818),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFFF9A9A),
                  fontSize: 13,
                  fontFamily: 'Microsoft YaHei',
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _start,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF5AC8FA),
                foregroundColor: const Color(0xFF0E0F12),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                '重试',
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
            ),
          ] else if (server != null) ...[
            // -------- 二维码卡片 --------
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF191B1F),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  if (host == null)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        '没找到局域网地址。\n请确认电脑已连上 Wi-Fi 或网线。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFFFD7A8),
                          fontSize: 13,
                          fontFamily: 'Microsoft YaHei',
                          height: 1.6,
                        ),
                      ),
                    )
                  else ...[
                    const Text(
                      '用手机 PageReader 扫码',
                      style: TextStyle(
                        color: Color(0xFFE3E5E8),
                        fontSize: 15,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$host:${server.port}',
                      style: const TextStyle(
                        color: Color(0xFF5F656C),
                        fontSize: 12,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 白底容器:二维码在深色底上扫不出来。
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: QrImageView(
                        data: buildPairLink(
                          host: host,
                          port: server.port,
                          code: server.pairingCode,
                        ),
                        size: 220,
                        backgroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '配对码  ',
                          style: TextStyle(
                            color: Color(0xFF5F656C),
                            fontSize: 12,
                            fontFamily: 'Microsoft YaHei',
                          ),
                        ),
                        Text(
                          server.pairingCode,
                          style: const TextStyle(
                            color: Color(0xFF5AC8FA),
                            fontSize: 20,
                            fontFamily: 'Consolas',
                            letterSpacing: 4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '配对码用过一次后会自动更换',
                      style: TextStyle(
                        color: Color(0xFF4A4F56),
                        fontSize: 11,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: host == null
                  ? null
                  : () {
                      final code = server.refreshPairingCode();
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('配对码已更新：$code'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF9AA0A6),
                side: const BorderSide(color: Color(0xFF2A2E35)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                '换一个配对码',
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
            ),

            // -------- 已配对设备 --------
            const SizedBox(height: 28),
            Row(
              children: [
                const Text(
                  '已配对的设备',
                  style: TextStyle(
                    color: Color(0xFFE3E5E8),
                    fontSize: 15,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
                const SizedBox(width: 8),
                if (_devices.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF23262B),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '${_devices.length}',
                      style: const TextStyle(
                        color: Color(0xFF9AA0A6),
                        fontSize: 11,
                        fontFamily: 'Microsoft YaHei',
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_devices.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF14161A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF23262B)),
                ),
                child: const Text(
                  '还没有设备配对。\n用手机扫码后会出现在这里。',
                  style: TextStyle(
                    color: Color(0xFF5F656C),
                    fontSize: 12,
                    fontFamily: 'Microsoft YaHei',
                    height: 1.7,
                  ),
                ),
              )
            else
              ..._devices.map(
                (d) => _DeviceCard(
                  device: d,
                  onUnpair: () => _unpair(d),
                ),
              ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _refreshDevices,
              icon: const Icon(Icons.refresh, size: 15),
              label: const Text(
                '刷新列表',
                style: TextStyle(fontSize: 12, fontFamily: 'Microsoft YaHei'),
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF5F656C),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 一台已配对设备的卡片。右侧是"断开配对"按钮。
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onUnpair});

  final PairedDevice device;
  final VoidCallback onUnpair;

  String _fmt(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    if (d.inDays < 30) return '${d.inDays} 天前';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final last = device.lastSeenAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF191B1F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF262A30)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.phone_android,
            size: 20,
            color: Color(0xFF5AC8FA),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(
                    color: Color(0xFFE3E5E8),
                    fontSize: 14,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  last == null
                      ? '配对于 ${_fmt(device.pairedAt)} · 还没同步过'
                      : '最近同步 ${_fmt(last)}',
                  style: const TextStyle(
                    color: Color(0xFF5F656C),
                    fontSize: 11,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onUnpair,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF9A9A),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 32),
            ),
            child: const Text(
              '断开配对',
              style: TextStyle(fontSize: 12, fontFamily: 'Microsoft YaHei'),
            ),
          ),
        ],
      ),
    );
  }
}
