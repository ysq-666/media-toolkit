// douyin.js —— 抖音无水印下载（绕过 yt-dlp 签名限制 + 直读 Firefox 实时登录态）
//
// 升级特性：
// 1. 优先通过 node:sqlite 直接读取本机 Firefox 实时 Cookie 库 (%douyin.com%)，永不过期；
// 2. Firefox 未登录时自动回退读取同目录或上级 download/cookies.txt；
// 3. 走 iesdouyin 分享页 _ROUTER_DATA 提取无水印 play 地址，支持视频作品。
//
// 用法： node douyin.js <链接> [输出目录]

const fs = require('fs');
const os = require('os');
const path = require('path');
const { Readable } = require('stream');
const { pipeline } = require('stream/promises');

const HERE = __dirname;
const COOKIE_CANDS = [
  path.join(HERE, 'cookies.txt'),
  path.join(HERE, '..', 'cookies.txt'),
  path.join(HERE, '..', '..', 'download', 'cookies.txt'),
];
const COOKIE_FILE = COOKIE_CANDS.find((p) => fs.existsSync(p)) || COOKIE_CANDS[0];
const UA_M = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

let COOKIE_SOURCE = 'none';

function firefoxCookieHeader(hostPattern) {
  let DatabaseSync;
  try {
    ({ DatabaseSync } = require('node:sqlite'));
  } catch {
    return '';
  }
  const base = path.join(
    process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'),
    'Mozilla', 'Firefox', 'Profiles',
  );
  if (!fs.existsSync(base)) return '';

  for (const prof of fs.readdirSync(base)) {
    const db = path.join(base, prof, 'cookies.sqlite');
    if (!fs.existsSync(db)) continue;
    const tmp = path.join(os.tmpdir(), `ff_dy_cookies_${process.pid}_${prof}.sqlite`);
    const map = new Map();
    try {
      fs.copyFileSync(db, tmp);
      const con = new DatabaseSync(tmp);
      const rows = con.prepare('SELECT name, value FROM moz_cookies WHERE host LIKE ?').all(hostPattern);
      con.close();
      for (const r of rows) if (r.name && r.value != null) map.set(r.name, r.value);
    } catch {
      /* ignore locked or unreadable profile */
    } finally {
      try { fs.unlinkSync(tmp); } catch { /* ignore */ }
    }
    if (map.size) {
      COOKIE_SOURCE = `firefox:${prof} (${map.size} 条)`;
      return [...map].map(([k, v]) => `${k}=${v}`).join('; ');
    }
  }
  return '';
}

function fileCookieHeader(re) {
  if (!fs.existsSync(COOKIE_FILE)) return '';
  const out = [];
  for (const raw of fs.readFileSync(COOKIE_FILE, 'utf8').split(/\r?\n/)) {
    if (!raw.trim()) continue;
    let line = raw;
    if (line.startsWith('#HttpOnly_')) line = line.slice(10);
    else if (line.startsWith('#')) continue;
    const p = line.split('\t');
    if (p.length < 7) continue;
    if (re && !re.test(p[0])) continue;
    out.push(`${p[5]}=${p[6]}`);
  }
  if (out.length && COOKIE_SOURCE === 'none') COOKIE_SOURCE = `cookies.txt (${ path.basename( path.dirname(COOKIE_FILE) ) })`;
  return out.join('; ');
}

function cookiesFor(re) {
  const live = firefoxCookieHeader('%douyin.com%');
  if (live) return live;
  return fileCookieHeader(re);
}

function sanitize(name) {
  return String(name || '')
    .replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 90) || 'douyin';
}

async function resolveId(input) {
  const m = input.match(/(?:video|note|share\/video)\/(\d{8,})/);
  if (m) return m[1];

  console.log('  短链接，正在解析 ...');
  const res = await fetch(input, {
    headers: { 'user-agent': UA_M, 'accept': 'text/html,*/*' },
    redirect: 'follow',
  });
  const text = await res.text();
  for (const candidate of [res.url, text]) {
    const mm = String(candidate).match(/\/(?:video|note)\/(\d{8,})/);
    if (mm) return mm[1];
  }
  throw new Error('无法从链接里解析出作品 ID');
}

