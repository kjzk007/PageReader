import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/domain/diagnostics.dart';
import '../../engine/desktop/cdp_engine.dart';

/// 诊断面板:把"进度到底有没有在记"摊开给用户看。
///
/// 这类工具最容易出的事故是进度静默丢失,而用户完全无法自查,
/// 最后只能反馈"不好用"。所以这里把端口、窗口数、最近一次上报时间
/// 全部显示出来 —— 出现问题时一眼能看出卡在哪一环。
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key, required this.engine});

  final CdpEngine engine;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  DiagnosticsSnapshot? _snapshot;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _refresh();
    // 两秒刷新一次:足够看出"上报是不是停了",又不费资源。
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final s = await widget.engine.diagnostics();
      if (!mounted) return;
      setState(() {
        _snapshot = s;
      });
    } catch (_) {
      // 诊断自己不该崩。
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _snapshot;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF15171B),
        title: const Text(
          '诊断',
          style: TextStyle(color: Color(0xFFF2F3F5), fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF9AA0A6)),
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _statusCard(s),
                const SizedBox(height: 16),
                _section('运行环境', [
                  ('浏览器', s.browserPath),
                  ('profile', s.profilePath),
                  ('DevTools 端口', s.port?.toString() ?? '未启动'),
                ]),
                const SizedBox(height: 16),
                _section('窗口', [
                  ('打开的阅读窗口', '${s.pageCount}'),
                  ('已映射的书', '${s.mappedBooks.length}'),
                ]),
                if (s.pageUrls.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final u in s.pageUrls)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 4),
                      child: Text(
                        u,
                        style: const TextStyle(
                          color: Color(0xFF6E747C),
                          fontSize: 11,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                _section('进度上报', [
                  ('累计次数', '${s.reportCount}'),
                  ('最近一次', _ago(s.lastReportAt)),
                  ('原因', s.lastReportReason ?? '—'),
                ]),
                if (s.lastError != null) ...[
                  const SizedBox(height: 16),
                  _errorCard(s.lastError!),
                ],
                if (s.degradedBooks.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _degradedCard(s.degradedBooks.length),
                ],
              ],
            ),
    );
  }

  Widget _statusCard(DiagnosticsSnapshot s) {
    final ok = s.healthy;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFF14251B) : const Color(0xFF2A1E14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ok ? const Color(0xFF2E5E3E) : const Color(0xFF5E3E2E),
        ),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            color: ok ? const Color(0xFF5FD07A) : const Color(0xFFFFB454),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ok ? '一切正常,进度正在记录' : _problemText(s),
              style: TextStyle(
                color: ok ? const Color(0xFF9AD9AC) : const Color(0xFFFFD7A8),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _problemText(DiagnosticsSnapshot s) {
    if (!s.engineRunning) return '未连上浏览器,进度不会记录';
    if (s.degradedBooks.isNotEmpty) {
      return '有 ${s.degradedBooks.length} 本书处于降级模式,进度会丢失';
    }
    if (s.lastError != null) return '最近出过错:请查看下方详情';
    return '状态异常';
  }

  Widget _section(String title, List<(String, String)> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF7C8188),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF15171B),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(
                          k,
                          style: const TextStyle(
                            color: Color(0xFF6E747C),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          v,
                          style: const TextStyle(
                            color: Color(0xFFC9CDD3),
                            fontSize: 12,
                            fontFamily: 'Consolas',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _errorCard(String error) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1414),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF5E2E2E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '最近一次错误',
            style: TextStyle(color: Color(0xFFFF9A9A), fontSize: 12),
          ),
          const SizedBox(height: 6),
          SelectableText(
            error,
            style: const TextStyle(
              color: Color(0xFFE0A0A0),
              fontSize: 11,
              fontFamily: 'Consolas',
            ),
          ),
        ],
      ),
    );
  }

  Widget _degradedCard(int count) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1E14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF5E3E2E)),
      ),
      child: Text(
        '有 $count 本书是用系统浏览器打开的,进度只能记到你打开时那个页面,'
        '之后的跳转不会记录。重新点开这本书会再试一次。',
        style: const TextStyle(color: Color(0xFFFFD7A8), fontSize: 12),
      ),
    );
  }

  String _ago(DateTime? at) {
    if (at == null) return '还没有上报过';
    final d = DateTime.now().difference(at);
    if (d.inSeconds < 5) return '刚刚';
    if (d.inSeconds < 60) return '${d.inSeconds} 秒前';
    if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
    return '${d.inHours} 小时前';
  }
}
