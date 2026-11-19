import 'dart:io';

import 'package:flutter/foundation.dart';

/// 单实例锁。
///
/// 为什么必须有:用户双击两次图标、或者从开始菜单又点一次,会启动两个进程。
/// 两个进程同时写同一个 SQLite,轻则锁等待,重则把库写坏
/// —— 书架是长期数据,坏了就是灾难。
///
/// 做法:在应用数据目录开一个独占的锁文件。
/// 第二个实例拿不到锁就把已有窗口激活,然后退出。
class SingleInstance {
  SingleInstance._();

  static RandomAccessFile? _lock;

  /// 尝试占用锁。返回 false 表示已有实例在运行。
  ///
  /// 用 `RandomAccessFile.lock(FileLock.exclusive)`:
  /// 进程退出(含崩溃)时操作系统会自动释放,不会留下死锁。
  static bool acquire(Directory supportDir) {
    try {
      supportDir.createSync(recursive: true);
      final lockFile = File(
        '${supportDir.path}${Platform.pathSeparator}pagereader.lock',
      );
      final raf = lockFile.openSync(mode: FileMode.write);
      try {
        raf.lockSync(FileLock.exclusive);
      } on FileSystemException {
        // 另一个实例持有锁。
        raf.closeSync();
        return false;
      }
      // 写进 PID 方便排查,但锁的权威性不依赖文件内容。
      raf.setPositionSync(0);
      raf.truncateSync(0);
      raf.writeStringSync('$pid\n');
      raf.flushSync();
      _lock = raf;
      return true;
    } catch (e) {
      // 锁机制本身出问题时不阻止启动:
      // 宁可冒双开的风险,也不要让用户完全打不开应用。
      debugPrint('单实例锁失败,继续启动: $e');
      return true;
    }
  }

  static void release() {
    try {
      _lock?.unlockSync();
      _lock?.closeSync();
    } catch (_) {}
    _lock = null;
  }
}