async function getInfo(id) {
  const cookie = cookiesFor(/douyin\.com$/);
  const res = await fetch(`https://www.iesdouyin.com/share/video/${id}/`, {
    headers: {
      'user-agent': UA_M,
      'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'accept-language': 'zh-CN,zh;q=0.9',
      'referer': 'https://www.douyin.com/',
      ...(cookie ? { cookie } : {}),
    },
    redirect: 'follow',
  });
  if (!res.ok) throw new Error(`分享页返回 HTTP ${res.status}`);
  const html = await res.text();
  const m = html.match(/_ROUTER_DATA\s*=\s*(\{[\s\S]*?\})\s*<\/script>/);
  if (!m) {
    if (html.length < 6000 || /argus-csp-token|verify|captcha|验证/i.test(html)) {
      const err = new Error(
        `触发了抖音风控（返回 ${html.length} 字节的验证页）。\n`
        + '        处理：立刻停手，等 3-10 分钟再试；不要并发。',
      );
      err.exitCode = 3;
      err.riskControl = true;
      throw err;
    }
    throw new Error('分享页里没找到 _ROUTER_DATA（可能被风控拦截）');
  }

  const data = JSON.parse(m[1]);
  const page = (data.loaderData || {})['video_(id)/page'] || {};
  const item = ((page.videoInfoRes || {}).item_list || [])[0];
  if (!item) {
    const msg = ((page.videoInfoRes || {}).filter_list || []).map((x) => x.detail_msg || x.filter_reason).filter(Boolean);
    throw new Error(`拿不到作品数据${msg.length ? '：' + msg.join('；') : ''}`);
  }
  if (!item.video) throw new Error('这是图文作品，没有视频轨');

  const urls = ((item.video.play_addr || {}).url_list || []).slice();
  if (!urls.length) throw new Error('play_addr 为空，Cookie 可能已失效');

  const clean = urls.map((u) => u.replace('/playwm/', '/play/'));
  const pick = clean.find((u) => u.includes('/play/')) || urls[0];

  return {
    id: item.aweme_id || id,
    desc: item.desc || '',
    author: (item.author || {}).nickname || '',
    duration: item.video.duration ? Math.round(item.video.duration / 1000) : null,
    url: pick,
    allUrls: [...new Set([...clean, ...urls])],
  };
}

async function download(info, outDir) {
  const base = `${sanitize(info.desc)} [${info.id}]`;
  const target = path.join(outDir, `${base}.mp4`);
  if (fs.existsSync(target)) {
    console.log(`  已存在，跳过：${target}`);
    return target;
  }

  const cookie = cookiesFor(/douyin\.com$/);
  let lastErr;
  for (const url of info.allUrls) {
    try {
      const res = await fetch(url, {
        headers: {
          'user-agent': UA_M,
          'referer': 'https://www.douyin.com/',
          ...(cookie ? { cookie } : {}),
        },
        redirect: 'follow',
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const total = Number(res.headers.get('content-length') || 0);
      if (!total) throw new Error('响应没有 content-length，可能不是视频');

      const tmp = target + '.part';
      let got = 0;
      let lastPrint = 0;
      const body = Readable.fromWeb(res.body);
      body.on('data', (chunk) => {
        got += chunk.length;
        const now = Date.now();
        if (now - lastPrint > 400) {
          lastPrint = now;
          const pct = ((got / total) * 100).toFixed(1);
          process.stdout.write(`\r  下载中 ${pct}%  ${(got / 1048576).toFixed(1)}/${(total / 1048576).toFixed(1)} MB`);
        }
      });
      await pipeline(body, fs.createWriteStream(tmp));
      process.stdout.write('\r');
      fs.renameSync(tmp, target);
      console.log(`  完成：${target}`);
      console.log(`  大小：${(fs.statSync(target).size / 1048576).toFixed(1)} MB`);
      return target;
    } catch (e) {
      lastErr = e;
      console.log(`  这个地址失败（${e.message}），换下一个 ...`);
    }
  }
  throw lastErr || new Error('全部地址都失败');
}

(async () => {
  const input = process.argv[2];
  const outDir = process.argv[3] || path.join(process.env.USERPROFILE || '.', 'Videos', 'yt-dlp');
  if (!input) {
    console.error('用法: node douyin.js <链接> [输出目录]');
    process.exit(2);
  }
  fs.mkdirSync(outDir, { recursive: true });

  console.log('抖音下载器');
  console.log(`  输出目录: ${outDir}`);
  const id = await resolveId(input);
  console.log(`  作品 ID: ${id}`);

  const info = await getInfo(id);
  console.log(`  登录态: ${COOKIE_SOURCE}`);
  console.log(`  作者: ${info.author || '?'}`);
  console.log(`  文案: ${info.desc ? info.desc.slice(0, 60) : '(无)'}${info.desc && info.desc.length > 60 ? '…' : ''}`);
  if (info.duration) console.log(`  时长: ${info.duration}s`);

  await download(info, outDir);
})().catch((e) => {
  console.error(`\n失败：${e.message}`);
  console.error('排查：在 Firefox 登录 douyin.com 或确认 cookies.txt 里有 douyin.com 的新鲜 Cookie。');
  process.exitCode = e.exitCode || 1;
});
