import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/webview_theme.dart';

/// 设置里的「注入能力」诊断行（仅 Android 显示）。
///
/// ── 为什么需要给用户看 ──
///
/// 主题设置在 Android 上能不能「不闪」，取决于这台设备的系统 WebView
/// 是否支持 `DOCUMENT_START_SCRIPT`。这不是靠猜能知道的，而且不同
/// 设备结果不一样 —— 所以直接把结论和 WebView 版本摆出来，
/// 用户自己就能判断，不用来回问。
///
/// 不支持时还给出可操作建议：更新 Android System WebView 通常能解决。
class InjectionCapabilitySection extends ConsumerStatefulWidget {
  const InjectionCapabilitySection({super.key});

  @override
  ConsumerState<InjectionCapabilitySection> createState() =>
      _InjectionCapabilitySectionState();
}

class _InjectionCapabilitySectionState
    extends ConsumerState<InjectionCapabilitySection> {
  InjectionCapability? _cap;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cap = await WebViewTheme.probe();
    if (!mounted) return;
    setState(() {
      _cap = cap;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final cap = _cap;
    if (cap == null) return const SizedBox.shrink();

    final ok = cap.documentStart;
    final color = ok ? const Color(0xFF4ADE80) : const Color(0xFFFFB454);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1E22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2C3038)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ok ? '主题设置会立即生效' : '主题设置会先闪一下',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            cap.summary,
            style: const TextStyle(
              color: Color(0xFF8A9099),
              fontSize: 11.5,
              height: 1.5,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
          if (cap.webViewVersion.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'WebView ${cap.webViewVersion}'
              '${cap.webViewPackage.isNotEmpty ? '  (${_shortPkg(cap.webViewPackage)})' : ''}',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 11,
                fontFamily: 'Consolas',
              ),
            ),
          ],
          if (!ok) ...[
            const SizedBox(height: 8),
            const Text(
              '想消除这一闪：在应用商店更新「Android System WebView」或 Chrome，'
              '让系统 WebView 升到较新版本即可。',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 11,
                height: 1.5,
                fontFamily: 'Microsoft YaHei',
              ),
            ),
          ],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '重新检测',
                style: TextStyle(
                  color: Color(0xFF5AC8FA),
                  fontSize: 11.5,
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 包名太长，只留最后两段。
  static String _shortPkg(String pkg) {
    final parts = pkg.split('.');
    if (parts.length <= 2) return pkg;
    return parts.sublist(parts.length - 2).join('.');
  }
}