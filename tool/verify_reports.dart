// 验收新的上报机制,四个场景:
//   1. 滚动后静止 → 库里有新位置(不需要退出)
//   2. 连续滚动 → 防抖只写一次
//   3. 关掉阅读窗口 → 精确记录关闭那一刻的位置
//   4. 硬杀应用 → 断电模拟,最后位置仍在库里
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

  final appData = Platform.environment['APPDATA']!;
  final support = p.join(appData, 'com.pagereader', 'PageReader');
  final profile = p.join(support, 'browser-profile');
  final db = p.join(support, 'pagereader.sqlite');

  await _killAll();
  await _del(profile);
  await _del(db);
  await _del('$db-wal');
  await _del('$db-shm');
  await Future<void>.delayed(const Duration(seconds: 1));

  var port = await _launch('b-rust');
  if (port == null) {
    check('浏览器启动', false);
    return 1;
  }
  await _waitContent(port);
  await Future<void>.delayed(const Duration(seconds: 3));

  // ---------- 场景 1:滚动后静止 ----------
  stdout.writeln('=== 场景 1:滚到 2500,静止 3 秒 ===');
  await _scrollTo(port, 2500);
  await Future<void>.delayed(const Duration(seconds: 3));
  final r1 = _ratio(await _readDb(db));
  stdout.writeln('  库里 docRatio = $r1');
  final max1 = await _eval(
    port,
    '(() => { const se = document.scrollingElement||document.documentElement;'
    'return se.scrollHeight - se.clientHeight; })()',
  );
  final expect1 = 2500 / (max1 as num).toDouble();
  check(
    '滚动后无需退出就落库',
    r1 != null && (r1 - expect1).abs() < 0.02,
    '库里 $r1,期望 $expect1',
  );

  // ---------- 场景 2:连续滚动,防抖 ----------
  stdout.writeln('');
  stdout.writeln('=== 场景 2:快速连滚 3000→4000→5000,静止 3 秒 ===');
  for (final y in [3000, 4000, 5000]) {
    await _scrollTo(port, y);
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  await Future<void>.delayed(const Duration(seconds: 3));
  final r2 = _ratio(await _readDb(db));
  final expect2 = 5000 / (max1 as num).toDouble();
  stdout.writeln('  库里 docRatio = $r2,期望 $expect2');
  check(
    '最终落在最后一次滚动的位置(防抖生效)',
    r2 != null && (r2 - expect2).abs() < 0.02,
    '库里 $r2',
  );

  // ---------- 场景 3:关掉阅读窗口 ----------
  stdout.writeln('');
  stdout.writeln('=== 场景 3:滚到 7777,然后关掉阅读窗口 ===');
  await _scrollTo(port, 7777);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  // 不等防抖,直接关窗 —— 验证 pagehide 能兜住
  await _closePageWindow(port);
  await Future<void>.delayed(const Duration(seconds: 3));
  final r3 = _ratio(await _readDb(db));
  final expect3 = 7777 / (max1 as num).toDouble();
  stdout.writeln('  库里 docRatio = $r3,期望 $expect3');
  check(
    '关窗口那一刻的位置被记录(pagehide)',
    r3 != null && (r3 - expect3).abs() < 0.05,
    '库里 $r3,期望 $expect3',
  );

  // ---------- 场景 4:硬杀 ----------
  stdout.writeln('');
  stdout.writeln('=== 场景 4:重开,滚到 1200,硬杀应用 ===');
  await _killAll();
  await Future<void>.delayed(const Duration(seconds: 1));
  port = await _launch('b-rust');
  if (port == null) {
    check('第二次启动', false);
    return 1;
  }
  await _waitContent(port);
  // 认领发生在引擎连上之后,等它完成再滚动
  await Future<void>.delayed(const Duration(seconds: 5));
  await _eval(
    port,
    'location.href + "|reporting=" + window.__prReporting + "|fn=" + (typeof window.__prReport)',
  );
  stdout.writeln('  页面状态 = ');
  await _scrollTo(port, 1200);
  stdout.writeln('  已滚到 1200,等上报…');
  await Future<void>.delayed(const Duration(seconds: 4));
  final midDb = _ratio(await _readDb(db));
  stdout.writeln('  硬杀前的库里值 = ');
  await _killAll();
  await Future<void>.delayed(const Duration(seconds: 1));
  final r4 = _ratio(await _readDb(db));
  final expect4 = 1200 / (max1 as num).toDouble();
  stdout.writeln('  库里 docRatio = $r4,期望 $expect4');
  check(
    '硬杀前的位置已落库(事件驱动覆盖断电)',
    r4 != null && (r4 - expect4).abs() < 0.05,
    '库里 $r4,期望 $expect4',
  );

  await _killAll();
  stdout.writeln('');
  stdout.writeln(fail == 0 ? '=== 全部通过 ===' : '=== $fail 项失败 ===');
  return fail;
}

// ----------------------------------------------------------------

Future<void> _closePageWindow(int port) async {
  await _cdp(port, 'Target.getTargets', {}, (infos) async {
    final pages = infos
        .where((t) => t['type'] == 'page')
        .where((t) => (t['url'] as String).contains('rust-lang'))
        .toList();
    for (final t in pages) {
      await _cdp(port, 'Target.closeTarget', {'targetId': t['targetId']},
          (_) async {});
    }
  });
}

Future<void> _scrollTo(int port, int y) async {
  await _eval(
    port,
    '(() => { const se = document.scrollingElement||document.documentElement;'
    'se.scrollTop = $y; window.scrollTo(0, $y); return window.scrollY; })()',
  );
}

