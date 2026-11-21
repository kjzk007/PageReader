import 'package:flutter/material.dart';

/// 深色引擎状态条。
///
/// ── 为什么需要它 ──
///
/// Android 上没有 DevTools，引擎注入后如果失败（语法错误、极点配置错、
/// 注入时机不对），用户只会看到「页面没变色」或「一片黑」，
/// 完全不知道卡在哪。
///
/// 引擎现在会自报一条状态（背景色、错误列表、被改写的元素数），
/// 这个组件把它显示成一条浮在页面顶部的小条。
///
/// 正常时不显眼（半透明绿），出错时才变醒目。
class DarkStatusBadge extends StatelessWidget {
  const DarkStatusBadge({super.key, required this.report});

  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    // ok 有三种值：
    //   true  → 引擎跑完了
    //   false → 明确失败
    //   null  → 未知（runJavaScript 调用成功但没拿到执行结果）
    final okRaw = report['ok'];
    final ok = okRaw == true;
    final unknown = okRaw == null;
    // 错误可能来自两处：Dart 侧的 runJavaScript 抛错（error 单值），
    // 或引擎内部的 __prDarkErrors（errors 列表）。都要显示。
    final errors = <String>[
      if ((report['error'] as String?)?.isNotEmpty ?? false) report['error'] as String,
      if ((report['note'] as String?)?.isNotEmpty ?? false) report['note'] as String,
      ...((report['errors'] as List?) ?? const []).map((e) => e.toString()),
    ];
    final styled = report['styled'] as int? ?? 0;
    final bg = report['bg'] as String? ?? '(未设置)';
    final mode = report['mode'];

    // 判定「真的生效了」：没报错、且改写了足够多的元素。
    //
    // 阈值取 20 —— 正常页面动辄几百个元素被改写；低于 20 说明
    // 引擎跑起来了但几乎没找到可算色的节点，实际是失败的。
    final effective = ok && errors.isEmpty && styled >= 20;
    final color = effective
        ? const Color(0xFF4ADE80)
        : (unknown
              ? const Color(0xFF5AC8FA)
              : (ok ? const Color(0xFFFFB454) : const Color(0xFFFF6B6B)));
    final title = effective
        ? '深色已生效'
        : (unknown
              ? '注入已调用，结果未知'
              : (ok ? '注入了但几乎没改写元素' : '注入失败'));

    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xE61C1E22),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Microsoft YaHei',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '背景 $bg   模式 $mode   改写 $styled 个元素',
              style: const TextStyle(
                color: Color(0xFF8A9099),
                fontSize: 10.5,
                fontFamily: 'Consolas',
              ),
            ),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final e in errors.take(3))
                Text(
                  '· $e',
                  style: const TextStyle(
                    color: Color(0xFFFF8A8A),
                    fontSize: 10,
                    fontFamily: 'Consolas',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}