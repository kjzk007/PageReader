/**
 * 一键重建深色引擎：提取 → 合并 → 拼装。
 *
 * 上一次清理临时文件时把中间产物全删了，结果每次改骨架都要手动
 * 重跑四步。这里收口成一个脚本，中间文件放临时目录，跑完不留垃圾。
 *
 * 用法：
 *   node tool/dark_engine/build_all.js <解包目录>/inject/index.js
 *
 * 解包目录指的是从浏览器扩展目录复制出来的那一份（含 inject/、
 * background/、config/）。找不到就报错退出，不会静默产出空引擎。
 */
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const here = __dirname;
const projectRoot = path.resolve(here, '..', '..');

const src = process.argv[2];
if (!src || !fs.existsSync(src)) {
  console.error('  用法: node tool/dark_engine/build_all.js <.../inject/index.js>');
  console.error('  给的文件不存在: ' + (src || '(空)'));
  process.exit(1);
}

// 中间产物放系统临时目录，不再污染仓库根目录
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pr-dark-'));
const files = {
  extract: path.join(tmp, 'extract.json'),
  extractVars: path.join(tmp, 'extract_vars.json'),
  body: path.join(tmp, 'body.js'),
};
const names = path.join(here, '_names.json');
const vars = path.join(here, '_vars.json');

function run(script, ...args) {
  const out = execFileSync(process.execPath, [path.join(here, script), ...args], {
    encoding: 'utf8',
    env: { ...process.env, PR_DARK_TMP: tmp },
  });
  process.stdout.write(out);
  return out;
}

try {
  console.log('  1/4 提取函数');
  run('_extract.js', src, names, files.extract);

  console.log('  2/4 提取顶层变量');
  run('_extract_vars.js', src, vars, files.extractVars);

  console.log('  3/4 合并 + 依赖检查');
  process.env.DR_SRC = src;
  process.env.PR_DARK_IN = files.extract;
  process.env.PR_DARK_VARS = files.extractVars;
  process.env.PR_DARK_BODY = files.body;
  run('_merge.js');

  console.log('  4/5 拼装');
  process.env.PR_DARK_BODY = files.body;
  const engineJs = path.join(projectRoot, 'assets', 'dark', 'engine.js');
  process.env.PR_DARK_OUT = engineJs;
  run('_build_engine.js');

  // ── 5/5 生成安卓降级版 ──
  //
  // 安卓老设备（MI PAD 4 PLUS 是 WebView 68）跑不动新语法。
  // 实测踩过的坑：引擎里有 class 字段（ES2022），WebView 68 直接
  // 解析失败 —— 而且 evaluateJavascript 不报解析错误，表现为
  // 「脚本注入成功但页面一点变化都没有」，极难排查。
  //
  // esbuild 转译到 es2017 能降掉所有 WebView 68 不支持的东西。
  // 不用自己写降级规则：以前手写的 lower_syntax.js 只处理了
  // ?. / ?? / replaceAll，漏了 class 字段，正是那次踩坑的原因。
  console.log('  5/5 生成安卓降级版 (es2017)');
  const legacyJs = path.join(projectRoot, 'assets', 'dark', 'engine.legacy.js');
  execFileSync(
    'npx',
    ['--yes', 'esbuild', engineJs, '--target=es2017', '--outfile=' + legacyJs],
    { encoding: 'utf8', stdio: 'inherit', shell: true },
  );
  const legacySize = (fs.statSync(legacyJs).size / 1024).toFixed(1);
  console.log('    engine.legacy.js  ' + legacySize + ' KB');
} finally {
  // 无论成败都清理临时目录
  try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (_) {}
}