# -*- coding: utf-8 -*-
"""在河小导全屏页问一句，量 App 界面侧的首字时间，并判断这次是出答案还是报错。

配合 tools/stall_mock.py 用：把 App 的 Dify 地址指到假服务，
静默时长就成了可控量，看门狗阈值改得对不对能直接验出来。

用法：python tools/stall_ui_check.py [问题] [最长等多久秒]
前提：模拟器停在河小导全屏页（首页右上角「问」→ 去全屏 ›）。
"""
import sys
import time

sys.path.insert(0, __file__.replace("\\", "/").rsplit("/", 1)[0])
import set_dify_cfg as ui   # 复用同一套 dumpLayout / 点击封装

ERR_MARKS = ("翻得有点久", "够不着", "开不了门", "找不到档案室", "没听清", "走神")


def exact(needle):
    for r in ui.rows():
        if r[0] == needle:
            return r
    return None


def ensure_fullscreen():
    """走到河小导全屏页，模拟器刚开机停在首页也能自己走进去。
    两个坑都实测过：
      - keyEvent 2 是「返回」，在首页/悬浮窗上按下去会把页面直接退掉，
        所以收键盘这一手只在已经确认在河小导页（屏上有 设置）时才允许用；
      - 首页右上角的入口和全屏页的发送键都叫「问」，只能靠位置分开：
        入口在顶上（cy<400），发送键在底下（cy>2400）。
    """
    for _ in range(6):
        ins = ui.inputs()
        on_page = exact("设置") is not None
        if on_page and ins and ins[-1][3] > 2400:
            return True
        g = ui.by_text("去全屏")
        if g:                                     # 助手悬浮卡片：先进全屏
            ui.tap(g[2], g[3])
            time.sleep(1.2)
            continue
        if on_page and ins and ins[-1][3] <= 2400:
            ui.sh("uitest uiInput keyEvent Back")  # 键盘把输入行顶到上面了，先收键盘
            time.sleep(1.0)
            continue
        q = exact("问")
        if q and q[3] < 400:                       # 首页右上角的入口
            ui.tap(q[2], q[3])
            time.sleep(1.2)
            continue
        return False
    return False


def ask(q, max_wait):
    sh = ui.sh
    if not ensure_fullscreen():
        print("进不到河小导全屏页：首页右上角「问」→ 去全屏 ›")
        return 1
    ins = ui.inputs()
    inp = ins[-1]
    ui.tap(inp[2], inp[3])
    sh("uitest uiInput inputText %d %d %s" % (inp[2], inp[3], q))
    time.sleep(0.8)
    a = exact("问")
    if not a:
        print("没找到 问 按钮（占位符里也有「问」，所以只认整词）")
        return 1
    t0 = time.time()
    ui.tap(a[2], a[3])
    # 以「点问之前屏上已有的文案」为底，之后新出现的长文本才算回答，免得把界面固定话术认成答案
    before = set(r[0] for r in ui.rows())

    ttft = None
    err = None
    body = ""
    while time.time() - t0 < max_wait:
        rs = ui.rows()
        for r in rs:
            if r[1] != "Text":
                continue
            for mark in ERR_MARKS:
                if mark in r[0]:
                    err = r[0]
            if err:
                continue                      # 报错文案也是新出现的长文本，别当成回答
            if r[0] in before or len(r[0]) <= 20:
                continue
            if ttft is None:
                ttft = time.time() - t0
            body = r[0]
        if err:
            break
        # 流完的标志：问 按钮回来了（用精确匹配，输入框占位符也带「问」字）
        if ttft is not None and exact("问") and body:
            break
        time.sleep(2)
    dt = time.time() - t0
    print("首字 %.1fs｜用时 %.1fs" % (ttft if ttft is not None else -1, dt))
    if err:
        print("报错文案：%s" % err[:60])
        return 2
    print("回答开头：%s" % body[:40])
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    q = sys.argv[1] if len(sys.argv) > 1 else "详细讲讲仰韶村遗址的博物馆和展陈"
    sys.exit(ask(q, float(sys.argv[2]) if len(sys.argv) > 2 else 100.0))
