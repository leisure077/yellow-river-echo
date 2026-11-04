# -*- coding: utf-8 -*-
"""按真实坐标点 停：验证中断标记。

uitest uiInput inputText 会拉起软键盘，输入行会被顶到上面去，
固定坐标会点到键盘上，所以这里每次都从 dumpLayout 现查按钮中心。
"""
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hh_env  # hdc 在哪、连哪台设备：环境变量 > 自动探测 > 明确报错

DUMP = os.path.join(hh_env.ROOT, ".tmp", "stop_probe_dump.json")


def run_shell(cmd):
    return subprocess.run([hh_env.hdc(), "-t", hh_env.device(), "shell", cmd],
                          capture_output=True, text=True, encoding="utf-8", errors="replace").stdout


def tree():
    run_shell("uitest dumpLayout -p /data/local/tmp/ui.json")
    os.makedirs(os.path.dirname(DUMP), exist_ok=True)
    subprocess.run([hh_env.hdc(), "-t", hh_env.device(), "file", "recv",
                    "/data/local/tmp/ui.json", DUMP], capture_output=True)
    return json.load(open(DUMP, encoding="utf-8"))


def boxes(node, txt=None, min_len=0):
    out = []

    def walk(n):
        a = n.get("attributes", {})
        t = (a.get("text") or "").strip()
        b = a.get("bounds") or ""
        p = b.split("][")
        if len(p) == 2:
            try:
                x1, y1 = [int(v) for v in p[0].strip("[]").split(",")]
                x2, y2 = [int(v) for v in p[1].strip("[]").split(",")]
            except ValueError:
                x1 = y1 = x2 = y2 = 0
            if (txt is None and len(t) >= min_len) or t == txt:
                out.append((t, x1, y1, x2, y2))
        for c in n.get("children", []) or []:
            walk(c)

    walk(node)
    return out


def center(items):
    x1, y1, x2, y2 = items[-1][1:]
    return (x1 + x2) // 2, (y1 + y2) // 2


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    q = sys.argv[1] if len(sys.argv) > 1 else "详细讲讲仰韶村遗址的博物馆和展陈"
    wait = float(sys.argv[2]) if len(sys.argv) > 2 else 2.5

    inp = boxes(tree(), min_len=0)
    tb = [r for r in inp if r[0] == ""]
    d = tree()
    # 输入框：TextInput 没有 text，用 type 找
    def find_input(n):
        a = n.get("attributes", {})
        if a.get("type") in ("TextInput", "TextArea"):
            b = (a.get("bounds") or "").split("][")
            if len(b) == 2:
                x1, y1 = [int(v) for v in b[0].strip("[]").split(",")]
                x2, y2 = [int(v) for v in b[1].strip("[]").split(",")]
                return (x1 + x2) // 2, (y1 + y2) // 2
        for c in n.get("children", []) or []:
            r = find_input(c)
            if r:
                return r
        return None

    ip = find_input(d)
    print("input at", ip)
    run_shell("uitest uiInput inputText %d %d %s" % (ip[0], ip[1], q))
    time.sleep(0.6)
    d = tree()
    ask = boxes(d, "问")
    if not ask:
        print("没找到 问 按钮")
        return
    ax, ay = center(ask)
    run_shell("uinput -T -c %d %d" % (ax, ay))
    print("sent at", ax, ay)
    time.sleep(wait)
    d = tree()
    stop = boxes(d, "停")
    if not stop:
        print("还没进入流式（或已结束），当前按钮：", [r[0] for r in boxes(d) if r[0] in ("问", "停")])
        return
    sx, sy = center(stop)
    print("tap 停 at", sx, sy)
    run_shell("uinput -T -c %d %d" % (sx, sy))
    time.sleep(1.2)
    d = tree()
    print("按钮:", [r[0] for r in boxes(d) if r[0] in ("问", "停")])
    for t, *_ in boxes(d, min_len=40):
        if "中断" in t or t.startswith("您好") or "仰韶" in t:
            print("TAIL:", t[:120])
    long = boxes(d, min_len=40)
    if long:
        print("LAST:", long[-1][0][:160])


if __name__ == "__main__":
    main()
