// 真机验收:真实 exe + 真实 SQLite + 真实浏览器。
//
// 回答用户的两个质问:
//   1. 阅读窗口有没有标签栏/地址栏
//   2. 读到某处关掉再开,能不能回到原位置
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

  // ---- 首次打开 ----
  stdout.writeln('=== 首次打开 ===');
  var port = await _launchApp('b-rust');
  check('浏览器已启动', port != null);
  if (port == null) return 1;

  var urls = await _pageUrls(port);
  stdout.writeln('  pages = $urls');
  check(
    '只有一个页面且是目标页',
    urls.length == 1 && urls.first.contains('rust-lang'),
    '$urls',
  );

  // ---- 滚到 60%,等记录器 ----
  stdout.writeln('=== 滚到 60% 并等待落库 ===');
  // 先等页面真的加载出内容:scrollHeight 必须明显大于视口
  for (var i = 0; i < 40; i++) {
    final ready = await _evalOnPage(port,
      '(() => { const se = document.scrollingElement || document.documentElement;'
      'return document.readyState + ":" + se.scrollHeight; })()');
    stdout.writeln('    等待加载: $ready');
    if (ready is String && ready.contains(':') ) {
      final h = int.tryParse(ready.split(':')[1]) ?? 0;
      if (ready.startsWith('complete') && h > 2000) break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  // 等布局稳定(与引擎里的逻辑一致):高度连续两次一样再动
  var lastH = -1;
  for (var i = 0; i < 25; i++) {
    final h = await _evalOnPage(port,
      '(() => { const se = document.scrollingElement || document.documentElement;'
      'return (se ? se.scrollHeight - se.clientHeight : 0) | 0; })()');
    final hh = h is num ? h.toInt() : 0;
    if (hh == lastH && hh > 0) { stdout.writeln('  布局稳定,可滚 ${hh}px'); break; }
    lastH = hh;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  final eval1 = await _evalOnPage(port, '''
    (() => {
      const se = document.scrollingElement || document.documentElement;
      const target = Math.floor((se.scrollHeight - se.clientHeight) * 0.6);
      se.scrollTop = target;
      window.scrollTo(0, target);
      return JSON.stringify({target: target, y: window.scrollY, st: se.scrollTop,
        max: se.scrollHeight - se.clientHeight});
    })()
  ''');
  stdout.writeln('  滚动结果 = $eval1');
  await Future<void>.delayed(const Duration(seconds: 1));
  final check1 = await _evalOnPage(port, '''
    (() => { const se = document.scrollingElement||document.documentElement;
      const max = se.scrollHeight - se.clientHeight;
      return max > 0 ? (window.scrollY || se.scrollTop)/max : -1; })()
  ''');
  stdout.writeln('  确认 ratio = $check1');
  await Future<void>.delayed(const Duration(seconds: 10));

  // ---- 查库 ----
  stdout.writeln('=== 查数据库 ===');
  final row = await _readDb(db);
  check('库里有 b-rust 的进度', row != null);
  double storedRatio = -1;
  if (row != null) {
    stdout.writeln('  url = ${row[0]}');
    stdout.writeln('  anchor = ${row[1]}');
    final m = RegExp(r'"docRatio"\s*:\s*([0-9.]+)').firstMatch(row[1]);
    storedRatio = m == null ? -1 : (double.tryParse(m.group(1)!) ?? -1);
    check('docRatio 已记录且 > 0.3', storedRatio > 0.3, 'ratio=$storedRatio');
  }

  // ---- 关掉 ----
  stdout.writeln('=== 全部关闭 ===');
  await _killAll();
  await Future<void>.delayed(const Duration(seconds: 2));

  // ---- 重开 ----
  stdout.writeln('=== 重新打开 ===');
  port = await _launchApp('b-rust');
  check('第二次浏览器已启动', port != null);
  if (port == null) return 1;

  await Future<void>.delayed(const Duration(seconds: 5));
  final diag = await _evalOnPage(port,
    'JSON.stringify({y: window.scrollY, se: (document.scrollingElement||document.documentElement).scrollTop, sh: (document.scrollingElement||document.documentElement).scrollHeight, ch: (document.scrollingElement||document.documentElement).clientHeight, hasPr: typeof window.__pr})');
  stdout.writeln('  重开诊断 = $diag');
  final ratioNow = await _evalOnPage(port, '''
    (() => { const el = document.scrollingElement||document.documentElement;
      const max = el.scrollHeight - el.clientHeight;
      return max > 0 ? (window.scrollY||el.scrollTop)/max : -1; })()
  ''');
  final rn = ratioNow is num ? ratioNow.toDouble() : -1.0;
  stdout.writeln('  重开后 ratio = $rn  (上次存的 $storedRatio)');
  check('回到上次位置(>0.3)', rn > 0.3, 'ratio=$rn');

  await _killAll();
  stdout.writeln(fail == 0 ? '=== 全部通过 ===' : '=== $fail 项失败 ===');
  return fail;
}

// ----------------------------------------------------------------

Future<int?> _launchApp(String bookId) async {
  final env = Map<String, String>.from(Platform.environment);
  env['PAGEREADER_OPEN'] = bookId;
  await Process.start(exe, const [], environment: env);
  final portFile = File(
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
    if (portFile.existsSync()) {
      final l = portFile.readAsLinesSync();
      if (l.isNotEmpty) {
        final p0 = int.tryParse(l.first.trim());
        if (p0 != null) return p0;
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

Future<List<String>> _pageUrls(int port) async {
  final c = HttpClient();
  try {
    final res = await (await c.getUrl(
      Uri.parse('http://127.0.0.1:$port/json/list'),
    )).close();
    final b = await res.transform(utf8.decoder).join();
    return (jsonDecode(b) as List)
        .cast<Map<String, dynamic>>()
        .where((t) => t['type'] == 'page')
        .map((t) => t['url'] as String)
        .toList();
  } catch (_) {
    return const [];
  } finally {
    c.close();
  }
}

/// 通过 browser WS + flatten 在页面上执行 JS。
Future<dynamic> _evalOnPage(int port, String expr) async {
  try {
    final c = HttpClient();
    final res = await (await c.getUrl(
      Uri.parse('http://127.0.0.1:$port/json/version'),
    )).close();
    final body = await res.transform(utf8.decoder).join();
    c.close();
    final wsUrl =
        (jsonDecode(body) as Map<String, dynamic>)['webSocketDebuggerUrl']
            as String;

    final ws = await WebSocket.connect(wsUrl);
    final pending = <int, Completer<Map<String, dynamic>>>{};
    var nextId = 0;
    ws.listen((d) {
      final m = jsonDecode(d as String) as Map<String, dynamic>;
      final id = m['id'];
      if (id is int) pending.remove(id)?.complete(m);
    });

    Future<Map<String, dynamic>> send(
      String method,
      Map<String, dynamic> params, [
      String? sid,
    ]) {
      final id = ++nextId;
      final c0 = Completer<Map<String, dynamic>>();
      pending[id] = c0;
      final payload = <String, dynamic>{
        'id': id,
        'method': method,
        'params': params,
      };
      if (sid != null) payload['sessionId'] = sid;
      ws.add(jsonEncode(payload));
      return c0.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => <String, dynamic>{},
      );
    }

    final list = await send('Target.getTargets', {});
    final infos =
        ((list['result'] as Map<String, dynamic>?)?['targetInfos']
                as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    // 严格只认目标页:列表里可能还有 newtab 等,挑错了就会报 hasPr=undefined。
    final page = infos.firstWhere(
      (t) => t['type'] == 'page' && (t['url'] as String).contains('rust-lang'),
      orElse: () => <String, dynamic>{},
    );
    final tid = page['targetId'] as String?;
    if (tid == null) {
      await ws.close();
      return null;
    }
    final att = await send('Target.attachToTarget', {
      'targetId': tid,
      'flatten': true,
    });
    final sid = (att['result'] as Map<String, dynamic>?)?['sessionId']
        as String?;
    if (sid == null) {
      await ws.close();
      return null;
    }
    final r = await send('Runtime.evaluate', {
      'expression': expr,
      'returnByValue': true,
    }, sid);
    await ws.close();
    final inner =
        (r['result'] as Map<String, dynamic>?)?['result']
            as Map<String, dynamic>?;
    return inner?['value'];
  } catch (e) {
    stdout.writeln('  eval 失败: $e');
    return null;
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
  final idx = out.indexOf('|');
  if (idx < 0) return [out, ''];
  return [out.substring(0, idx), out.substring(idx + 1)];
}
