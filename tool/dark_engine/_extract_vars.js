/**
 * 提取顶层变量声明（const/let/var），支持多行对象/数组/正则。
 */
const fs = require('fs');

const srcPath = process.argv[2];
const namesPath = process.argv[3];
const outPath = process.argv[4];

const src = fs.readFileSync(srcPath, 'utf8');
const names = JSON.parse(fs.readFileSync(namesPath, 'utf8'));

function makeScanner(text, pos) {
  return { text, i: pos, inS: false, q: '', esc: false, inLine: false, inBlock: false,
    inRegex: false, inRegexClass: false, lastSignificant: '' };
}
const REGEX_PRECEDERS = new Set(['', '(', ',', '=', ':', '[', '!', '&', '|', '?', '{', '}', ';', '+', '-', '*', '%', '<', '>', '~', '^']);

function step(s) {
  const { text } = s;
  const n = text.length;
  if (s.i >= n) return null;
  const ch = text[s.i];
  const nx = s.i + 1 < n ? text[s.i + 1] : '';
  if (s.inLine) { if (ch === '\n') s.inLine = false; s.i++; return ''; }
  if (s.inBlock) { if (ch === '*' && nx === '/') { s.inBlock = false; s.i += 2; return ''; } s.i++; return ''; }
  if (s.inS) {
    if (s.esc) { s.esc = false; s.i++; return ''; }
    if (ch === '\\') { s.esc = true; s.i++; return ''; }
    if (ch === s.q) { s.inS = false; s.i++; return ''; }
    s.i++; return '';
  }
  if (s.inRegex) {
    if (ch === '\\') { s.i += 2; return ''; }
    if (ch === '[') { s.inRegexClass = true; s.i++; return ''; }
    if (ch === ']') { s.inRegexClass = false; s.i++; return ''; }
    if (ch === '/' && !s.inRegexClass) { s.inRegex = false; s.i++; return ''; }
    s.i++; return '';
  }
  if (ch === '/' && nx !== '/' && nx !== '*' && REGEX_PRECEDERS.has(s.lastSignificant)) {
    s.inRegex = true; s.i++; return '';
  }
  if (ch === '/' && nx === '/') { s.inLine = true; s.i += 2; return ''; }
  if (ch === '/' && nx === '*') { s.inBlock = true; s.i += 2; return ''; }
  if (ch === '"' || ch === "'" || ch === '`') { s.inS = true; s.q = ch; s.lastSignificant = ch; s.i++; return ''; }
  if (!/\s/.test(ch)) s.lastSignificant = ch;
  s.i++;
  return ch;
}

function findDeclEnd(text, startPos) {
  const s = makeScanner(text, startPos);
  let depth = 0;
  let seenEqual = false;
  while (s.i < text.length) {
    const p = s.i;
    const ch = step(s);
    if (ch === null) break;
    if (!seenEqual) {
      if (ch === '=') seenEqual = true;
      // 没有初始值的声明（let x;）直接到分号结束
      else if (ch === ';') return p;
      continue;
    }
    if (ch === '{' || ch === '(' || ch === '[') depth++;
    else if (ch === '}' || ch === ')' || ch === ']') depth--;
    else if (ch === ';' && depth <= 0) return p;
  }
  return startPos;
}

const result = [];
for (const name of names) {
  const re = new RegExp(`^    (?:const|let|var)\\s+${name.replace(/[$]/g, '\\$')}\\s*(?:=|;|$)`, 'm');
  const m = re.exec(src);
  if (!m) { result.push({ name, start: -1, end: -1, text: null }); continue; }
  const endPos = findDeclEnd(src, m.index);
  result.push({
    name,
    start: src.slice(0, m.index).split('\n').length,
    end: src.slice(0, endPos).split('\n').length,
    text: src.slice(m.index, endPos + 1),
  });
}

fs.writeFileSync(outPath, JSON.stringify(result, null, 2), 'utf8');
const missing = result.filter(r => r.start === -1);
console.log(`  变量 ${result.length}，未找到 ${missing.length}`);
missing.forEach(r => console.log('    ✗ ' + r.name));
const totalLines = result.filter(r => r.text).reduce((a, r) => a + r.text.split('\n').length, 0);
console.log('  总行数 ' + totalLines);