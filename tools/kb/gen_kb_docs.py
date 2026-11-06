"""把 App 内置的黄河内容包导出成 Dify 知识库文档。

用法（在项目根目录执行）：
    python tools/kb/gen_kb_docs.py            # 输出到 tools/kb/docs
    python tools/kb/gen_kb_docs.py --out D:/kb

产物：
    s01-庙底沟遗址.md … s20-…….md   每处遗址一篇
    goods-文创市集.md
    courses-沿河课程.md
    events-沿河活动.md

社区动态（huanghe_posts.json）不再导出：那是站内游客自己的分享，进检索源
会让助手把 UGC 当档案引用，也会让回答里冒出「引 · posts」这类chip。

上传到 Dify 知识库时保持文件名不变。App 端引用回跳只认文件名开头的
siteId（如 s01-庙底沟遗址.md → s01），所以不要改 sXX- 前缀。
"""

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RAWFILE = ROOT / "entry" / "src" / "main" / "resources" / "rawfile"

def load(name):
    with (RAWFILE / name).open(encoding="utf-8") as f:
        return json.load(f)

def safe(name):
    return re.sub(r'[\\/:*?"<>|\r\n]+', "-", name).strip()

def site_doc(s):
    lines = [
        f"# {s['name']}（{s['id']}）",
        "",
        f"- 别名：{s.get('alias') or '无'}",
        f"- 所在城市：{s['city']}",
        f"- 年代：{'、'.join(s.get('eras') or [])}",
        f"- 类型：{'、'.join(s.get('types') or [])}",
        "",
        "## 摘要",
        s.get("summary", ""),
        "",
        "## 简介",
        s.get("intro", ""),
        "",
        "## 考古发现",
        s.get("archaeology", ""),
        "",
        "## 历史脉络",
        s.get("history", ""),
        "",
    ]
    poems = s.get("poems") or []
    if poems:
        lines += ["", "## 相关诗句"]
        for p in poems:
            lines.append(f"> {p.get('line', '')}")
            lines.append(f"> —— {p.get('author', '')}《{p.get('source', '')}》")
            lines.append("")
    t = s.get("travel") or {}
    if t:
        lines += [
            "## 参观信息",
            f"- 门票：{t.get('ticket', '')}",
            f"- 开放时间：{t.get('openTime', '')}",
            f"- 提示：{t.get('tips', '')}",
            f"- 信息更新：{t.get('updated', '')}",
        ]
    lines += ["", "## 资料来源", s.get("source", ""), ""]
    return "\n".join(lines)

def goods_doc(goods):
    lines = ["# 文创市集", "", "站内文创商品目录，均为概念演示数据。", ""]
    for g in goods:
        lines += [
            f"## {g['name']}（{g['id']}）",
            f"- 分类：{g['cat']}",
            f"- 价格：¥{g['price']}",
            f"- 年代元素：{g['era']}",
            f"- 产地：{g['origin']}",
            f"- 标签：{'、'.join(g.get('tags') or [])}",
            f"- 简介：{g.get('sub', '')}",
            "",
            g.get("story", ""),
            "",
            "规格：",
        ]
        for kv in g.get("spec") or []:
            lines.append(f"- {kv['k']}：{kv['v']}")
        lines += ["", f"资料来源：{g.get('source', '')}", ""]
    return "\n".join(lines)

def courses_doc(courses):
    lines = ["# 沿河课程", "", "站内手作与通识课程目录。", ""]
    for c in courses:
        lines += [
            f"## {c['title']}（{c['id']}）",
            f"- 分类：{c['cat']}",
            f"- 难度：{c['level']}",
            f"- 时长：{c['minutes']} 分钟",
            f"- 关联遗址：{c.get('siteId', '')}",
            f"- 简介：{c.get('brief', '')}",
            "",
            "步骤：",
        ]
        for i, step in enumerate(c.get("steps") or [], 1):
            lines.append(f"{i}. {step['t']}：{step['d']}")
        lines += ["", f"资料来源：{c.get('source', '')}", ""]
    return "\n".join(lines)

def events_doc(events):
    lines = ["# 沿河活动", "", "站内线下活动排期。", ""]
    for e in events:
        lines += [
            f"## {e['title']}（{e['id']}）",
            f"- 类型：{e['kind']}",
            f"- 日期：{e['date']}",
            f"- 地点：{e['place']}",
            f"- 费用：{e['fee']}",
            f"- 名额：{e['seats']}",
            f"- 关联遗址：{e.get('siteId', '')}",
            "",
            e.get("brief", ""),
            "",
        ]
    return "\n".join(lines)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "tools" / "kb" / "docs"))
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    sites = load("huanghe_sites.json")
    count = 0
    for s in sites:
        fn = f"{s['id']}-{safe(s['name'])}.md"
        (out / fn).write_text(site_doc(s), encoding="utf-8", newline="\n")
        count += 1

    packs = [
        ("goods-文创市集.md", goods_doc(load("huanghe_goods.json"))),
        ("courses-沿河课程.md", courses_doc(load("huanghe_courses.json"))),
        ("events-沿河活动.md", events_doc(load("huanghe_events.json"))),
    ]
    for fn, text in packs:
        (out / fn).write_text(text, encoding="utf-8", newline="\n")
        count += 1

    total = sum(p.stat().st_size for p in out.glob("*.md"))
    print(f"wrote {count} docs to {out}")
    print(f"total {total} bytes")

if __name__ == "__main__":
    main()
