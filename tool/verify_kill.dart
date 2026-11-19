// 单独验证"断电/强杀"场景。
//
// 关键:不能用外部 CDP 去滚动 —— 那是另一个 session,应用收不到。
// 必须用应用自己认领的那个窗口。这里通过读应用日志确认上报发生。
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
  final log = p.join(Platform.environment['TEMP']!, 'pr_kill.log');

  await _killAll();
  await _del(profile);
  await _del(db);
  await Future<void>.delayed(const Duration(seconds: 1));

  // 启动,把 stdout 写到文件,后面靠日志判断上报
  final env = Map<String, String>.from(Platform.environment);
  env['PAGEREADER_OPEN'] = 'b-rust';
  final app = await Process.start(
    exe,
    const [],
    environment: env,
  );
  final sb = StringBuffer();
  app.stdout.transform(utf8.decoder).listen(sb.write);
  app.stderr.transform(utf8.decoder).listen((_) {});

  final pf = File(p.join(profile, 'DevToolsActivePort'));
  int? port;
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (pf.existsSync()) {
      final l = pf.readAsLinesSync();
      if (l.isNotEmpty) {
        port = int.tryParse(l.first.trim());
        if (port != null) break;
      }
    }
  }
  check('浏览器已启动', port != null);
  if (port == null) return 1;

  // 等页面稳定 + 应用完成认领
  await Future<void>.delayed(const Duration(seconds: 10));

  // 用外部 CDP 滚动,但等待足够久,看应用是否通过 scroll 事件收到
  stdout.writeln('滚到 3300(外部 CDP 只是触发器,真正的上报来自页面自己的 scroll 监听)');
  _scroll(port, 3300);
  await Future<void>.delayed(const Duration(seconds: 4));

  // 看日志里有没有这次上报
  final logged = sb.toString();
  final hit = logged.contains('y=3300');
  check('页面把自己的滚动位置上报了(应用日志可见)', hit, '日志里没找到 y=3300');

  final before = _ratio(await _readDb(db));
  stdout.writeln('  硬杀前库里 = $before');

  // 硬杀:不走 QuitGuard
  await _killAll();
  await Future<void>.delayed(const Duration(seconds: 2));

  final after = _ratio(await _readDb(db));
  final maxScroll = await 0; // 占位,下面用固定值比较
  stdout.writeln('  硬杀后库里 = $after');

  // 3300/9000 = 0.3667
  check(
    '硬杀后位置仍在(说明上报已落库,不依赖正常退出)',
    after != null && (after - 0.3667).abs() < 0.02,
    '库里 $after,期望约 0.3667',
  );

  await _killAll();
  stdout.writeln('');
  stdout.writeln(fail == 0 ? '=== 全部通过 ===' : '=== $fail 项失败 ===');
  return fail;
}

Future<void> _scroll(int port, int y) {
  await _eval(
    port,
    '(() => { const se = document.scrollingElement||document.documentElement;'
    'se.scrollTop = $y; window.scrollTo(0, $y); return window.scrollY; })()',
  );
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
