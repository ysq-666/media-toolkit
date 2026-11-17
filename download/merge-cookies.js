// merge-cookies.js
// 把多次「按站点导出」的 cookies.txt 合并成一个 yt-dlp 可用的总文件
// 用法： node merge-cookies.js <放导出的文件夹> [输出文件]
//
// 规则：只保留 7 字段的 Netscape 行；同一 (domain+path+name) 只留最后一条；
//       自动补标准头部。

const fs = require('fs');
const path = require('path');

const dir = process.argv[2] || '.';
const outPath = process.argv[3] || path.join(dir, '..', 'cookies.txt');

if (!fs.existsSync(dir)) {
  console.error(`目录不存在: ${dir}`);
  process.exit(1);
}

const files = fs
  .readdirSync(dir)
  .filter((f) => /\.txt$/i.test(f))
  .map((f) => path.join(dir, f))
  .filter((p) => path.resolve(p) !== path.resolve(outPath));

if (!files.length) {
  console.error(`没找到任何 .txt 文件：${dir}`);
  process.exit(1);
}

const map = new Map();
let parsed = 0;
let skipped = 0;

for (const file of files) {
  const text = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
  for (const rawLine of text.split(/\r?\n/)) {
    let line = rawLine;
    if (!line.trim()) continue;

    // #HttpOnly_ 是有效前缀，需要保留；其它 # 开头是注释
    let httpOnly = false;
    if (line.startsWith('#HttpOnly_')) {
      httpOnly = true;
      line = line.slice('#HttpOnly_'.length);
    } else if (line.startsWith('#')) {
      continue;
    }

    const parts = line.split('\t');
    if (parts.length < 7) {
      skipped++;
      continue;
    }
    const [domain, includeSub, cookiePath, secure, expiry, name, value] = parts;
    if (!domain || !name) {
      skipped++;
      continue;
    }

    const key = `${domain}\t${cookiePath}\t${name}`;
    map.set(key, {
      domain, includeSub, path: cookiePath, secure, expiry, name, value, httpOnly,
    });
    parsed++;
  }
}

const rows = [...map.values()].sort(
  (a, b) =>
    a.domain.localeCompare(b.domain) ||
    a.path.localeCompare(b.path) ||
    a.name.localeCompare(b.name),
);

const lines = rows.map((c) => {
  const host = c.httpOnly ? '#HttpOnly_' + c.domain : c.domain;
  return [host, c.includeSub, c.path, c.secure, c.expiry, c.name, c.value].join('\t');
});

const domains = new Set(rows.map((c) => c.domain.replace(/^#HttpOnly_/, '').replace(/^\./, ''))).size;
const header =
  '# Netscape HTTP Cookie File\n' +
  `# merged by merge-cookies.js on ${new Date().toISOString()}\n` +
  `# sources: ${files.length} file(s), cookies: ${rows.length}, domains: ${domains}\n\n`;

fs.writeFileSync(outPath, header + lines.join('\n') + '\n', 'utf8');
console.log(`读取 ${files.length} 个文件，解析 ${parsed} 条（跳过 ${skipped} 条无效行）`);
console.log(`合并结果：${rows.length} 条 cookie，${domains} 个域名`);
console.log(`输出：${outPath}`);