Future<void> _waitContent(int port) async {
  var prev = -1;
  var stable = 0;
  for (var i = 0; i < 60; i++) {
    final s = await _eval(
      port,
      '(() => { const se = document.scrollingElement||document.documentElement;'
      'return document.readyState + ":" + (se.scrollHeight - se.clientHeight); })()',
    );
    if (s is String && s.contains(':')) {
      final v = int.tryParse(s.split(':')[1]) ?? 0;
      if (v == prev && v > 1000) {
        stable++;
        if (stable >= 3) return;
      } else {
        stable = 0;
      }
      prev = v;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

Future<int?> _launch(String bookId) async {
  final env = Map<String, String>.from(Platform.environment);
  env['PAGEREADER_OPEN'] = bookId;
  await Process.start(exe, const [], environment: env);
  final pf = File(
    p.join(
      Platform.environment['APPDATA']!,
      'com.pagereader',
      'PageReader',
      'browser-profile',
      'DevToolsActivePort',
    ),
  );
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (pf.existsSync()) {
      final l = pf.readAsLinesSync();
      if (l.isNotEmpty) {
        final v = int.tryParse(l.first.trim());
        if (v != null) return v;
      }
    }
  }
  return null;
}

Future<void> _killAll() async {
  await Process.run('taskkill', ['/F', '/IM', 'pagereader.exe']);
  final r = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    r'Get-CimInstance Win32_Process -Filter "Name=''msedge.exe''" | '
        r'Where-Object { $_.CommandLine -like ''*com.pagereader*'' } | '
        r'Select-Object -ExpandProperty ProcessId',
  ]);
  for (final s in (r.stdout as String).split(RegExp(r'\s+'))) {
    final pid = int.tryParse(s);
    if (pid != null) await Process.run('taskkill', ['/F', '/PID', '$pid']);
  }
}

Future<void> _del(String path) async {
  for (var i = 0; i < 6; i++) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
      final d = Directory(path);
      if (d.existsSync()) d.deleteSync(recursive: true);
      return;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
}

Future<List<String>?> _readDb(String db) async {
  if (!File(db).existsSync()) return null;
  final r = await Process.run('sqlite3', [
    db,
    "SELECT url, anchor_json FROM progress_entries WHERE book_id='b-rust' ORDER BY updated_at DESC LIMIT 1;",
  ]);
  if (r.exitCode != 0) return null;
  final out = (r.stdout as String).trim();
  if (out.isEmpty) return null;
  final i = out.indexOf('|');
  return i < 0 ? [out, ''] : [out.substring(0, i), out.substring(i + 1)];
}

double? _ratio(List<String>? row) {
  if (row == null) return null;
  final m = RegExp(r'"docRatio"\s*:\s*([0-9.]+)').firstMatch(row[1]);
  return m == null ? null : double.tryParse(m.group(1)!);
}

Future<void> _cdp(
  int port,
  String method,
  Map<String, dynamic> params,
  Future<void> Function(List<Map<String, dynamic>>) then,
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
    final pending = <int, Completer<Map<String, dynamic>>>{};
    var id = 0;
    ws.listen((d) {
      final m = jsonDecode(d as String) as Map<String, dynamic>;
      final i = m['id'];
      if (i is int) pending.remove(i)?.complete(m);
    });
    Future<Map<String, dynamic>> send(
      String m,
      Map<String, dynamic> pm,
    ) {
      final n = ++id;
      final comp = Completer<Map<String, dynamic>>();
      pending[n] = comp;
      ws.add(jsonEncode({'id': n, 'method': m, 'params': pm}));
      return comp.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => <String, dynamic>{},
      );
    }

    final r = await send(method, params);
    final infos =
        ((r['result'] as Map<String, dynamic>?)?['targetInfos'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    await then(infos);
    await ws.close();
  } catch (_) {}
}

Future<dynamic> _eval(int port, String expr) async {
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
    final pending = <int, Completer<Map<String, dynamic>>>{};
    var id = 0;
    ws.listen((d) {
      final m = jsonDecode(d as String) as Map<String, dynamic>;
      final i = m['id'];
      if (i is int) pending.remove(i)?.complete(m);
    });

    Future<Map<String, dynamic>> send(
      String m,
      Map<String, dynamic> pm, [
      String? sid,
    ]) {
      final n = ++id;
      final comp = Completer<Map<String, dynamic>>();
      pending[n] = comp;
      final payload = <String, dynamic>{
        'id': n,
        'method': m,
        'params': pm,
      };
      if (sid != null) payload['sessionId'] = sid;
      ws.add(jsonEncode(payload));
      return comp.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => <String, dynamic>{},
      );
    }

    final t = await send('Target.getTargets', {});
    final infos =
        ((t['result'] as Map<String, dynamic>?)?['targetInfos'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final page = infos.firstWhere(
      (x) => x['type'] == 'page' && (x['url'] as String).contains('rust-lang'),
      orElse: () => <String, dynamic>{},
    );
    if (page.isEmpty) {
      await ws.close();
      return null;
    }
    final att = await send('Target.attachToTarget', {
      'targetId': page['targetId'],
      'flatten': true,
    });
    final sid = (att['result'] as Map<String, dynamic>?)?['sessionId']
        as String?;
    final r = await send('Runtime.evaluate', {
      'expression': expr,
      'returnByValue': true,
    }, sid);
    await ws.close();
    return ((r['result'] as Map<String, dynamic>?)?['result']
        as Map<String, dynamic>?)?['value'];
  } catch (_) {
    return null;
  }
}
