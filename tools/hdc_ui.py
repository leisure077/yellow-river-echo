# -*- coding: utf-8 -*-
"""模拟器 UI 自动化小工具（开发用，不进 App 代码）。

用法：
  python tools/hdc_ui.py dump [关键词]      # dumpLayout 并列出可见文本+坐标
  python tools/hdc_ui.py tap x y            # 点击（像素）
  python tools/hdc_ui.py drag x1 y1 x2 y2   # 拖动
  python tools/hdc_ui.py shot 名字           # 截图并收到 shots/<名字>.jpeg
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hh_env  # hdc 在哪、连哪台设备：环境变量 > 自动探测 > 明确报错
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCAL_TMP = os.path.join(ROOT, ".tmp")


def sh(args):
    cmd = [hh_env.hdc(), "-t", hh_env.device(), "shell"]
    cmd += [args] if isinstance(args, str) else list(args)
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return (r.stdout or "") + (r.stderr or "")


def dump(kw=None):
    out = sh("uitest dumpLayout -p /data/local/tmp/ui.json")
    if "success" not in out and "Dump" not in out:
        print("dumpLayout failed:", out.strip()[:300])
        return []
    local = os.path.join(LOCAL_TMP, "ui_dump.json")
    subprocess.run([hh_env.hdc(), "-t", hh_env.device(), "file", "recv",
                    "/data/local/tmp/ui.json", local],
                   capture_output=True, text=True, encoding="utf-8", errors="replace")
    data = json.load(open(local, encoding="utf-8"))
    rows = []

    def walk(node):
        a = node.get("attributes", {})
        t = (a.get("text") or a.get("description") or "").strip()
        if t:
            rows.append((t, a.get("bounds"), a.get("type"), a.get("enabled")))
        for c in node.get("children", []) or []:
            walk(c)

    walk(data if "attributes" in data else data.get("root", data))
    if kw:
        rows = [r for r in rows if kw in r[0]]
    sys.stdout.reconfigure(encoding="utf-8")
    for t, b, ty, en in rows:
        print("%-28s | %-30s | %s | en=%s" % (t[:28], b, ty, en))
    return rows


def center(bounds):
    x1, y1, x2, y2 = [int(v) for v in bounds.replace("][", " ").replace("[", "").replace("]", "").split()]
    return (x1 + x2) // 2, (y1 + y2) // 2


def find(text):
    rows = dump()
    for t, b, ty, en in rows:
        if text in t:
            return center(b)
    return None


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    cmd = sys.argv[1]
    if cmd == "dump":
        dump(sys.argv[2] if len(sys.argv) > 2 else None)
    elif cmd == "find":
        p = find(sys.argv[2])
        print("POS " + (str(p[0]) + " " + str(p[1]) if p else "NOT_FOUND"))
    elif cmd == "tap":
        print(sh("uinput -T -c %s %s" % (sys.argv[2], sys.argv[3])).strip())
    elif cmd == "drag":
        print(sh("uinput -T -m %s %s %s %s 600" % tuple(sys.argv[2:6])).strip())
    elif cmd == "shot":
        name = sys.argv[2]
        sh("snapshot_display -f /data/local/tmp/s.jpeg")
        local = os.path.join(ROOT, "shots", name + ".jpeg")
        os.makedirs(os.path.dirname(local), exist_ok=True)
        subprocess.run([hh_env.hdc(), "-t", hh_env.device(), "file", "recv",
                        "/data/local/tmp/s.jpeg", local],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
        print(local, os.path.getsize(local) if os.path.exists(local) else "MISSING")
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
