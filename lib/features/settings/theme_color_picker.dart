import 'package:flutter/material.dart';

/// 任意颜色取色器。
///
/// 三块：色相条、饱和度-明度面板、十六进制输入。
/// 不做预设色板 —— 用户要的是「能选任何颜色」，
/// 给几个固定按钮反而是限制。
class ThemeColorPicker extends StatefulWidget {
  const ThemeColorPicker({
    super.key,
    required this.initial,
    required this.onChanged,
    this.title,
  });

  /// 初始颜色，#RRGGBB。
  final String initial;
  final ValueChanged<String> onChanged;
  final String? title;

  @override
  State<ThemeColorPicker> createState() => _ThemeColorPickerState();
}

class _ThemeColorPickerState extends State<ThemeColorPicker> {
  late HSVColor _hsv;
  late TextEditingController _hex;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _hsv = _parse(widget.initial);
    _hex = TextEditingController(text: _toHex(_hsv));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static HSVColor _parse(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length != 6) return const HSVColor.fromAHSV(1, 0, 0, 0.1);
    final v = int.tryParse(h, radix: 16) ?? 0x14161a;
    final c = Color(0xFF000000 | v);
    return HSVColor.fromColor(c);
  }

  static String _toHex(HSVColor hsv) {
    final c = hsv.toColor();
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }

  void _emit() {
    final hex = _toHex(_hsv);
    _syncing = true;
    _hex.text = hex;
    _syncing = false;
    widget.onChanged(hex);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.title!,
              style: const TextStyle(
                color: Color(0xFF8A9099),
                fontSize: 11.5,
                fontFamily: 'Microsoft YaHei',
              ),
            ),
          ),
        // 色相条
        SizedBox(
          height: 22,
          child: LayoutBuilder(
            builder: (ctx, box) {
              return GestureDetector(
                onTapDown: (d) => _setHue(d.localPosition.dx / box.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _setHue(d.localPosition.dx / box.maxWidth),
                child: CustomPaint(
                  painter: _HuePainter(_hsv.hue),
                  size: Size(box.maxWidth, 22),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        // 饱和度-明度面板
        SizedBox(
          height: 140,
          child: LayoutBuilder(
            builder: (ctx, box) {
              void pick(Offset p) {
                final s = (p.dx / box.maxWidth).clamp(0.0, 1.0);
                final v = 1 - (p.dy / box.maxHeight).clamp(0.0, 1.0);
                setState(() {
                  _hsv = _hsv.withSaturation(s).withValue(v);
                });
                _emit();
              }

              return GestureDetector(
                onTapDown: (d) => pick(d.localPosition),
                onPanUpdate: (d) => pick(d.localPosition),
                child: CustomPaint(
                  painter: _SvPainter(_hsv),
                  size: Size(box.maxWidth, 140),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 36,
              height: 30,
              decoration: BoxDecoration(
                color: _hsv.toColor(),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF3A3F47)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _hex,
                style: const TextStyle(
                  color: Color(0xFFE3E5E8),
                  fontSize: 13,
                  fontFamily: 'Consolas',
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '#RRGGBB',
                  hintStyle: TextStyle(color: Color(0xFF6B7280)),
                ),
                onChanged: (v) {
                  if (_syncing) return;
                  final t = v.trim();
                  if (t.length != 7 || !t.startsWith('#')) return;
                  final parsed = int.tryParse(t.substring(1), radix: 16);
                  if (parsed == null) return;
                  setState(() {
                    _hsv = HSVColor.fromColor(Color(0xFF000000 | parsed));
                  });
                },
                onSubmitted: (v) {
                  final t = v.trim();
                  if (t.length != 7 || !t.startsWith('#')) return;
                  final parsed = int.tryParse(t.substring(1), radix: 16);
                  if (parsed == null) return;
                  setState(() {
                    _hsv = HSVColor.fromColor(Color(0xFF000000 | parsed));
                  });
                  _emit();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _setHue(double ratio) {
    setState(() {
      _hsv = _hsv.withHue((ratio.clamp(0.0, 1.0)) * 360);
    });
    _emit();
  }
}

class _HuePainter extends CustomPainter {
  _HuePainter(this.hue);
  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final colors = <Color>[
      for (var i = 0; i <= 6; i++) HSVColor.fromAHSV(1, (i * 60).toDouble() % 360, 1, 1).toColor(),
    ];
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..shader = LinearGradient(colors: colors).createShader(rect),
    );
    // 当前色相标记
    final x = (hue / 360) * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 2, 0, 4, size.height),
        const Radius.circular(1),
      ),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}

class _SvPainter extends CustomPainter {
  _SvPainter(this.hsv);
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final base = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    // 白 → 纯色（饱和度）
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, base],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(rect),
    );
    // 透明 → 黑（明度）
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.transparent, Colors.black],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect),
    );
    // 当前点
    final x = hsv.saturation * size.width;
    final y = (1 - hsv.value) * size.height;
    canvas.drawCircle(Offset(x, y), 7, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(x, y),
      7,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_SvPainter old) =>
      old.hsv.hue != hsv.hue ||
      old.hsv.saturation != hsv.saturation ||
      old.hsv.value != hsv.value;
}