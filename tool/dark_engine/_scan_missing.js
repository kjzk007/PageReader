const fs = require('fs');
const srcPath = process.argv[2];
const src = fs.readFileSync(srcPath, 'utf8');
const body = fs.readFileSync('_engine_body.js', 'utf8');

// 源文件里所有顶层声明（4 空格缩进的 const/let/var/function/class）
const decls = new Map();
for (const m of src.matchAll(/^    (?:const|let|var)\s+(\w+)/gm)) decls.set(m[1], 'var');
for (const m of src.matchAll(/^    (?:function|class)\s+(\w+)/gm)) decls.set(m[1], 'decl');

// 算法体里已定义的
const defined = new Set();
for (const m of body.matchAll(/^\s*(?:function |const |let |var |class )(\w+)/gm)) defined.add(m[1]);

// 算法体里引用的标识符（排除方法调用：前面有 . 的）
const referenced = new Set();
for (const m of body.matchAll(/(?<![.\w$])([a-zA-Z_$][\w$]*)/g)) referenced.add(m[1]);

const jsKeywords = new Set('if for while switch catch function return typeof new delete void in of do else case try finally throw yield await async break continue default var let const class extends super this null true false undefined NaN Infinity'.split(' '));

const missing = [];
for (const name of referenced) {
  if (defined.has(name) || jsKeywords.has(name)) continue;
  if (decls.has(name)) missing.push({ name, kind: decls.get(name) });
}
console.log('  源文件顶层声明: ' + decls.size);
console.log('  算法体已定义: ' + defined.size);
console.log('  缺的顶层声明 (' + missing.length + '):');
for (const m of missing) console.log('    ' + m.kind.padEnd(6) + ' ' + m.name);
fs.writeFileSync('_missing.json', JSON.stringify(missing.map(m => m.name)), 'utf8');

