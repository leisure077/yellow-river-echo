# -*- coding: utf-8 -*-
"""在模拟器里把「河小导 → 设置」的 Dify 地址和 App Key 改对并保存。

为什么要点 UI 而不是改 preferences 文件：hdc shell 是 uid=2000(shell)，
对 App 沙箱目录只读，写不进去；而且设置页才是游客/演示真正会走的路径。

坑（都实测过）：
  - `uitest uiInput inputText` 会拉起软键盘，键盘把整页顶上去，
    所以每次输入后必须重新 dumpLayout 拿 保存 的当前坐标，不能复用旧坐标。
  - 删除只能用原生按键 `uinput -K -d 2055 -u 2055`。
    `uitest uiInput keyEvent 2055` 打在这两个 TextInput 上一颗字都删不掉，
    结果就是新 Key 拼在旧 Key 前面，存成 170 字符的废值。
  - Ctrl+A(keyEvent 2072 97) 不生效；长按弹的「全选」菜单不稳定，别指望。
  - 密码框在 dumpLayout 里是 **** 掩码，但颗数和真实长度一致，所以界面侧只能数长度；
    真实值以 preferences 文件为准（cat 回本地解析，只报长度和前缀，不打印值）。
  - App Key 框拉起的是「安全键盘」，退格丢包严重，原因和对策见 clear() 的注释。

用法：python tools/set_dify_cfg.py <baseUrl> [appKey]
  appKey 省略时从本机 Dify 的 api_tokens 表里取，不落盘、不打印。
"""
import json
import re
import subprocess
import sys
import time

HDC = r"C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
DEV = "127.0.0.1:5555"
PREFS = "/data/app/el2/100/base/com.example.demo01/haps/entry/preferences/hh_ai"


def sh(args):
    r = subprocess.run([HDC, "-t", DEV, "shell", args],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    return (r.stdout or "") + (r.stderr or "")


def rows():
    """dumpLayout 后返回 [(text, type, cx, cy)]，坐标一律取控件自己的 bounds 中心。"""
    sh("uitest dumpLayout -p /data/local/tmp/ui.json")
    local = ".tmp/ui_dump.json"
    subprocess.run([HDC, "-t", DEV, "file", "recv", "/data/local/tmp/ui.json", local],
                   capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = []

    def walk(n):
        a = n.get("attributes", {})
        t = (a.get("text") or a.get("description") or "").strip()
        ty = a.get("type") or ""
        nums = re.findall(r"-?\d+", a.get("bounds") or "")
        if ty and len(nums) == 4:
            x1, y1, x2, y2 = [int(v) for v in nums]
            out.append((t, ty, (x1 + x2) // 2, (y1 + y2) // 2, x1, y1, x2, y2))
        for c in n.get("children", []) or []:
            walk(c)

    d = json.load(open(local, encoding="utf-8"))
    walk(d if "attributes" in d else d.get("root", d))
    return out


def by_text(needle, ty=None):
    for r in rows():
        if needle in r[0] and (ty is None or r[1] == ty):
            return r
    return None


def tap(x, y):
    sh("uinput -T -c %d %d" % (x, y))
    time.sleep(0.9)


def inputs():
    rs = [r for r in rows() if r[1] == "TextInput"]
    rs.sort(key=lambda r: r[3])
    return rs


def clear(idx):
    """删到空为止。
    实测退格键会掉：连着发 8 下，最多收 4 下；一旦掉焦点，后面整批全丢。
    所以每轮都重新点一下输入框、每颗键之间留 80ms，按完回读一次。
    """
    for _ in range(20):
        f = inputs()[idx]
        if f[0] == "":
            return True
        tap(f[2], f[3])
        for _ in range(6):
            sh("uinput -K -d 2055 -u 2055")
            time.sleep(0.08)
        time.sleep(0.2)
    return inputs()[idx][0] == ""


def fill(idx, text):
    f = inputs()[idx]
    tap(f[2], f[3])
    for attempt in range(2):
        if not clear(idx):
            print("第 %d 栏删不干净，还剩 %d 字符" % (idx + 1, len(inputs()[idx][0])))
            continue
        # ASCII 走原生按键（实测能触发 onChange）；中文交给 uitest，原生 -t 不吃非 ASCII
        if text.isascii():
            sh("uinput -K -t " + text)
        else:
            sh("uitest uiInput inputText %d %d %s" % (f[2], f[3], text))
        time.sleep(1.0)
        got = len(inputs()[idx][0])
        if got == len(text):
            return True
        print("第 %d 栏打完是 %d 字符，期望 %d，重来" % (idx + 1, got, len(text)))
    return False


def open_settings():
    """把界面弄回能点 设置 的样子再进卡片。
    问完一句之后页面是滚到底的、键盘还弹着，表头的 设置 不在屏上，
    所以先收键盘（keyEvent 2）再往下划回顶部，最多试 3 次。
    """
    for _ in range(3):
        if by_text("接入设置"):
            return True
        s = by_text("设置")
        if s:
            tap(s[2], s[3])
            time.sleep(1.2)
            if by_text("接入设置"):
                return True
            continue
        sh("uitest uiInput keyEvent 2")
        time.sleep(0.8)
        sh("uinput -T -m 640 900 640 2200 800")
        time.sleep(1.0)
    return False


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    base = sys.argv[1]
    key = sys.argv[2] if len(sys.argv) > 2 else None
    if key is None:
        key = subprocess.run(["docker", "exec", "docker-db_postgres-1", "psql", "-U", "postgres",
                              "-d", "dify", "-t", "-A", "-c", "select token from api_tokens limit 1"],
                             capture_output=True, text=True).stdout.strip()
    assert key.startswith("app-"), "拿到的不是 Dify 的 app- 开头 Key"

    # 1. 打开设置卡片
    if not open_settings():
        print("进不去设置卡片：请确认停在河小导全屏页（首页右上角「问」→ 去全屏 ›）")
        return 1
    print("设置卡片已打开")

    # 2. 两个输入框按屏幕顺序：上面是地址，下面是 Key
    if len(inputs()) < 2:
        print("输入框数量不对:", [(r[0][:20], r[1]) for r in inputs()])
        return 1
    if not fill(0, base):
        print("地址栏没写好"); return 1
    if not fill(1, key):
        print("App Key 栏没写好"); return 1

    # 3. 键盘弹起后 保存 会移位，必须重新找
    sv = by_text("保存")
    if not sv:
        print("没找到 保存")
        return 1
    tap(sv[2], sv[3])
    time.sleep(1.5)
    print("已点保存，接入设置卡片是否还在：", bool(by_text("接入设置")))

    # 4. 以落盘值为准：preferences 文件 shell 只读得动，写得动的是 App 自己。
    #    设备上的 shell 没有 awk/tr，只能 cat 回来在本地解析；Key 只报长度和前缀。
    raw = sh("cat " + PREFS).replace("\n", "")
    got = {}
    for k in ("baseUrl", "appKey"):
        m = re.search(r'key="%s"[^>]*>([^<]*)' % k, raw)
        got[k] = m.group(1) if m else None
    print("落盘 baseUrl =", got.get("baseUrl"))
    print("落盘 appKey：长度 %s，前缀 %s，与输入一致 %s，没有 sk-ws 残留 %s"
          % (len(got.get("appKey") or ""), (got.get("appKey") or "")[:4],
             got.get("appKey") == key, "sk-ws" not in raw))
    return 0 if got.get("baseUrl") == base and got.get("appKey") == key else 1


if __name__ == "__main__":
    sys.exit(main())
