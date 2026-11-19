// 验收:进度记录与关窗恢复。
//
// 重要:绝不碰用户的真实数据。
// 之前的版本会删除 %APPDATA%\com.pagereader\PageReader 下的
// pagereader.sqlite,导致用户手动添加的书全被清空 ——
// 那是开发工具污染了产品数据,不可接受。
//
// 现在改为:用独立的 PAGEREADER_DATA_DIR 让应用指向临时目录,
// 验收只在临时目录里折腾,用户数据原封不动。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'paths.dart';

import 'package:path/path.dart' as p;

const exe = exePath();

/// 项目根目录。用于对比 exe 与源码的时间戳。
const rootDir = projectRoot();

/// 路径分隔符,避免在字符串插值里写 ${...}。
final pathSep = Platform.pathSeparator;

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

  // 独立的临时数据目录,与用户真实环境完全隔离。
  final sandbox = Directory.systemTemp.createTempSync('pr-verify-');
  final profile = p.join(sandbox.path, 'browser-profile');
  final db = p.join(sandbox.path, 'pagereader.sqlite');
  stdout.writeln('沙箱目录: ${sandbox.path}');
  stdout.writeln('');

  // ---------------------------------------------------------------
  // 先校验构建产物是不是最新的。
  //
  // 为什么必须做这一步:
  // `flutter build windows` 会报 "√ Built",但增量构建有时并不真正
  // 重新链接 exe。表现是:代码改了、构建显示成功、跑起来却还是旧行为。
  // 这个坑实际踩过 —— exe 停留在 8 小时前,用户反复测试发现插件/
  // 新功能都没生效,而所有"验证"都是在沙箱里用别的方式做的,
  // 从没验证过用户真正运行的那个 exe。
  //
  // 判定方式:exe 的修改时间必须晚于 lib/ 下最新的源码文件。
  // 不满足就直接报错退出,而不是给出"通过"的假象。
  stdout.writeln('[0] 构建产物校验');
  final exeFile = File(exe);
  if (!exeFile.existsSync()) {
    stdout.writeln('FAIL 找不到可执行文件: $exe');
    stdout.writeln('     先跑 flutter build windows --debug');
    return 1;
  }
  final exeTime = exeFile.lastModifiedSync();
  DateTime? newestSource;
  String? newestPath;
  for (final e in Directory(p.join(rootDir, 'lib')).listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    if (e.path.contains('$pathSep.dart_tool')) continue;
    if (e.path.endsWith('.g.dart')) continue;
    final t = e.lastModifiedSync();
    if (newestSource == null || t.isAfter(newestSource)) {
      newestSource = t;
      newestPath = e.path;
    }
  }
  if (newestSource != null && newestSource.isAfter(exeTime)) {
    stdout.writeln('FAIL exe 比源码旧,跑的是旧程序');
    stdout.writeln('     exe: $exeTime');
    stdout.writeln('     源码: $newestSource  ($newestPath)');
    stdout.writeln('     处理: 删掉 build/windows 后重建');
    stdout.writeln('           Remove-Item build\\windows -Recurse -Force');
    stdout.writeln('           flutter build windows --debug');
    return 1;
  }
  stdout.writeln('PASS exe 是最新的 ($exeTime)');
  stdout.writeln('');

  Future<void> killAll() async {
    await Process.run('taskkill', ['/F', '/IM', 'pagereader.exe']);
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      r'Get-CimInstance Win32_Process -Filter "Name=''msedge.exe''" | '
          r'Where-Object { $_.CommandLine -like ''*pr-verify-*'' } | '
          r'Select-Object -ExpandProperty ProcessId',
    ]);
    for (final s in (r.stdout as String).split(RegExp(r'\s+'))) {
      final pid = int.tryParse(s);
      if (pid != null) await Process.run('taskkill', ['/F', '/PID', '$pid']);
    }
  }

  Future<int?> launch(String bookId) async {
    final env = Map<String, String>.from(Platform.environment);
    env['PAGEREADER_OPEN'] = bookId;
    env['PAGEREADER_DATA_DIR'] = sandbox.path;
    await Process.start(exe, const [], environment: env);
    final pf = File(p.join(profile, 'DevToolsActivePort'));
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (pf.existsSync()) {
        final l = pf.readAsLinesSync();
        if (l.isNotEmpty) {
          final v = int.tryParse(l.first.trim());
          if (v != null) {
            // 端口文件出现不等于端口可用,确认能连上再返回。
            if (await _portAlive(v)) return v;
          }
        }
      }
      if (i == 20) stdout.writeln('  (等待浏览器就绪…)');
    }
    stdout.writeln('  ERROR 30 秒内没拿到可用端口');
    return null;
  }

  try {
    await killAll();
    await Future<void>.delayed(const Duration(seconds: 1));

    // ---------- 1. 打开书 ----------
    stdout.writeln('[1] 打开书');
    var port = await launch('b-rust');
    check('浏览器已启动', port != null, 'port=$port');
    if (port == null) return 1;

    final urls = await _pageUrls(port);
    check('窗口里有目标页', urls.any((u) => u.contains('rust-lang')), '$urls');

    // ---------- 2. 采集并落库 ----------
    stdout.writeln('');
    stdout.writeln('[2] 滚动并等上报');
    await _waitContent(port);
    // 先确认注入脚本就位,再滚动 —— 否则滚动事件没人监听。
    final ready = await _waitInjection(port);
    check('注入脚本已就位', ready, 'window.__pr 或 __prReport 缺失');
    if (!ready) return 1;

    // 滚动到中间位置。
    //
    // 必须先确认滚动真的发生了 —— 页面可能因为懒加载在滚动后
    // 重置 scrollTop,或者滚动容器不是 documentElement。
    // 之前直接滚动就等 8 秒,经常读到 docRatio=0(根本没动)。
    await _scrollTo(port, 4200);
    await Future<void>.delayed(const Duration(milliseconds: 800));

    // 回读确认。偏低就再滚一次,给懒加载一点时间稳定。
    for (var attempt = 0; attempt < 3; attempt++) {
      final y = await _eval(port, 'String(window.scrollY || 0)');
      final scrolled = int.tryParse(y?.toString() ?? '0') ?? 0;
      if (scrolled > 1000) {
        stdout.writeln('  已滚动到 y=$scrolled');
        break;
      }
      stdout.writeln('  滚动未生效(y=$scrolled),重试 ${attempt + 1}/3');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _scrollTo(port, 4200);
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }

    // 上报链路:scroll 事件 → 800ms 防抖 → CDP bindingCalled
    // → ProgressRecorder → SQLite。整条链路有延迟。
    //
    // 不能只等固定时长再读一次:实测有约 20% 的概率读到初始的
    // docRatio=0(页首那条),而此时滚动确实发生了(y=4200)。
    // 说明上报还在路上。改成轮询:最多等 20 秒,直到读到 > 0.1。
    List<String>? row;
    double? ratio;
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      row = await _readDb(db);
      if (row == null) continue;
      final m = RegExp(r'"docRatio"\s*:\s*([0-9.]+)').firstMatch(row[1]);
      ratio = m == null ? null : double.tryParse(m.group(1)!);
      if (ratio != null && ratio > 0.1) break;
    }

    check('库里有进度', row != null, '$row');
    if (row != null) {
      stdout.writeln('  docRatio=$ratio');
      check('比例大于 0', ratio != null && ratio > 0.1);
    }

    // ---------- 3. 关窗记录 ----------
    stdout.writeln('');
    stdout.writeln('[3] 关窗');
    await _scrollTo(port, 7100);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _closeWindow(port);
    await Future<void>.delayed(const Duration(seconds: 3));

    final row2 = await _readDb(db);
    check('关窗那一刻已记录', row2 != null);
    if (row2 != null) {
      final m = RegExp(r'"docRatio"\s*:\s*([0-9.]+)').firstMatch(row2[1]);
      final r2 = m == null ? null : double.tryParse(m.group(1)!);
      stdout.writeln('  docRatio=$r2');
      check('记录的是关窗位置', r2 != null && r2 > 0.5, '$r2');
    }

    // ---------- 4. 重开恢复 ----------
    stdout.writeln('');
    stdout.writeln('[4] 重开恢复');
    await killAll();
    await Future<void>.delayed(const Duration(seconds: 2));
    // 清掉旧端口文件,避免读到已失效的端口
    final pf = File(p.join(profile, 'DevToolsActivePort'));
    if (pf.existsSync()) pf.deleteSync();

    port = await launch('b-rust');
    check('第二次启动', port != null);
    if (port != null) {
      await _waitContent(port);
      await Future<void>.delayed(const Duration(seconds: 4));
      final y = await _eval(port, 'window.scrollY');
      final yn = y is num ? y.toDouble() : -1;
      stdout.writeln('  重开后 scrollY=$yn(目标约 7100)');
      check('回到上次位置', yn > 3000, 'y=$yn');
    }

    // ---------- 5. 种子数据完整性 ----------
    stdout.writeln('');
    stdout.writeln('[5] 沙箱里是干净的种子数据');
    final titles = await _sql(db, "SELECT title FROM books WHERE deleted_at IS NULL;");
    final titleList = titles.split('\n').where((s) => s.trim().isNotEmpty).toList();
    stdout.writeln('  共 ${titleList.length} 本');
    check('种子书齐全(6 本)', titleList.length == 6, '$titleList');
  } finally {
    await killAll();
    // 退出后删掉沙箱,不污染系统。
    await Future<void>.delayed(const Duration(seconds: 1));
    try {
      sandbox.deleteSync(recursive: true);
    } catch (_) {}
  }

  stdout.writeln('');
  stdout.writeln(fail == 0 ? '══════ 全部通过 ══════' : '══════ $fail 项失败 ══════');
  // 强制退出:Dart 的 HttpClient / WebSocket 即使 close 过,
  // 内部连接池仍可能挂住事件循环,导致脚本跑完却退不出去
  // (表现为"输出完整但不返回")。验收脚本用 exit 是合理的。
  await Future<void>.delayed(const Duration(milliseconds: 200));
  exit(fail);
}

