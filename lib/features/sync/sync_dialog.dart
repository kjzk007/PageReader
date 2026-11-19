import 'package:flutter/material.dart';

/// 同步对话框。
///
/// 现状:同步功能还没实现。这个对话框如实说明,
/// 不做一个"看起来很能同步"的假界面 ——
/// 那比没有入口更糟。
///
/// 等真正的同步做好后,这里会变成:
///   1. 扫描局域网找桌面端(或手动填地址/配对码)
///   2. 双向合并书架与进度
///   3. 展示本次同步了多少条
class SyncDialog extends StatelessWidget {
  const SyncDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const SyncDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF191B1F),
      title: const Text(
        '与桌面端同步',
        style: TextStyle(
          color: Color(0xFFF2F3F5),
          fontSize: 17,
          fontFamily: 'Microsoft YaHei',
        ),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 未实现的状态,直接说清楚。
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2418),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF3D3320)),
                ),
                child: const Text(
                  '还没做',
                  style: TextStyle(
                    color: Color(0xFFD9B36C),
                    fontSize: 11,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '同步会在同一个局域网内直连你的桌面端，'
                '双向合并书架和阅读进度。不需要云端账号。',
                style: TextStyle(
                  color: Color(0xFF9AA0A6),
                  fontSize: 13,
                  fontFamily: 'Microsoft YaHei',
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
              _row(
                Icons.wifi_tethering,
                '同一 Wi-Fi',
                '手机和电脑连在同一个路由器下',
              ),
              _row(
                Icons.qr_code_2,
                '一次配对',
                '桌面端显示一个配对码，输入一次即可',
              ),
              _row(
                Icons.merge_type,
                '双向合并',
                '两边都读过的书，取更靠后的进度',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            '知道了',
            style: TextStyle(color: Color(0xFF5AC8FA), fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _row(IconData icon, String title, String detail) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF5F656C)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFC9CDD3),
                    fontSize: 12,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Color(0xFF5F656C),
                    fontSize: 11,
                    fontFamily: 'Microsoft YaHei',
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
