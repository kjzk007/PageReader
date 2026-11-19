import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 退出前先把所有打开的书保存一次。
///
/// 为什么必须有:用户关掉应用那一刻,阅读窗口还开着,
/// 最后一次滚动只有我们知道。如果不 flush 就直接退出,
/// 下次打开会回到"上一次自动记录的位置",读的最后几页白读。
///
/// 策略(台账已定):
///   * 先 flush 再退,不静默丢数据
///   * 显示"正在保存"遮罩,超时 3 秒允许强制退出
///   * 不做无限等待:CDP 卡住时宁可丢一条也不能卡死应用
class QuitGuard extends StatefulWidget {
  const QuitGuard({
    super.key,
    required this.child,
    required this.onFlush,
    this.timeout = const Duration(seconds: 3),
  });

  final Widget child;

  /// 退出前的保存动作。返回后即认为保存完毕。
  final Future<void> Function() onFlush;

  /// 超过这个时间仍未完成,允许用户强制退出。
  final Duration timeout;

  @override
  State<QuitGuard> createState() => _QuitGuardState();
}

class _QuitGuardState extends State<QuitGuard> with WindowListener {
  bool _saving = false;
  bool _forceAvailable = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // 已经在保存中:再点关闭就当作"强制退出"。
    if (_saving) {
      await _reallyQuit();
      return;
    }

    setState(() {
      _saving = true;
      _forceAvailable = false;
    });

    Timer(widget.timeout, () {
      if (!mounted || !_saving) return;
      setState(() {
        _forceAvailable = true;
      });
    });

    try {
      await widget.onFlush();
    } catch (_) {
      // 保存失败也要让用户退出,不能把应用锁死。
    }

    await _reallyQuit();
  }

  Future<void> _reallyQuit() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_saving)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xCC000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '正在保存阅读进度…',
                      style: TextStyle(
                        color: Color(0xFFE3E5E8),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '保存完就会退出',
                      style: TextStyle(
                        color: Color(0xFF6E747C),
                        fontSize: 12,
                      ),
                    ),
                    if (_forceAvailable) ...[
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: _reallyQuit,
                        child: const Text(
                          '不再等待,强制退出',
                          style: TextStyle(
                            color: Color(0xFFFF6B6B),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
