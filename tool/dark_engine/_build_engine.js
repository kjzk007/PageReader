const fs = require('fs');
const path = require('path');
const algo = fs.readFileSync(process.env.PR_DARK_BODY || '_engine_body.js', 'utf8');
const skeletonPath = process.env.PR_DARK_SKELETON || path.join(__dirname, '..', '..', 'assets', 'dark', 'skeleton.js');
const skeleton = fs.readFileSync(skeletonPath, 'utf8');
if (!skeleton.includes('/* @ALGORITHM */')) {
  console.error('  骨架里找不到占位符');
  process.exit(1);
}
const out = skeleton.replace('/* @ALGORITHM */', '// ===== 算法部分（颜色解析 / 亮度映射 / 缓存 / CSS 遍历）=====\n' + algo);
const outPath = process.env.PR_DARK_OUT || path.join(__dirname, '..', '..', 'assets', 'dark', 'engine.js');
fs.writeFileSync(outPath, out, 'utf8');
console.log('  已生成 assets/dark/engine.js');
console.log('  大小: ' + (out.length / 1024).toFixed(1) + ' KB');
console.log('  行数: ' + out.split('\n').length);

// 语法检查
try {
  new Function(out);
  console.log('  语法检查: ✓ 通过');
} catch (e) {
  console.log('  语法检查: ✗ ' + e.message);
}
