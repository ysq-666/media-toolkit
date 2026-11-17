// xhs.js —— 小红书图文 & 视频全能下载器（直读 Firefox 实时登录态）
//
// 升级特性：
// 1. 图文笔记：下载全部无水印原图 (01.jpg ... NN.jpg) + 笔记.txt
// 2. 视频笔记：不再报错中断！直接从 __INITIAL_STATE__ 提取无水印 H264/H265 视频流下载 video.mp4 + 封面 cover.jpg + 笔记.txt
// 3. 登录态：优先通过 node:sqlite 读取 Firefox 实时登录态，fallback 到 cookies.txt。

const fs = require('fs');
const os = require('os');
const path = require('path');
const { Readable } = require('stream');
const { pipeline } = require('stream/promises');
const { execFile } = require('child_process');

const HERE = __dirname;
const COOKIE_CANDS = [
  path.join(HERE, 'cookies.txt'),
  path.join(HERE, '..', 'download', 'cookies.txt'),
];
const COOKIE_FILE = COOKIE_CANDS.find((p) => fs.existsSync(p)) || COOKIE_CANDS[0];
const UA_D = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

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
    const tmp = path.join(os.tmpdir(), `ff_cookies_${process.pid}_${prof}.sqlite`);
    const map = new Map();
    try {
      fs.copyFileSync(db, tmp);
      const con = new DatabaseSync(tmp);
      const rows = con.prepare('SELECT name, value FROM moz_cookies WHERE host LIKE ?').all(hostPattern);
      con.close();
      for (const r of rows) if (r.name && r.value != null) map.set(r.name, r.value);
    } catch {
      /* ignore */
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
  if (out.length && COOKIE_SOURCE === 'none') COOKIE_SOURCE = 'cookies.txt';
  return out.join('; ');
}

function cookiesFor(re) {
  const isXhs = /xiaohongshu|rednote/.test(String(re));
  const live = isXhs ? firefoxCookieHeader('%xiaohongshu.com%') : '';
  if (live) return live;
  return fileCookieHeader(re);
}

function sanitize(name) {
  return String(name || '')
    .replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 90) || 'xhs';
}

function extractState(html) {
  const start = html.indexOf('__INITIAL_STATE__');
  if (start < 0) return null;
  let i = html.indexOf('{', start);
  if (i < 0) return null;
  let depth = 0;
  let inStr = false;
  let esc = false;
  for (let k = i; k < html.length; k++) {
    const c = html[k];
    if (inStr) {
      if (esc) esc = false;
      else if (c === '\\') esc = true;
      else if (c === '"') inStr = false;
    } else {
      if (c === '"') inStr = true;
      else if (c === '{') depth++;
      else if (c === '}') {
        depth--;
        if (depth === 0) return html.slice(i, k + 1);
      }
    }
  }
  return null;
}

function parseState(raw) {
  let s = raw;
  s = s.replace(/:\s*undefined/g, ':null');
  s = s.replace(/\[\s*undefined/g, '[null');
  s = s.replace(/,\s*undefined/g, ',null');
  s = s.replace(/new\s+\w+\([^)]*\)/g, 'null');
  return JSON.parse(s);
}

function findNoteCard(obj) {
  if (!obj || typeof obj !== 'object') return null;
  if (typeof obj.title === 'string' && (Array.isArray(obj.imageList) || obj.video)) return obj;
  if (Array.isArray(obj)) {
    for (const v of obj) {
      const r = findNoteCard(v);
      if (r) return r;
    }
  } else {
    for (const v of Object.values(obj)) {
      const r = findNoteCard(v);
      if (r) return r;
    }
  }
  return null;
}

function pickImageUrl(im) {
  if (!im) return null;
  if (im.urlDefault) return im.urlDefault;
  const list = im.infoList || [];
  const dft = list.find((x) => x.imageScene === 'WB_DFT');
  if (dft && dft.url) return dft.url;
  const prv = list.find((x) => x.imageScene === 'WB_PRV');
  if (prv && prv.url) return prv.url;
  if (list[0] && list[0].url) return list[0].url;
  if (im.url) return im.url;
  if (im.urlPre) return im.urlPre;
  return null;
}

function pickVideoUrl(card) {
  const v = card.video || {};
  const stream = (v.media && v.media.stream) || {};
  for (const codec of ['h264', 'h265', 'av1']) {
    const arr = stream[codec];
    if (Array.isArray(arr) && arr.length) {
      for (const item of arr) {
        if (item.masterUrl) return item.masterUrl;
        if (Array.isArray(item.backupUrls) && item.backupUrls[0]) return item.backupUrls[0];
      }
    }
  }
  if (v.consumer && v.consumer.originVideoKey) {
    return `https://sns-video-bd.xhscdn.com/${v.consumer.originVideoKey}`;
  }
  return null;
}

