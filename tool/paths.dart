import 'dart:io';

import 'package:path/path.dart' as p;

/// tool/ 下所有脚本共用的路径解析。
///
/// ── 为什么需要 ──
///
/// 这些脚本原来把项目根目录写死成 `D:\PageReader`。别人 clone 下来
/// 放到别的路径就全跑不起来。现在统一从脚本自身位置往上推,
/// 与项目目录名、盘符都无关。
///
/// 约定:脚本都在 `<项目根>/tool/` 下,所以根 = 本文件的上两级。

/// 项目根目录。
String projectRoot() {
  // Platform.script 指向当前正在执行的脚本。
  final scriptPath = Platform.script.toFilePath();
  // <root>/tool/paths.dart → 上两级
  return p.dirname(p.dirname(scriptPath));
}

/// Windows 构建产物里的 exe 路径。
///
/// [mode] 是 `Debug` 或 `Release`。
String exePath([String mode = 'Debug']) => p.join(
  projectRoot(),
  'build',
  'windows',
  'x64',
  'runner',
  mode,
  'pagereader.exe',
);

/// Android APK 路径。
String apkPath([String mode = 'release']) => p.join(
  projectRoot(),
  'build',
  'app',
  'outputs',
  'flutter-apk',
  mode == 'release' ? 'app-release.apk' : 'app-debug.apk',
);

/// 图标源 SVG。
String svgPath() => p.join(projectRoot(), 'application_icon.svg');

/// 图标生成的临时输出目录。
///
/// 放在 `.icon-build` 而不是 `_scratch`:后者是开发期的杂物堆,
/// 已经在 .gitignore 里,但语义上不该用来放工具产物。
String iconOutDir() => p.join(projectRoot(), '.icon-build');

/// 验收脚本用的隔离数据目录。
///
/// **绝不能指向真实数据目录** —— 之前验收脚本直接删了用户的库,
/// 把人手动添加的书全清了。现在固定用项目内的临时目录。
String sandboxDataDir() => p.join(projectRoot(), '.verify-data');

/// 确认 exe 存在,不存在时给出可操作的提示。
bool requireExe(String path, {String mode = 'Debug'}) {
  if (File(path).existsSync()) return true;
  stderr.writeln('找不到构建产物: $path');
  stderr.writeln('先构建: flutter build windows --${mode.toLowerCase()}');
  return false;
}