// ----------------------------------------------------------------

/// 确认端口真的能接受 HTTP 请求。
Future<bool> _portAlive(int port) async {
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    final res = await (await c.getUrl(
      Uri.parse('http://127.0.0.1:$port/json/version'),
    )).close().timeout(const Duration(seconds: 3));
    await res.drain<void>();
    c.close();
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
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

/// 等注入脚本就位。
///
/// window.__pr 和 window.__prReport 是锚点采集与上报的前提。
/// 没有它们,滚动再多次也不会有任何记录 ——
/// 之前验收失败就是没确认这一步。
/// 等注入脚本就位。
///
/// 判定条件要同时满足两条,缺一不可:
///   1. `document.readyState === 'complete'` —— 页面真的加载完了。
///      浏览器冷启动时 document 可能是空的,此时 `__pr` 自然不存在,
///      早查只会白等一轮。
///   2. `__pr` 是 object 且 `__prReport` 是 function。
///
/// 之前的版本只查第 2 条、最多等 10 秒,冷启动时经常不够 ——
/// 表现为"注入脚本已就位 FAIL",但重跑一次又过。这种时序脆弱性
/// 必须靠等更久 + 明确的就绪条件解决,不能靠重试。
Future<bool> _waitInjection(int port) async {
  var waited = 0;
  while (waited < 45000) {
    final r = await _eval(
      port,
      '(() => {'
      'var se = document.scrollingElement || document.documentElement;'
      'var scrollable = se ? (se.scrollHeight - se.clientHeight) : 0;'
      'return document.readyState + ":" + typeof window.__pr + ":" +'
      ' typeof window.__prReport + ":" + scrollable;'
      '})()',
    );
    if (r is String) {
      final parts = r.split(':');
      final ready = parts[0] == 'complete';
      final hasPr = parts.length > 1 && parts[1] == 'object';
      final hasReport = parts.length > 2 && parts[2] == 'function';
      // 还要页面真的能滚动 —— 否则后面滚动测试没有意义。
      final scrollable = parts.length > 3 ? int.tryParse(parts[3]) ?? 0 : 0;
      if (ready && hasPr && hasReport && scrollable > 500) return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    waited += 500;
  }
  stdout.writeln('  (等了 ${waited ~/ 1000} 秒仍未就位)');
  return false;
}

Future<void> _scrollTo(int port, int y) async {
  await _eval(
    port,
    '(() => { const se = document.scrollingElement||document.documentElement;'
    'se.scrollTop = $y; window.scrollTo(0, $y); return window.scrollY; })()',
  );
}

Future<List<String>> _pageUrls(int port) async {
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    final res = await (await c.getUrl(
      Uri.parse('http://127.0.0.1:$port/json/list'),
    )).close();
    final list = jsonDecode(await res.transform(utf8.decoder).join()) as List;
    c.close();
    return list
        .cast<Map<String, dynamic>>()
        .where((t) => t['type'] == 'page')
        .map((t) => t['url'] as String)
        .toList();
  } catch (_) {
    return const [];
  }
}

Future<void> _closeWindow(int port) async {
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    final res = await (await c.getUrl(
      Uri.parse('http://127.0.0.1:$port/json/list'),
    )).close();
    final list = jsonDecode(await res.transform(utf8.decoder).join()) as List;
    c.close();
    final page = list.cast<Map<String, dynamic>>().firstWhere(
      (t) => t['type'] == 'page' && (t['url'] as String).contains('rust-lang'),
      orElse: () => <String, dynamic>{},
    );
    if (page.isEmpty) return;
    final c2 = HttpClient();
    await (await c2.getUrl(
      Uri.parse('http://127.0.0.1:$port/json/close/${page['id']}'),
    )).close();
    c2.close();
  } catch (_) {}
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

Future<String> _sql(String db, String q) async {
  final r = await Process.run('sqlite3', [db, q]);
  return (r.stdout as String).trim();
}

Future<dynamic> _eval(int port, String expr) async {
  try {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    final res = await (await c.getUrl(
      Uri.parse('http://127.0.0.1:$port/json/version'),
    )).close();
    final wsUrl =
        (jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>)['webSocketDebuggerUrl'] as String;
    c.close();
    final ws = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 10));
    final pending = <int, Completer<Map<String, dynamic>>>{};
    var id = 0;
    ws.listen(
      (d) {
        final m = jsonDecode(d as String) as Map<String, dynamic>;
        final i = m['id'];
        if (i is int) pending.remove(i)?.complete(m);
      },
      // 连接被对端关掉时,未完成的请求必须立刻失败,
      // 否则 await 会永远挂着 —— 这是之前脚本卡死的直接原因。
      onDone: () {
        for (final c in pending.values) {
          if (!c.isCompleted) c.complete({});
        }
        pending.clear();
      },
    );

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