function curlResolve(url) {
  return new Promise((resolve) => {
    const nullDev = process.platform === 'win32' ? 'NUL' : '/dev/null';
    execFile('curl', ['-s', '-o', nullDev, '-w', '%{url_effective}', '--max-time', '25', '-L', url],
      { timeout: 30000 },
      (err, stdout) => resolve(err ? '' : String(stdout || '')));
  });
}

async function resolveInput(input) {
  const m = input.match(/(?:explore|discovery\/item|note)\/([0-9a-f]{24})/);
  if (m) return { id: m[1], url: input };
  console.log('  短链接，正在解析 ...');
  const cookie = cookiesFor(/xiaohongshu\.com$|rednote\.com$/);
  let finalUrl = '';
  let text = '';
  try {
    const res = await fetch(input, {
      headers: {
        'user-agent': UA_D,
        'accept': 'text/html,*/*',
        ...(cookie ? { cookie } : {}),
      },
      redirect: 'follow',
      signal: AbortSignal.timeout(30000),
    });
    finalUrl = res.url;
    text = await res.text();
  } catch (e) {
    console.log(`  fetch 没通（${e.name}），改用 curl 再试 ...`);
    finalUrl = await curlResolve(input);
  }
  const decoded = decodeURIComponent(finalUrl);
  const rp = decoded.match(/redirectPath=(https?:\/\/.+)$/);
  if (rp) {
    const noteUrl = rp[1].replace(/^https?:\/\/[^/]+/, 'https://www.xiaohongshu.com');
    const mm = noteUrl.match(/(?:explore|discovery\/item|note)\/([0-9a-f]{24})/);
    if (mm) return { id: mm[1], url: noteUrl };
  }
  for (const candidate of [finalUrl, decoded, text]) {
    const mm = String(candidate).match(/(?:explore|discovery\/item|note)\/([0-9a-f]{24})/);
    if (mm) return { id: mm[1], url: finalUrl || input };
  }
  throw new Error('无法从链接里解析出笔记 ID');
}

async function getNote(id, pageUrl) {
  const cookie = cookiesFor(/xiaohongshu\.com$/);
  const res = await fetch(pageUrl, {
    headers: {
      'user-agent': UA_D,
      'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'accept-language': 'zh-CN,zh;q=0.9',
      'referer': 'https://www.xiaohongshu.com/',
      ...(cookie ? { cookie } : {}),
    },
    redirect: 'follow',
    signal: AbortSignal.timeout(30000),
  });
  if (!res.ok) throw new Error(`笔记页返回 HTTP ${res.status}`);
  if (/\/login/.test(res.url)) {
    const err = new Error('被跳到登录页：Firefox 里没有登录态。请在 Firefox 登录 xiaohongshu.com 后重试');
    err.exitCode = 4;
    throw err;
  }
  const html = await res.text();
  const raw = extractState(html);
  if (!raw) {
    if (html.length < 6000 || /verify|captcha|验证/i.test(html)) {
      const err = new Error(
        '触发了小红书风控（返回验证页）。\n'
        + '        处理：立刻停手，等 3-10 分钟再试；不要并发。',
      );
      err.exitCode = 3;
      err.riskControl = true;
      throw err;
    }
    throw new Error('笔记页里没找到 __INITIAL_STATE__（可能被风控拦截）');
  }
  const state = parseState(raw);
  const card = (state.feed && state.feed.undertakeNote && state.feed.undertakeNote.items
    && state.feed.undertakeNote.items[0] && state.feed.undertakeNote.items[0].noteCard)
    || (state.noteDetail && state.noteDetail.note)
    || findNoteCard(state);
  if (!card) throw new Error('没找到笔记数据（页面结构可能变了）');

  const isVideo = card.type === 'video' || Boolean(card.video && pickVideoUrl(card));
  const videoUrl = isVideo ? pickVideoUrl(card) : null;
  const images = (card.imageList || []).map(pickImageUrl).filter(Boolean);

  if (!isVideo && !images.length) {
    throw new Error('笔记里没找到图片或视频地址，Cookie 可能已失效');
  }

  return {
    id: card.noteId || id,
    title: card.title || card.desc?.slice(0, 40) || '小红书笔记',
    desc: card.desc || '',
    author: (card.user || {}).nickname || '',
    type: isVideo ? 'video' : (card.type || 'normal'),
    tags: (card.tagList || []).map((t) => t.name).filter(Boolean),
    likes: (card.interactInfo || {}).likedCount,
    collects: (card.interactInfo || {}).collectedCount,
    images,
    videoUrl,
  };
}

