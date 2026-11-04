# -*- coding: utf-8 -*-
"""点设置页里的「测一下」，抓 App 自己给出的自检结论。

这条链路是给「换一台电脑/别人接手」准备的：不用看代码、不用抓包，
设置页那一行话就能把 地址不通 / Key 被拒 / 地址对但接口不对 / 一切正常 分开。

用法：
    python tools/probe_ui_check.py                 # 用输入框里现有的地址测
    python tools/probe_ui_check.py http://x/v1     # 先把地址栏改成它再测（不点保存）
    python tools/probe_ui_check.py dump            # 只把设置卡片上的行和坐标列出来

退出码：0=通了，2=自检报了别的情况（报的内容就是要看的东西），1=没点到按钮。
前提：模拟器停在河小导全屏页（首页右上角「问」→ 去全屏 ›）。
"""
import sys
import time

sys.path.insert(0, __file__.replace("\\", "/").rsplit("/", 1)[0])
import set_dify_cfg as ui

# 自检行的开头几种可能，全来自 AiService.probe()
MARKS = ("通了", "连不上", "地址通", "服务回", "地址不对", "先填 App Key", "正在试", "没测成")


def exact(needle):
    for r in ui.rows():
        if r[0] == needle:
            return r
    return None


def find_mark():
    for r in ui.rows():
        if r[0].startswith("正在试"):
            continue          # 这是点下去之后的过渡态，不是结论
        for m in MARKS:
            if r[0].startswith(m):
                return r[0]
    return ""


def msg(deadline):
    """等自检回话；正在试… 不算结果。"""
    t0 = time.time()
    while time.time() - t0 < deadline:
        cur = find_mark()
        if cur and not cur.startswith("正在试"):
            return cur
        time.sleep(0.6)
    return ""


def dump():
    if not ui.open_settings():
        print("进不去设置卡片"); return 1
    for r in ui.rows():
        if r[0]:
            print("%-10s (%4d,%4d) %s" % (r[1], r[2], r[3], r[0][:60]))
    return 0


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    if len(sys.argv) > 1 and sys.argv[1] == "dump":
        return dump()
    if not ui.open_settings():
        print("进不去设置卡片"); return 1
    if len(sys.argv) > 1:
        # 只动地址栏，Key 保持设备里已有的值，免得两件事混在一起验
        if not ui.fill(0, sys.argv[1]):
            print("地址栏没写好"); return 1
    btn = exact("测一下") or exact("试中…")
    if not btn:
        print("设置卡片里没有「测一下」：装的是旧包？")
        dump()
        return 1
    before = find_mark()
    ui.tap(btn[2], btn[3])
    # 上一轮的结论可能还挂在屏幕上，文字一模一样也会被当成"没变化"。
    # 所以认两种信号：出现过渡态 正在试…（说明这次真点下去了，之后等它换成结论），
    # 或者文字直接变了（快得没抓到过渡态，本机 1.1s 通的这一次就是）。
    # 地址彻底不通时 http 侧要等自己的超时：本机实测端口 9 是 40 秒开外，这里给 120 秒。
    t0 = time.time()
    started = False
    got = ""
    while time.time() - t0 < 120:
        time.sleep(0.7)
        cur = find_mark()
        if not started:
            if any(r[0].startswith("正在试") for r in ui.rows()):
                started = True
                continue
            if cur and cur != before:
                got = cur
                break
        elif cur:
            got = cur
            break
    print("自检结果（%.1fs）：%s" % (time.time() - t0, got if got else "120 秒内没出结果"))
    line = [r for r in ui.rows() if r[0].startswith("最近一次失败")]
    if line:
        print("界面另有一行：", line[0][0][:80])
    return 0 if got.startswith("通了") else 2


if __name__ == "__main__":
    sys.exit(main())
