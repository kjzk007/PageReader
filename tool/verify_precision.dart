// 回答两个问题:
//   1. 滚到段落中间(不是章节开头)后关掉,重开能不能精确回到那一行?
//   2. 只滚动、不导航、不退出,进度会不会被自动保存?
//
// 这两个问题的答案决定了用户"读到一半关掉又要重新下拉"是否真的会发生。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'paths.dart';

import 'package:path/path.dart' as p;

const exe = exePath();
const scrollTarget = 4321; // 故意取一个有零头的像素值,章节标题不会恰好在这

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

  // ---------- 第一次:打开、滚到段落中间、不退出 ----------
  stdout.writeln('=== 打开并滚到 ${scrollTarget}px(段落中间)===');
  var port = await _launch('b-rust');
  if (port == null) {
    check('浏览器启动', false);
    return 1;
  }
  await _waitContent(port);

  final maxScroll = await _eval(
    port,
    '(() => { const se = document.scrollingElement||document.documentElement;'
    'return se.scrollHeight - se.clientHeight; })()',
  );
  stdout.writeln('  可滚高度 = $maxScroll');

  await _eval(
    port,
    '(() => { const se = document.scrollingElement||document.documentElement;'
    'se.scrollTop = $scrollTarget; window.scrollTo(0, $scrollTarget);'
    'return window.scrollY; })()',
  );
  final actual = await _eval(port, 'window.scrollY');
  stdout.writeln('  实际滚到 = $actual');

  // 停在段落中间,等 12 秒(远超过 5 秒停留阈值)
  stdout.writeln('  保持不动 12 秒,看是否自动落库…');
  await Future<void>.delayed(const Duration(seconds: 12));

  // ---------- 关键检查 1:只滚动不退出,库里有什么? ----------
  final mid = await _readDb(db);
  stdout.writeln('');
  stdout.writeln('=== 检查 1:滚动后库里的记录 ===');
  double? midRatio;
  if (mid == null) {
    stdout.writeln('  库里没有记录');
  } else {
    midRatio = _ratio(mid[1]);
    stdout.writeln('  url = ${mid[0]}');
    stdout.writeln('  docRatio = $midRatio');
    final expectRatio = scrollTarget / (maxScroll as num).toDouble();
    stdout.writeln('  本次滚动的真实比例 ≈ ${expectRatio.toStringAsFixed(4)}');
    check(
      '滚动会被自动保存(库里有接近当前位置的记录)',
      midRatio != null && (midRatio - expectRatio).abs() < 0.05,
      '库里 $midRatio,实际 $expectRatio',
    );
  }

  // ---------- 硬杀,模拟崩溃/断电 ----------
  stdout.writeln('');
  stdout.writeln('=== 硬杀应用(不走正常退出,不触发 flush)===');
  await _killAll();
  await Future<void>.delayed(const Duration(seconds: 2));

  // ---------- 第二次:重开,看落在哪 ----------
  stdout.writeln('=== 重开,检查落点 ===');
  port = await _launch('b-rust');
  if (port == null) {
    check('第二次浏览器启动', false);
    return 1;
  }
  await _waitContent(port);
  await Future<void>.delayed(const Duration(seconds: 4));

  final restored = await _eval(port, 'window.scrollY');
  final restoredNum = restored is num ? restored.toDouble() : -1;
  stdout.writeln('  重开后的 scrollY = $restoredNum(目标 $scrollTarget)');

  final delta = (restoredNum - scrollTarget).abs();
  stdout.writeln('  偏差 = ${delta.toStringAsFixed(1)}px');
  // 容差一屏的 1/6,约 130px;超过就说明"要重新下拉"的抱怨是真的
  check(
    '精确回到段落中间(偏差 < 130px)',
    delta < 130,
    '偏差 ${delta.toStringAsFixed(1)}px',
  );

  await _killAll();
  stdout.writeln('');
  if (midRatio == null) {
    stdout.writeln('结论:滚动不会自动保存,只有导航/退出才会写库。');
  }
  stdout.writeln(fail == 0 ? '=== 全部通过 ===' : '=== $fail 项失败 ===');
  return fail;
}

// ----------------------------------------------------------------

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

Future<void> _waitContent(int port) async {
  for (var i = 0; i < 40; i++) {
    final h = await _eval(
      port,
      '(() => { const se = document.scrollingElement||document.documentElement;'
      'return document.readyState + ":" + (se.scrollHeight - se.clientHeight); })()',
    );
    if (h is String && h.startsWith('complete')) {
      final v = int.tryParse(h.split(':')[1]) ?? 0;
      if (v > 1000) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
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

double? _ratio(String anchor) {
  final m = RegExp(r'"docRatio"\s*:\s*([0-9.]+)').firstMatch(anchor);
  return m == null ? null : double.tryParse(m.group(1)!);
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
