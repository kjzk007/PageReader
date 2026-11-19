// 从大图生成所有平台所需的图标尺寸。
//
// 关键经验(踩了三轮):
//   1. 不能按每个尺寸调 Chrome `--screenshot --window-size=N,N` ——
//      小窗口下截到的只是图标左上角一块。
//   2. 也不能用 CDP 的 Page.captureScreenshot + clip —— 实测返回空数据。
//   3. 可靠路径:Chrome 只渲染一张 1024 大图(这个尺寸它工作正常),
//      其余尺寸用纯 Dart 的 image 包做高质量降采样。
//
// 这样只有一次外部依赖,且那一处是稳定的。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'paths.dart';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const svgPath = svgPath();
const outDir = iconOutDir();

/// 目标尺寸。Windows 的 ICO 需要多档,Android 是固定密度档。
const windowsSizes = [16, 24, 32, 48, 64, 128, 256];
const androidSizes = {
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};
const masterSize = 1024;

Future<void> main() async {
  final chrome = _findChrome();
  if (chrome == null) {
    stderr.writeln('找不到 Chrome/Edge');
    exit(1);
  }
  final dir = Directory(outDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);

  // 1. 生成正方形 SVG
  final svg = _buildSquareSvg();
  File('$outDir/app_icon_square.svg').writeAsStringSync(svg);

  // HTML 里必须用 CSS 让 svg 100% 铺满视口。
  //
  // 踩过的坑:只写 <svg width="532" height="532"> 时,
  // 浏览器按 532 CSS 像素渲染,而 --window-size=1024,1024 的视口
  // 可能更大(受设备像素比影响),结果 SVG 只占左上角约 1/4,
  // 其余全是透明 —— 缩到 256px 时图标看着只有 1/4 大。
  // 用 width:100vw;height:100vh 强制铺满,再截图就准了。
  final html = File('$outDir/render.html');
  html.writeAsStringSync(
    '<!DOCTYPE html><html><head><meta charset="utf-8">'
    '<style>'
    'html,body{margin:0;padding:0;overflow:hidden;background:transparent}'
    'svg{display:block;width:100vw;height:100vh}'
    '</style></head><body>$svg</body></html>',
  );

  // 2. Chrome 只渲染 1024 这一张
  final masterPng = await _renderMaster(chrome, html);
  if (masterPng == null) {
    stderr.writeln('主图渲染失败');
    exit(1);
  }
  File('$outDir/icon_master_1024.png').writeAsBytesSync(masterPng);
  stdout.writeln('主图: ${masterSize}px  ${masterPng.length ~/ 1024}KB');

  // 3. 纯 Dart 降采样
  final master = img.decodePng(masterPng);
  if (master == null) {
    stderr.writeln('主图解码失败');
    exit(1);
  }
  stdout.writeln('主图尺寸: ${master.width}x${master.height}');

  final allSizes = <int>{...windowsSizes, ...androidSizes.values, 512}.toList()
    ..sort();
  final rendered = <int, Uint8List>{};
  for (final size in allSizes) {
    var resized = img.copyResize(
      master,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );
    // 小尺寸锐化(力度要轻)。
    //
    // 白底 + 金色细描边的组合,锐化过猛会在描边外缘产生
    // 彩色光晕(金色被强化成黄边),反而更脏。
    // 这里用温和的 5 点锐化,只让字母边界稍微立起来。
    if (size <= 64) {
      resized = img.convolution(
        resized,
        filter: [
          0, -0.35, 0,
          -0.35, 2.4, -0.35,
          0, -0.35, 0,
        ],
        div: 1.0,
      );
    }
    final png = Uint8List.fromList(img.encodePng(resized));
    rendered[size] = png;
    File('$outDir/icon_$size.png').writeAsBytesSync(png);
    stdout.writeln('  ${size}px → ${png.length ~/ 1024}KB');
  }

  // 4. 打包 ICO
  final present = windowsSizes.where(rendered.containsKey).toList();
  final ico = _buildIco([for (final s in present) rendered[s]!], present);
  if (ico != null) {
    File('$outDir/app_icon.ico').writeAsBytesSync(ico);
    stdout.writeln('ICO: ${ico.length ~/ 1024}KB (${present.join("/")})');
  }

  stdout.writeln('');
  stdout.writeln('完成,产物在 $outDir');
}