async function downloadFile(url, targetPath, cookie) {
  const res = await fetch(url, {
    headers: {
      'user-agent': UA_D,
      'referer': 'https://www.xiaohongshu.com/',
      ...(cookie ? { cookie } : {}),
    },
    redirect: 'follow',
    signal: AbortSignal.timeout(120000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const body = Readable.fromWeb(res.body);
  await pipeline(body, fs.createWriteStream(targetPath));
}

async function download(note, outDir) {
  const folder = path.join(outDir, `${sanitize(note.title)} [${note.id}]`);
  fs.mkdirSync(folder, { recursive: true });

  const txt = [
    `标题：${note.title}`,
    `作者：${note.author}`,
    `类型：${note.type === 'video' ? '视频笔记' : '图文笔记'}`,
    `链接：https://www.xiaohongshu.com/discovery/item/${note.id}`,
    note.likes != null ? `点赞：${note.likes}  收藏：${note.collects}` : '',
    note.tags.length ? `话题：${note.tags.map((t) => '#' + t).join(' ')}` : '',
    '',
    note.desc || '',
    '',
  ].join('\n');
  fs.writeFileSync(path.join(folder, '笔记.txt'), txt, 'utf8');

  const cookie = cookiesFor(/xiaohongshu\.com$/);

  if (note.type === 'video' && note.videoUrl) {
    const vTarget = path.join(folder, 'video.mp4');
    if (fs.existsSync(vTarget)) {
      console.log('  视频 video.mp4 已存在，跳过');
    } else {
      console.log('  正在下载无水印视频流 -> video.mp4 ...');
      await downloadFile(note.videoUrl, vTarget, cookie);
      console.log(`  视频完成：${(fs.statSync(vTarget).size / 1048576).toFixed(2)} MB`);
    }
    if (note.images.length) {
      const coverTarget = path.join(folder, 'cover.jpg');
      if (!fs.existsSync(coverTarget)) {
        try { await downloadFile(note.images[0], coverTarget, cookie); } catch {}
      }
    }
    return { folder, done: 1, total: 1, isVideo: true };
  }

  let done = 0;
  for (let i = 0; i < note.images.length; i++) {
    const target = path.join(folder, `${String(i + 1).padStart(2, '0')}.jpg`);
    if (fs.existsSync(target)) {
      console.log(`  ${i + 1}/${note.images.length} 已存在，跳过`);
      done++;
      continue;
    }
    await downloadFile(note.images[i], target, cookie);
    console.log(`  ${i + 1}/${note.images.length} 完成：${(fs.statSync(target).size / 1024).toFixed(0)} KB`);
    done++;
  }
  return { folder, done, total: note.images.length, isVideo: false };
}

(async () => {
  const input = process.argv[2];
  const outDir = process.argv[3] || path.join(process.env.USERPROFILE || '.', 'Pictures', 'xhs');
  if (!input) {
    console.error('用法: node xhs.js <链接> [输出目录]');
    process.exit(2);
  }
  fs.mkdirSync(outDir, { recursive: true });

  console.log('小红书图文/视频下载器');
  console.log(`  输出目录: ${outDir}`);
  const { id, url } = await resolveInput(input);
  console.log(`  笔记 ID: ${id}`);

  const note = await getNote(id, url);
  console.log(`  登录态: ${COOKIE_SOURCE}`);
  console.log(`  类型: ${note.type === 'video' ? '视频笔记 (自动提取无水印MP4)' : `图文笔记 (${note.images.length} 张图)`}`);
  console.log(`  标题: ${note.title}`);
  console.log(`  作者: ${note.author || '?'}`);

  const r = await download(note, outDir);
  if (r.isVideo) {
    console.log(`  完成：${r.folder}（video.mp4 + 笔记.txt）`);
  } else {
    console.log(`  完成：${r.folder}（${r.done}/${r.total} 张图 + 笔记.txt）`);
  }
})().catch((e) => {
  console.error(`\n失败：${e.message}`);
  console.error('排查：在 Firefox 里登录 xiaohongshu.com（要能看到自己的头像），再重试；');
  process.exitCode = e.exitCode || 1;
});
