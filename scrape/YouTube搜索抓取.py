"""YouTube 关键词搜索结果抓取（Scrapling 版）

用途：yt-dlp 的 `ytsearch` 被限流、或你想先把结果落成表格时用这个。
只抓搜索结果页，不下载视频；拿到 videoId 后再交给 yt-dlp。

用法：
    python YouTube搜索抓取.py "lofi hip hop"
    python YouTube搜索抓取.py "关键词" --lang en --out result.csv
"""

import argparse
import csv
import json
import re
import sys
import time
from pathlib import Path

from scrapling.fetchers import Fetcher

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BASE = "https://www.youtube.com/results?search_query="


def walk_videos(node, out):
    if isinstance(node, dict):
        if "videoRenderer" in node:
            v = node["videoRenderer"]
            title = "".join(r.get("text", "") for r in v.get("title", {}).get("runs", []))
            channel = "".join(
                r.get("text", "")
                for r in (((v.get("ownerText") or {}).get("runs")) or [])
            )
            out.append({
                "video_id": v.get("videoId", ""),
                "title": title,
                "length": (v.get("lengthText") or {}).get("simpleText", ""),
                "channel": channel,
                "views": (v.get("viewCountText") or {}).get("simpleText", ""),
            })
        for value in node.values():
            walk_videos(value, out)
    elif isinstance(node, list):
        for value in node:
            walk_videos(value, out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("keyword")
    ap.add_argument("--lang", default="en-US,en;q=0.9")
    ap.add_argument("--out", default=None, help="CSV 输出路径")
    ap.add_argument("--json", action="store_true", help="同时打印 JSON")
    args = ap.parse_args()

    url = BASE + args.keyword.replace(" ", "+")
    t0 = time.time()
    page = Fetcher.get(url, impersonate="chrome",
                       headers={"accept-language": args.lang})
    print(f"status={page.status} len={len(page.html_content)} 用时 {time.time()-t0:.2f}s")

    m = re.search(r"var ytInitialData = (\{.*?\});</script>", page.html_content, re.S)
    if not m:
        print("没拿到 ytInitialData：可能被强制跳转到同意页或触发了风控。")
        print("试试加 --lang en-US 或改用浏览器模式（见 README 模式 2/3）。")
        return 1

    videos = []
    walk_videos(json.loads(m.group(1)), videos)

    # 去重（同一个视频可能在推荐位出现多次）
    seen, uniq = set(), []
    for v in videos:
        if v["video_id"] and v["video_id"] not in seen:
            seen.add(v["video_id"])
            uniq.append(v)

    print(f"抓到 {len(uniq)} 条结果")
    for v in uniq[:10]:
        print(f"  {v['video_id']} | {v['length']:>6} | {v['title'][:50]}")

    out = args.out or str(Path(__file__).parent / "output" / f"yt_{int(time.time())}.csv")
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="utf-8-sig", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=["video_id", "title", "length", "channel", "views"])
        writer.writeheader()
        writer.writerows(uniq)
    print(f"已保存: {out}")

    if args.json:
        print(json.dumps(uniq[:3], ensure_ascii=False, indent=2))

    print("\n下一步：把 video_id 拼成链接交给 yt-dlp")
    for v in uniq[:3]:
        print(f"  yt-dlp https://www.youtube.com/watch?v={v['video_id']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
