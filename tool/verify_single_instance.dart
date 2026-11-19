// 验证单实例锁:启动两个进程,第二个必须自己退出。
import 'dart:io';

import 'paths.dart';

const exe = exePath();

Future<int> main() async {
  var fail = 0;
  void check(String label, bool ok, [String detail = '']) {
    if (ok) {
      stdout.writeln('PASS $label');
    } else {
      fail++;
      stdout.writeln('FAIL $label  $detail');
    }
  }

  await Process.run('taskkill', ['/F', '/IM', 'pagereader.exe']);
  await Future<void>.delayed(const Duration(seconds: 1));

  stdout.writeln('=== 启动第一个实例 ===');
  final first = await Process.start(exe, const []);
  await Future<void>.delayed(const Duration(seconds: 6));
  check('第一个实例在运行', _alive(first), '');

  stdout.writeln('=== 启动第二个实例 ===');
  final second = await Process.start(exe, const []);
  final exitCode = await second.exitCode.timeout(
    const Duration(seconds: 12),
    onTimeout: () {
      stdout.writeln('  第二个实例 12 秒内没退出');
      return -999;
    },
  );
  stdout.writeln('  第二个实例退出码 = $exitCode');
  check('第二个实例已自行退出', exitCode == 0, 'exitCode=$exitCode');

  final count = await _countProcesses();
  stdout.writeln('  当前 pagereader 进程数 = $count');
  check('只剩一个实例', count == 1, 'count=$count');

  await Process.run('taskkill', ['/F', '/IM', 'pagereader.exe']);
  await Future<void>.delayed(const Duration(seconds: 1));

  // 锁在进程退出后必须自动释放,否则用户第二次就打不开了。
  stdout.writeln('');
  stdout.writeln('=== 全部退出后重新启动,确认锁已释放 ===');
  final third = await Process.start(exe, const []);
  await Future<void>.delayed(const Duration(seconds: 6));
  check('退出后能再次启动', _alive(third), '');

  await Process.run('taskkill', ['/F', '/IM', 'pagereader.exe']);
  stdout.writeln('');
  stdout.writeln(fail == 0 ? '=== 全部通过 ===' : '=== $fail 项失败 ===');
  return fail;
}

bool _alive(Process p) => p.exitCode.toString() != '0';

Future<int> _countProcesses() async {
  final r = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    r'(Get-Process -Name pagereader -ErrorAction SilentlyContinue | Measure-Object).Count',
  ]);
  return int.tryParse((r.stdout as String).trim()) ?? 0;
}
