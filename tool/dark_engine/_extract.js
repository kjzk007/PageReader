/**
 * 从 Dark Reader 的 inject/index.js 中提取指定函数/对象。
 *
 * 关键点：先配平圆括号跳过参数列表，再找函数体的花括号。
 * 否则 `function f({a, b}) {` 里参数解构的花括号会被误认为函数体开始。
 */
const fs = require('fs');

const src = fs.readFileSync(process.argv[2], 'utf8');
const names = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
const outPath = process.argv[4];

// 扫描器状态
function makeScanner(text, pos) {
  return {
    text, i: pos,
    inS: false, q: '', esc: false, inLine: false, inBlock: false,
    inRegex: false, inRegexClass: false, lastSignificant: '',
  };
}

// 这些字符之后的 `/` 是正则开始，而不是除号
const REGEX_PRECEDERS = new Set(['', '(', ',', '=', ':', '[', '!', '&', '|', '?', '{', '}', ';', '+', '-', '*', '%', '<', '>', '~', '^']);

function step(s) {
  const { text } = s;
  const n = text.length;
  if (s.i >= n) return null;
  const ch = text[s.i];
  const nx = s.i + 1 < n ? text[s.i + 1] : '';

  if (s.inLine) {
    if (ch === '\n') s.inLine = false;
    s.i++;
    return '';
  }
  if (s.inBlock) {
    if (ch === '*' && nx === '/') { s.inBlock = false; s.i += 2; return ''; }
    s.i++;
    return '';
  }
  if (s.inS) {
    if (s.esc) { s.esc = false; s.i++; return ''; }
    if (ch === '\\') { s.esc = true; s.i++; return ''; }
    if (ch === s.q) { s.inS = false; s.i++; return ''; }
    s.i++;
    return '';
  }
  // 正则字面量：里面的 / 和 {} 都不该被当成语法结构
  if (s.inRegex) {
    if (ch === '\\') { s.i += 2; return ''; }
    if (ch === '[') { s.inRegexClass = true; s.i++; return ''; }
    if (ch === ']') { s.inRegexClass = false; s.i++; return ''; }
    if (ch === '/' && !s.inRegexClass) { s.inRegex = false; s.i++; return ''; }
    s.i++;
    return '';
  }
  if (ch === '/' && nx !== '/' && nx !== '*' && REGEX_PRECEDERS.has(s.lastSignificant)) {
    s.inRegex = true;
    s.i++;
    return '';
  }
  if (ch === '/' && nx === '/') { s.inLine = true; s.i += 2; return ''; }
  if (ch === '/' && nx === '*') { s.inBlock = true; s.i += 2; return ''; }
  if (ch === '"' || ch === "'" || ch === '`') {
    s.inS = true; s.q = ch; s.lastSignificant = ch; s.i++; return '';
  }
  if (!/\s/.test(ch)) s.lastSignificant = ch;

  s.i++;
  return ch;
}

function findDeclEnd(text, startPos) {
  // 阶段 A：跳过参数列表，找到函数体/对象体的第一个花括号
  const s = makeScanner(text, startPos);
  let paren = 0;
  let bracket = 0;
  let bodyStart = -1;
  while (s.i < text.length) {
    const p = s.i;
    const ch = step(s);
    if (ch === null) break;
    if (ch === '(') paren++;
    else if (ch === ')') paren--;
    else if (ch === '[') bracket++;
    else if (ch === ']') bracket--;
    else if (ch === '{' && paren <= 0 && bracket <= 0) { bodyStart = p; break; }
    else if (ch === ';' && paren <= 0 && bracket <= 0) {
      // 箭头函数的单表达式体，无花括号
      return p;
    }
  }
  if (bodyStart < 0) return startPos;

  // 阶段 B：从函数体开始配平花括号
  const s2 = makeScanner(text, bodyStart);
  let depth = 0;
  while (s2.i < text.length) {
    const p = s2.i;
    const ch = step(s2);
    if (ch === null) break;
    if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) return p;
    }
  }
  return bodyStart;
}

const result = [];
for (const name of names) {
  // 找声明位置：行首 4 空格 + function/const/let/var/class + 名字
  const re = new RegExp(`^    (?:function |const |let |var |class )${name.replace(/[$]/g, '\\$')}\\s*[=({]`, 'm');
  const m = re.exec(src);
  if (!m) { result.push({ name, start: -1, end: -1, text: null }); continue; }
  const startPos = m.index + (m[0].length - m[0].trimStart().length);
  const endPos = findDeclEnd(src, m.index);
  const text = src.slice(m.index, endPos + 1);
  const startLine = src.slice(0, m.index).split('\n').length;
  const endLine = src.slice(0, endPos).split('\n').length;
  result.push({ name, start: startLine, end: endLine, text });
}

fs.writeFileSync(outPath, JSON.stringify(result, null, 2), 'utf8');
const missing = result.filter(r => r.start === -1);
const totalLines = result.filter(r => r.text).reduce((a, r) => a + r.text.split('\n').length, 0);
console.log(`  提取 ${result.length} 项，未找到 ${missing.length}，总行数 ${totalLines}`);
missing.forEach(r => console.log('    ✗ ' + r.name));
// 报告异常大的
result.filter(r => r.text && r.text.split('\n').length > 150)
  .forEach(r => console.log(`    偏大: ${r.name} ${r.start}-${r.end} (${r.text.split('\n').length} 行)`));
