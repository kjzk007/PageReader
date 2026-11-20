const fs = require('fs');

// 函数/类/对象
const funcs = JSON.parse(fs.readFileSync(process.env.PR_DARK_IN || '_extract.json', 'utf8'));
// 顶层变量（缓存、颜色表、正则等）
const varsPath = process.env.PR_DARK_VARS || '_extract_vars.json';
const vars = fs.existsSync(varsPath)
  ? JSON.parse(fs.readFileSync(varsPath, 'utf8'))
  : [];

const all = [...funcs, ...vars].filter(d => d.text);
// 按原始行号排序：变量可能依赖前面的变量（如 rgbUnits 用到 rgbRange）
all.sort((a, b) => a.start - b.start);

const body = all.map(d => d.text).join('\n\n');
fs.writeFileSync(process.env.PR_DARK_BODY || '_engine_body.js', body, 'utf8');

// 语法检查
try {
  new Function(body);
  console.log('  语法: ✓');
} catch (e) {
  console.log('  语法: ✗ ' + e.message);
  // 二分找问题
  let acc = '';
  for (const d of all) {
    try { new Function(acc + '\n\n' + d.text); acc = acc + '\n\n' + d.text; }
    catch (err) {
      console.log('  加入 ' + d.name + ' (行' + d.start + '-' + d.end + ') 出错: ' + err.message);
      break;
    }
  }
}

// 依赖检查
const defined = new Set();
for (const m of body.matchAll(/^\s*(?:function |const |let |var |class )(\w+)/gm)) defined.add(m[1]);
const referenced = new Set();
for (const m of body.matchAll(/(?<![.\w$])([a-zA-Z_$][\w$]*)/g)) referenced.add(m[1]);
const src = fs.readFileSync(process.env.DR_SRC || '', 'utf8');
const decls = new Map();
for (const m of src.matchAll(/^    (?:const|let|var)\s+(\w+)\s*=/gm)) decls.set(m[1], 1);
for (const m of src.matchAll(/^    (?:function|class)\s+(\w+)/gm)) decls.set(m[1], 1);
const kw = new Set('if for while switch catch function return typeof new delete void in of do else case try finally throw yield await async break continue default var let const class extends super this null true false undefined NaN Infinity'.split(' '));
const missing = [...referenced].filter(n => !defined.has(n) && !kw.has(n) && decls.has(n));
console.log('  仍缺的源文件声明: ' + missing.length + (missing.length ? ' → ' + missing.join(', ') : ''));

console.log('  合计: ' + (body.length / 1024).toFixed(1) + ' KB / ' + body.split('\n').length + ' 行');
console.log('  组件: ' + all.length + ' 项');