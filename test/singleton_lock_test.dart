import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Chromium 单实例锁清理的测试。
///
/// 背景:上次异常退出会留下 SingletonLock / SingletonCookie /
/// SingletonSocket / lockfile。新进程看到它们会认为"已有实例在跑",
/// 把 URL 转发过去然后自己以 exit code 0 退出 ——
/// 表现是用户点了书什么都没发生,进程列表里也看不到 Edge。
///
/// 这里验证清理逻辑本身;真实启动路径见 tool/verify_all.dart。
void main() {
  late Directory profile;

  setUp(() {
    profile = Directory.systemTemp.createTempSync('pr-locks-');
  });

  tearDown(() {
    try {
      profile.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 复刻 _clearSingletonLocks 的行为(它依赖 CdpEngine 的私有状态,
  /// 这里用同样的逻辑做纯文件层面的验证)。
  void clearLocks(String dir) {
    const names = [
      'SingletonLock',
      'SingletonCookie',
      'SingletonSocket',
      'lockfile',
    ];
    for (final name in names) {
      final full = '$dir${Platform.pathSeparator}$name';
      try {
        final f = File(full);
        final l = Link(full);
        if (f.existsSync()) {
          f.deleteSync();
        } else if (l.existsSync()) {
          l.deleteSync();
        }
      } catch (_) {}
    }
  }

  group('清理锁文件', () {
    test('四个锁文件都会被删除', () {
      final names = [
        'SingletonLock',
        'SingletonCookie',
        'SingletonSocket',
        'lockfile',
      ];
      for (final n in names) {
        File(
          '${profile.path}${Platform.pathSeparator}$n',
        ).writeAsStringSync('stale');
      }
      // 清理前确实存在
      for (final n in names) {
        expect(
          File('${profile.path}${Platform.pathSeparator}$n').existsSync(),
          isTrue,
        );
      }

      clearLocks(profile.path);

      for (final n in names) {
        expect(
          File('${profile.path}${Platform.pathSeparator}$n').existsSync(),
          isFalse,
          reason: '$n 应该被清理',
        );
      }
    });

    test('不存在的锁文件不报错', () {
      expect(() => clearLocks(profile.path), returnsNormally);
    });

    test('不碰其它文件', () {
      final keep = File('${profile.path}${Platform.pathSeparator}Preferences');
      keep.writeAsStringSync('{"setting":1}');
      File(
        '${profile.path}${Platform.pathSeparator}SingletonLock',
      ).writeAsStringSync('stale');

      clearLocks(profile.path);

      expect(
        keep.existsSync(),
        isTrue,
        reason: '只该删锁文件,不能动 profile 里的其它数据',
      );
      expect(keep.readAsStringSync(), '{"setting":1}');
    });

    test('不碰子目录里的同名文件', () {
      final sub = Directory(
        '${profile.path}${Platform.pathSeparator}Default',
      )..createSync();
      final inner = File(
        '${sub.path}${Platform.pathSeparator}SingletonLock',
      )..writeAsStringSync('inner');

      clearLocks(profile.path);

      expect(
        inner.existsSync(),
        isTrue,
        reason: '锁文件在 profile 根目录,不该递归删子目录的',
      );
    });

    test('空 profile 目录不报错', () {
      final empty = Directory.systemTemp.createTempSync('pr-empty-');
      expect(() => clearLocks(empty.path), returnsNormally);
      empty.deleteSync(recursive: true);
    });
  });

  group('真实场景复现', () {
    test('残留锁 + 清理后目录恢复干净', () {
      // 模拟异常退出:写完锁文件就没了
      for (final n in ['SingletonLock', 'SingletonCookie', 'lockfile']) {
        File(
          '${profile.path}${Platform.pathSeparator}$n',
        ).writeAsStringSync('crash-residue');
      }
      // 模拟正常的数据文件
      for (final n in ['Preferences', 'History']) {
        File(
          '${profile.path}${Platform.pathSeparator}$n',
        ).writeAsStringSync('data');
      }

      clearLocks(profile.path);

      final remaining = profile
          .listSync()
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .toSet();
      expect(remaining, {'Preferences', 'History'});
    });
  });
}
