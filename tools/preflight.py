"""演示前一条命令自检：后端起没起、模型常驻没常驻、设备连着没、包新不新。

用法：
    python tools/preflight.py            # 全跑，红绿清单
    python tools/preflight.py --quick    # 跳设备上那几项（没开模拟器时用）

退出码 0=可以直接演示；2=能演示但会撞慢（冷态首字之类）；1=有一项直接连不通。
每一项失败都跟着"怎么办"，不用再去翻 dify/README 的编号。
地址与 Key 一律走 hh_env（环境变量 > 自动探测 > 明确报错），这里不写死，
Key 只报长度和前缀。
"""
import io
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hh_env

sys.stdout.reconfigure(encoding="utf-8")

ROOT = hh_env.ROOT
HAP = os.path.join(ROOT, "entry", "build", "default", "outputs", "default",
                   "entry-default-signed.hap")
HAP_FALLBACK = HAP.replace("-signed", "-unsigned")
BUNDLE = "com.example.demo01"
PREFS = "/data/app/el2/100/base/%s/haps/entry/preferences/hh_ai" % BUNDLE
NEED_CONTAINERS = ["nginx", "api", "worker", "db_postgres", "redis", "weaviate", "web"]

OK, WARN, FAIL = "ok  ", "WARN", "FAIL"
rows = []

def say(level, what, how):
    rows.append((level, what, how))
    print("[%s] %-34s %s" % (level, what, how if how else ""))

def get(url, headers=None, timeout=6):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read().decode("utf-8", "replace")

def check_docker():
    try:
        out = subprocess.run(["docker", "ps", "--format", "{{.Names}}\t{{.Status}}"],
                             capture_output=True, text=True, encoding="utf-8",
                             errors="replace", timeout=25)
    except Exception as e:
        say(FAIL, "Docker 引擎", "连不上（%s）：先启动 Docker Desktop，等状态变绿" % type(e).__name__)
        return {}
    if out.returncode != 0:
        say(FAIL, "Docker 引擎", out.stderr.strip()[:60] + " → 启动 Docker Desktop")
        return {}
    live = {}
    for line in out.stdout.splitlines():
        if "\t" in line:
            name, st = line.split("\t", 1)
            live[name] = st
    miss = [n for n in NEED_CONTAINERS
            if not any(("docker-" + n + "-") in k or (n + "-") in k for k in live)]
    if miss:
        say(FAIL, "Dify 容器", "没在跑：%s → cd dify 部署目录后 docker compose up -d" % " ".join(miss))
    else:
        say(OK, "Dify 容器", "%d 个在跑" % len([k for k in live if k.startswith("docker-")]))
    return live

def check_dify():
    base = hh_env.base()
    key = hh_env.app_key()
    t0 = time.time()
    try:
        code, _ = get(base + "/parameters", {"Authorization": "Bearer " + key}, 10)
    except Exception as e:
        say(FAIL, "Dify /v1 + App Key", "打不通（%s）→ 看 dify/README 第 7 节；"
            "容器在跑但全路由超时，就先 docker restart docker-api-1（只 restart，别 rm 容器和卷）"
            % type(e).__name__)
        return
    ms = (time.time() - t0) * 1000
    if code == 200:
        say(OK if ms < 4000 else WARN, "Dify /v1 + App Key",
            "%.0fms 回 200（Key %s）" % (ms, hh_env.brief(key))
            + ("" if ms < 4000 else " → 首次调用慢是 worker 冷启动，正式演示前先点一次「测一下」"))
    elif code in (401, 403):
        say(FAIL, "Dify /v1 + App Key", "%d：钥匙开不了门 → Dify 应用页重复制 App Key，"
            "或 set HH_APP_KEY=app-..." % code)
    elif code == 404:
        say(FAIL, "Dify /v1 + App Key", "404：地址不是 /v1 接口地址 → HH_DIFY_BASE 填 http://127.0.0.1/v1")
    else:
        say(FAIL, "Dify /v1 + App Key", "回 %d" % code)

