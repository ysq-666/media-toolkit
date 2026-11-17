"""Scrapling 示例：抓取 + 解析（HTTP / 浏览器 / 带 Cookie 三种姿势）

用法：
    python 示例-抓取与解析.py                        # 默认演示站点
    python 示例-抓取与解析.py https://example.com
    python 示例-抓取与解析.py URL --css ".quote .text"
    python 示例-抓取与解析.py URL --browser          # 用浏览器渲染 JS
    python 示例-抓取与解析.py URL --cf               # 浏览器 + 过 Cloudflare（慢）
    python 示例-抓取与解析.py URL --cookies cookies.txt

Cookie 文件要求 Netscape 格式（就是 yt-dlp 用的那种 cookies.txt）。
"""

import argparse
import sys
import time

from scrapling.parser import Selector

DEFAULT_URL = "https://quotes.toscrape.com/"


def load_cookies_netscape(path: str) -> dict:
    """把 Netscape cookies.txt 读成 {name: value}（curl_cffi 只认这种简单形式，不带域）。"""
    jar = {}
    with open(path, encoding="utf-8", errors="ignore") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line.strip():
                continue
            if line.startswith("#HttpOnly_"):
                line = line[len("#HttpOnly_"):]
            elif line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 7:
                continue
            jar[parts[5]] = parts[6]
    return jar


def parse_demo(html_source: str) -> None:
    """纯解析：不联网也能跑。"""
    sel = Selector(html_source)
    print("  CSS   :", sel.css(".quote .text::text").getall())
    print("  XPath :", sel.xpath("//span[@class='author']/text()").getall())
    first = sel.css(".quote")[0]
    print("  单元素 :", first.css(".text::text").get(), "| 父节点:", first.parent.tag)


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("url", nargs="?", default=DEFAULT_URL)
    ap.add_argument("--css", default=None, help="只取匹配的元素，例如 '.quote'")
    ap.add_argument("--browser", action="store_true", help="用浏览器渲染 JS")
    ap.add_argument("--cf", action="store_true", help="浏览器 + 过 Cloudflare（很慢）")
    ap.add_argument("--cookies", default=None, help="Netscape 格式 cookies 文件")
    ap.add_argument("--save", default=None, help="把页面 HTML 存到文件")
    args = ap.parse_args()

    print("=== 1) 离线解析器 ===")
    parse_demo("<html><body>"
               "<div class='quote'><span class='text'>Hello</span><span class='author'>A</span></div>"
               "<div class='quote'><span class='text'>World</span><span class='author'>B</span></div>"
               "</body></html>")

    cookies = load_cookies_netscape(args.cookies) if args.cookies else None
    if cookies:
        print(f"\n[cookies] 载入 {len(cookies)} 条（{args.cookies}）")

    print(f"\n=== 2) 抓取 {args.url} ===")
    t0 = time.time()
    if args.cf or args.browser:
        from scrapling.fetchers import StealthyFetcher
        kwargs = {"headless": True, "network_idle": True}
        if args.cf:
            kwargs.update({"solve_cloudflare": True, "timeout": 180000})
        if cookies:
            kwargs["cookies"] = cookies
        page = StealthyFetcher.fetch(args.url, **kwargs)
    else:
        from scrapling.fetchers import Fetcher
        kwargs = {"impersonate": "chrome"}
        if cookies:
            kwargs["cookies"] = cookies
        page = Fetcher.get(args.url, **kwargs)

    print(f"  status={page.status} len={len(page.html_content)} 用时 {time.time() - t0:.2f}s")

    if args.save:
        with open(args.save, "w", encoding="utf-8") as fh:
            fh.write(page.html_content)
        print(f"  已保存 HTML -> {args.save}")

    print("\n=== 3) 提取 ===")
    sel = args.css or ".quote .text::text"
    try:
        found = page.css(sel).getall()
    except Exception as exc:  # noqa: BLE001
        print(f"  CSS 失败: {exc}")
        found = []
    print(f"  css('{sel}') -> {len(found)} 条")
    for item in found[:5]:
        print("   -", str(item)[:100])

    print("\n=== 4) 转 Markdown（喂 AI / 做 RAG 用） ===")
    try:
        md = page.markdown()
        print(md[:200].replace("\n", " "), "...")
    except Exception as exc:  # noqa: BLE001
        print("  markdown() 不可用:", exc)
    return 0


if __name__ == "__main__":
    sys.exit(main())