String? _findChrome() {
  for (final p in [
    r'C:\Program Files\Google\Chrome\Application\chrome.exe',
    r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
  ]) {
    if (File(p).existsSync()) return p;
  }
  return null;
}

/// 包成正方形:圆角白色背景 + 居中放大。
///
/// 原始 SVG 的 viewBox 是 532x459,但实际绘制内容只占
/// x 81..429、y 157..340 这一块,四周全是空白 ——
/// 不放大就会得到一个"小图居中、四边大片留白"的图标,
/// 缩到 16px 时字母只剩几像素。
///
/// 背景用白色(用户指定):PR 本身是深炭黑填充 + 金色描边,
/// 放在白底上对比度最高。深色底会让深色字母吃掉一半对比,
/// 缩到任务栏尺寸时几乎看不清。
String _buildSquareSvg() {
  final raw = File(svgPath).readAsStringSync();
  final defs = RegExp(r'<defs>[\s\S]*?</defs>').firstMatch(raw)?.group(0) ?? '';
  final body = raw
      .replaceAll(RegExp(r'^[\s\S]*?<svg[^>]*>'), '')
      .replaceAll('</svg>', '')
      .replaceAll(defs, '')
      .trim();

  // 内容中心:x=(81+429)/2=255, y=(157+340)/2=248.5
  // 画布中心:266,266
  // 放大 1.35 倍让内容占约 88%
  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 532 532" width="532" height="532">
  $defs
  <rect x="0" y="0" width="532" height="532" rx="100" fill="#FFFFFF"/>
  <g transform="translate(266,266) scale(1.35) translate(-255,-248.5)">
    $body
  </g>
</svg>
''';
}

/// Chrome 渲染 1024 主图。
///
/// 只有这个尺寸可靠:窗口够大,截图区域和视口能对齐。
Future<Uint8List?> _renderMaster(String chrome, File html) async {
  final out = '$outDir/_master.png';
  final f = File(out);
  if (f.existsSync()) f.deleteSync();
  final profile = Directory.systemTemp.createTempSync('icon-master-');
  try {
    final r = await Process.run(chrome, [
      '--headless=new',
      '--disable-gpu',
      '--hide-scrollbars',
      '--default-background-color=00000000',
      '--force-device-scale-factor=1',
      '--window-size=$masterSize,$masterSize',
      '--user-data-dir=${profile.path}',
      '--screenshot=$out',
      'file:///${html.path.replaceAll('\\', '/')}',
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (r.exitCode != 0) {
      stderr.writeln('  chrome: ${r.stderr}');
    }
    if (!f.existsSync()) return null;
    return f.readAsBytesSync();
  } finally {
    try {
      profile.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// 组装 ICO。Vista 以后支持直接嵌 PNG,不必自己写 BMP 编码。
Uint8List? _buildIco(List<Uint8List> pngs, List<int> sizes) {
  if (pngs.isEmpty || pngs.length != sizes.length) return null;

  final out = BytesBuilder();
  out.add(_u16(0));
  out.add(_u16(1)); // type = icon
  out.add(_u16(pngs.length));

  var offset = 6 + 16 * pngs.length;
  final entries = BytesBuilder();
  for (var i = 0; i < pngs.length; i++) {
    final size = sizes[i];
    final data = pngs[i];
    entries.addByte(size >= 256 ? 0 : size);
    entries.addByte(size >= 256 ? 0 : size);
    entries.addByte(0);
    entries.addByte(0);
    entries.add(_u16(1));
    entries.add(_u16(32));
    entries.add(_u32(data.length));
    entries.add(_u32(offset));
    offset += data.length;
  }
  out.add(entries.takeBytes());
  for (final p in pngs) {
    out.add(p);
  }
  return out.takeBytes();
}

Uint8List _u16(int v) => Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF]);
Uint8List _u32(int v) => Uint8List.fromList([
  v & 0xFF,
  (v >> 8) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 24) & 0xFF,
]);

/// 未使用,保留以说明为何不在此处做编码转换。
String _note() => jsonEncode({});