def check_ollama():
    try:
        code, body = get("http://127.0.0.1:11434/api/tags", timeout=5)
    except Exception:
        say(FAIL, "Ollama", "11434 没起 → 启动 Ollama，再 ollama pull bge-m3")
        return
    names = re.findall(r'"name":"([^"]+)"', body)
    if not any(n.startswith("bge-m3") for n in names):
        say(FAIL, "Ollama", "在跑但没有 bge-m3（现有 %s）→ ollama pull bge-m3" % (names or "无"))
        return
    say(OK, "Ollama", "bge-m3 就绪")
    try:
        _, ps = get("http://127.0.0.1:11434/api/ps", timeout=5)
    except Exception:
        ps = ""
    if "bge-m3" not in ps:
        say(WARN, "bge-m3 是否常驻",
            "没在显存里 → 下一问要重装模型，首字实测 34.5s（设了 OLLAMA_KEEP_ALIVE=-1 是 13.0s）；"
            "演示前先问一句预热，或给 Ollama 进程加这个环境变量")
    else:
        say(OK, "bge-m3 是否常驻", "常驻中（首字实测约 13s）")

def check_device(quick):
    if quick:
        return
    try:
        h = hh_env.hdc()
    except Exception as e:
        say(FAIL, "hdc", str(e)[:60] + " → set HH_HDC=<你的 toolchains/hdc.exe>")
        return
    out = subprocess.run([h, "list", "targets"], capture_output=True, text=True,
                         encoding="utf-8", errors="replace", timeout=20)
    targets = [t.strip() for t in out.stdout.splitlines() if t.strip() and t.strip() != "[Empty]"]
    if not targets:
        say(FAIL, "设备", "hdc 看不到设备 → 开模拟器，或 hdc tconn 127.0.0.1:5555")
        return
    dev = hh_env.device() if hh_env.device() in targets else targets[0]
    say(OK, "设备", "%s 在线" % dev)
    bm = subprocess.run([h, "-t", dev, "shell", "bm", "dump", "-n", BUNDLE],
                        capture_output=True, text=True, encoding="utf-8",
                        errors="replace", timeout=30).stdout
    if "versionName" not in bm:
        say(FAIL, "App 是否装了", "%s 没装 → hdc install -r 那个 hap" % BUNDLE)
    else:
        say(OK, "App 是否装了", re.search(r"versionName\[\S*?([^\]\s]+)", bm).group(1)
            if re.search(r"versionName\[\S*?([^\]\s]+)", bm) else "已装")
    pref = subprocess.run([h, "-t", dev, "shell", "cat", PREFS], capture_output=True,
                          text=True, encoding="utf-8", errors="replace", timeout=30).stdout
    m = re.search(r'<string key="baseUrl">([^<]*)</string>', pref)
    if not m:
        say(WARN, "App 里的 Dify 地址", "没读到 baseUrl（首次启动还没存过）→ 打开河小导设置填地址，"
            "或 python tools/set_dify_cfg.py http://10.0.2.2/v1")
    else:
        u = m.group(1)
        if "127.0.0.1" in u or "localhost" in u:
            say(FAIL, "App 里的 Dify 地址", "%s 在模拟器里指向它自己 → 改成 http://10.0.2.2/v1" % u)
        elif u.rstrip("/").endswith("/v1"):
            say(OK, "App 里的 Dify 地址", u)
        else:
            say(WARN, "App 里的 Dify 地址", "%s 没带 /v1（App 会自己补，但别写成控制台地址）" % u)

def check_build():
    hap = HAP if os.path.exists(HAP) else HAP_FALLBACK
    if not os.path.exists(hap):
        say(FAIL, "hap 新不新", "还没构建 → README 第 2 节那条 assembleHap")
        return
    newest = 0
    for dp, _, fs in os.walk(os.path.join(ROOT, "entry", "src")):
        if "build" in dp.split(os.sep):
            continue
        for f in fs:
            if f.endswith((".ets", ".json5", ".json")):
                newest = max(newest, os.path.getmtime(os.path.join(dp, f)))
    gap = newest - os.path.getmtime(hap)
    if gap > 0:
        say(FAIL, "hap 新不新", "源码比 hap 新 %.0f 分钟 → 重新 assembleHap 并 hdc install -r"
            % (gap / 60))
    else:
        say(OK, "hap 新不新", "hap 不比源码旧（%.1f MB）" % (os.path.getsize(hap) / 1048576))

def main():
    quick = "--quick" in sys.argv
    print("项目根 " + ROOT)
    print("探测到的 Dify 地址 " + hh_env.base())
    print("—— 后端 ——")
    check_docker()
    check_dify()
    check_ollama()
    print("—— 设备 ——")
    check_device(quick)
    check_build()
    f = sum(1 for lv, _, _ in rows if lv == FAIL)
    w = sum(1 for lv, _, _ in rows if lv == WARN)
    print("\n%d 项通过 / %d 项注意 / %d 项连不通"
          % (sum(1 for lv, _, _ in rows if lv == OK), w, f))
    sys.exit(1 if f else (2 if w else 0))

main()
