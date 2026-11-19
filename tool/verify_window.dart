// 验证:通过书架打开的书,窗口是否最大化。
//
// 必须在有界面的真实环境跑(headless 没有窗口)。
// 用独立沙箱目录,不碰用户数据。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'paths.dart';

import 'package:path/path.dart' as p;

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

  final sandbox = Directory.systemTemp.createTempSync('pr-win-');
  final profile = p.join(sandbox.path, 'browser-profile');
  stdout.writeln('沙箱: ${sandbox.path}');

  Future<void> killAll() async {
    await Process.run('taskkill', ['/F', '/IM', 'pagereader.exe']);
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      r'Get-CimInstance Win32_Process -Filter "Name=''msedge.exe''" | '
          r'Where-Object { $_.CommandLine -like ''*pr-win-*'' } | '
          r'Select-Object -ExpandProperty ProcessId',
    ]);
    for (final s in (r.stdout as String).split(RegExp(r'\s+'))) {
      final pid = int.tryParse(s);
      if (pid != null) await Process.run('taskkill', ['/F', '/PID', '$pid']);
    }
  }

  try {
    await killAll();
    await Future<void>.delayed(const Duration(seconds: 1));

    final env = Map<String, String>.from(Platform.environment);
    env['PAGEREADER_OPEN'] = 'b-rust';
    env['PAGEREADER_DATA_DIR'] = sandbox.path;
    await Process.start(exe, const [], environment: env);

    final pf = File(p.join(profile, 'DevToolsActivePort'));
    int? port;
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (pf.existsSync()) {
        final l = pf.readAsLinesSync();
        if (l.isNotEmpty) {
          port = int.tryParse(l.first.trim());
          if (port != null) break;
        }
      }
    }
    check('应用与浏览器已启动', port != null, 'port=$port');
    if (port == null) return 1;

    // 等窗口稳定
    await Future<void>.delayed(const Duration(seconds: 6));

    final state = await _windowState(port);
    stdout.writeln('  窗口状态: ${state ?? "取不到"}');
    check(
      '阅读窗口已最大化',
      state == 'maximized',
      'windowState=$state',
    );

    if (state != null) {
      final bounds = await _windowBounds(port);
      stdout.writeln('  窗口尺寸: $bounds');
    }
  } finally {
    await killAll();
    await Future<void>.delayed(const Duration(seconds: 1));
    try {
      sandbox.deleteSync(recursive: true);
    } catch (_) {}
  }

  stdout.writeln('');
  stdout.writeln(fail == 0 ? '══════ 通过 ══════' : '══════ $fail 项失败 ══════');
  return fail;
}

Future<Map<String, dynamic>?> _call(
  int port,
  String method,
  Map<String, dynamic> params,
) async {
  try {
    final c = HttpClient();
    final res = await (await c.getUrl(
      Uri.parse('http://127.0.0.1:$port/json/version'),
    )).close();
    final wsUrl =
        (jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>)['webSocketDebuggerUrl'] as String;
    c.close();
    final ws = await WebSocket.connect(wsUrl);
    final comp = Completer<Map<String, dynamic>>();
    ws.listen((d) {
      final m = jsonDecode(d as String) as Map<String, dynamic>;
      if (m['id'] == 1 && !comp.isCompleted) {
        comp.complete((m['result'] as Map<String, dynamic>?) ?? {});
      }
    });
    ws.add(jsonEncode({'id': 1, 'method': method, 'params': params}));
    final r = await comp.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => <String, dynamic>{},
    );
    await ws.close();
    return r;
  } catch (_) {
    return null;
  }
}

Future<String?> _windowState(int port) async {
  final targets = await _call(port, 'Target.getTargets', {});
  final infos =
      (targets?['targetInfos'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>()
          .where((t) => t['type'] == 'page')
          .toList() ??
      [];
  if (infos.isEmpty) return null;
  final win = await _call(port, 'Browser.getWindowForTarget', {
    'targetId': infos.first['targetId'],
  });
  final b = win?['bounds'];
  return (b as Map?)?['windowState'] as String?;
}

Future<String?> _windowBounds(int port) async {
  final targets = await _call(port, 'Target.getTargets', {});
  final infos =
      (targets?['targetInfos'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>()
          .where((t) => t['type'] == 'page')
          .toList() ??
      [];
  if (infos.isEmpty) return null;
  final win = await _call(port, 'Browser.getWindowForTarget', {
    'targetId': infos.first['targetId'],
  });
  final b = win?['bounds'];
  if (b is! Map) return null;
  return '${b['width']}x${b['height']} @ ${b['left']},${b['top']}';
}
