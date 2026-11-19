import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/settings.dart';
import '../../engine/desktop/extension_probe.dart';

/// 首次使用时的插件选择引导。
///
/// ── 为什么需要它 ──
///
/// 插件默认一个都不启用。新用户装完软件直接打开书，一个插件都加载不上，
/// 而设置页里那个插件区块他未必会注意到 —— 结果就是"这软件说支持插件，
/// 但我打开书什么插件都没有"。
///
/// 所以在用户第一次打开书之前主动问一次：列出本机扫到的插件，
/// 默认全勾上（用户装了什么多半就是想用），他可以取消不想在阅读时
/// 生效的那几个。问过一次就不再打扰。
///
/// [ref] 接受 WidgetRef 或 ProviderContainer，两种都支持。
/// 因为书架是普通 StatefulWidget，没有 ref，只能从外部拿容器。
Future<void> showExtensionOnboarding(
  BuildContext context,
  ProviderContainer container,
) async {
  final settings = container.read(extensionSettingsProvider);
  if (settings.asked) return;

  // 扫描可能花几百毫秒，先给个占位。
  final all = ExtensionProbe.probe();
  if (!context.mounted) return;

  if (all.isEmpty) {
    // 本机没扫到插件 —— 记下"问过了"，避免每次打开书都走一遍。
    await container.read(extensionSettingsProvider.notifier).markAsked();
    return;
  }

  final chosen = await showDialog<Set<String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ExtensionOnboardingDialog(all: all),
  );

  final notifier = container.read(extensionSettingsProvider.notifier);
  await notifier.setEnabled(chosen ?? const {});
  await notifier.markAsked();
}

class _ExtensionOnboardingDialog extends StatefulWidget {
  const _ExtensionOnboardingDialog({required this.all});

  final List<BrowserExtension> all;

  @override
  State<_ExtensionOnboardingDialog> createState() =>
      _ExtensionOnboardingDialogState();
}

class _ExtensionOnboardingDialogState
    extends State<_ExtensionOnboardingDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    // 默认全选：用户装了什么插件，多半就是希望它生效。
    _selected = widget.all.map((e) => e.id).toSet();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF191B1F),
      title: const Text(
        '选择要在阅读时启用的插件',
        style: TextStyle(color: Color(0xFFF2F3F5), fontSize: 17),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '这些是你浏览器里已装的插件。勾选的会在阅读窗口里生效，'
              '插件本身不会被复制，用的就是原来那份。'
              '以后可以随时在「设置 → 浏览器插件」里调整。',
              style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 12),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.all.length,
                itemBuilder: (_, i) {
                  final ext = widget.all[i];
                  final on = _selected.contains(ext.id);
                  return CheckboxListTile(
                    value: on,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: const Color(0xFF7C9CFF),
                    checkColor: const Color(0xFF0E0F12),
                    title: Text(
                      ext.name,
                      style: const TextStyle(
                        color: Color(0xFFE3E5E8),
                        fontSize: 14,
                      ),
                    ),
                    subtitle: ext.version.isEmpty
                        ? null
                        : Text(
                            'v${ext.version}',
                            style: const TextStyle(
                              color: Color(0xFF6B7075),
                              fontSize: 11,
                            ),
                          ),
                    onChanged: (v) {
                      setState(() {
                        if (v ?? false) {
                          _selected.add(ext.id);
                        } else {
                          _selected.remove(ext.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(const <String>{}),
          child: const Text(
            '都不用',
            style: TextStyle(color: Color(0xFF9AA0A6)),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text(
            '确定',
            style: TextStyle(color: Color(0xFF7C9CFF)),
          ),
        ),
      ],
    );
  }
}
