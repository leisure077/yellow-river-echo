"""快照摆渡：把一台设备导出的备份取到电脑、验一遍、再摊成局域网地址给另一台设备拉。

为什么不是 hdc file send：这台镜像上 hdc shell 是 uid=2000(shell)、context=u:r:sh:s0，
对 App 沙箱（app_data_file）**只读不可写**，file send 直接 permission denied；
退一步写到 shell 可写的 /data/local/tmp 也没用——实测在里面临时文件 chmod 777 之后，
App 侧读依旧是 readable=false（SELinux 拦的是标签，不是 DAC 权限）。
所以进来的路换成 App 自己伸手：App 有 INTERNET 权限，模拟器里 10.0.2.2 就是宿主机
（Dify 那条链路已实测通），由 App 从电脑上拉，比在设备上敲一整条 URL 也快。

用法：
  python tools/snap_bridge.py check [文件]     # 只验一份快照：校验和 + 有没有带口令字段
  python tools/snap_bridge.py recv [--dev 设备] # 从某台设备取最新快照到 .tmp/snaps/
  python tools/snap_bridge.py serve [--dev 设备] [--port 8877] [--no-recv]
        取最新 → 复制成 hhmem_latest.json → 验一遍 → 起 HTTP 服务，
        然后到另一台设备的「同步与备份 → 备份快照」里点「拉取导入」（地址已预填）。

设备侧填的地址：http://10.0.2.2:8877/hhmem_latest.json
（端口 8877 是特意避开假 Dify 的 8899，两个服务可以同时开着。）
"""
import functools
import glob
import http.server
import json
import os
import re
import socketserver
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hh_env

ROOT = hh_env.ROOT
BUNDLE = "com.example.demo01"
REMOTE_DIR = "/data/app/el2/100/base/%s/haps/entry/files/backups" % BUNDLE
OUT_DIR = os.path.join(ROOT, ".tmp", "snaps")
LATEST = "hhmem_latest.json"
DEFAULT_PORT = 8877
SECRET_KEYS = ["digest", "pwd", "password", "passwd", "token", "secret"]

def _hdc(args, timeout=180):
    r = subprocess.run([hh_env.hdc()] + args, capture_output=True,
                       text=True, encoding="utf-8", errors="replace", timeout=timeout)
    return (r.stdout or "") + (r.stderr or "")

def _json_dump(v):
    """贴近 ArkTS 的 JSON.stringify：紧凑分隔符 + 不转义中文 + 不重排键。"""
    return json.dumps(v, separators=(",", ":"), ensure_ascii=False)

def fnv16(s):
    """复刻 MemoryStore.fnv：按 UTF-16 code unit 逐个算，32 位回绕。"""
    units = []
    for ch in s:
        o = ord(ch)
        if o > 0xFFFF:
            o -= 0x10000
            units.append(0xD800 + (o >> 10))
            units.append(0xDC00 + (o & 0x3FF))
        else:
            units.append(o)
    h = 2166136261
    for u in units:
        h ^= u
        h = (h * 16777619) & 0xFFFFFFFF
    return h

def body_of(d):
    """校验和覆盖的正文，口径和 MemoryStore.bodyOf 一致（v2 才带 accounts）。"""
    s = _json_dump(d["favorites"]) + _json_dump(d["notes"]) + _json_dump(d["tags"]) \
        + _json_dump(d["progress"]) + _json_dump(d["topics"])
    if d.get("formatVer", 1) >= 2 and "accounts" in d:
        s += _json_dump(d["accounts"])
    return s

def _leaks(text):
    """只找「字段名」形状的命中（"digest" 这种带引号的键），避免正文里正好写了这个词被误报。"""
    hits = []
    for k in SECRET_KEYS:
        if ('"%s"' % k) in text:
            hits.append(k)
    return hits

def check(path):
    raw = open(path, encoding="utf-8").read()
    d = json.loads(raw)
    calc = fnv16(body_of(d))
    ok = calc == d.get("checksum")
    acc = d.get("accounts") or []
    leak = sorted(set(_leaks(_json_dump(acc)) + _leaks(raw)))
    print("%s" % os.path.basename(path))
    print("  formatVer=%s appVer=%s siteCount=%s 笔记 %d / 收藏 %d / 标签 %d / 进度 %d / 专题 %d / 档案 %d"
          % (d.get("formatVer"), d.get("appVer"), d.get("siteCount"), len(d.get("notes", [])),
             len(d.get("favorites", [])), len(d.get("tags", [])), len(d.get("progress", [])),
             len(d.get("topics", [])), len(acc)))
    print("  校验和：文件 %s，本地重算 %s → %s" % (d.get("checksum"), calc, "一致" if ok else "不一致"))
    if acc:
        print("  档案字段：%s" % sorted(acc[0].keys()))
    print("  口令类字段：%s" % ("没找到" if not leak else "命中 " + "/".join(leak) + " ← 这份不能用"))
    if d.get("notes"):
        d2 = json.loads(raw)
        k = sorted(d2["notes"][0].keys())[0]
        d2["notes"][0][k] = str(d2["notes"][0][k]) + "X"
        broke = fnv16(body_of(d2)) != d.get("checksum")
        print("  篡改一字：%s" % ("校验和立刻对不上（闸门有效）" if broke else "仍验得过（闸门是摆设）"))
    return ok and not leak

def remote_list(dev):
    out = _hdc(["-t", dev, "shell", "ls -1 %s 2>/dev/null" % REMOTE_DIR])
    names = [n.strip() for n in out.splitlines()
             if n.strip().startswith("hhmem_backup_") and n.strip().endswith(".json")]
    names.sort(key=lambda n: int(re.findall(r"\d+", n)[0]) if re.findall(r"\d+", n) else 0)
    return names

def recv(dev):
    names = remote_list(dev)
    if not names:
        print("设备 %s 的 %s 里没有快照，先在那台设备上点「导出快照」。" % (dev, REMOTE_DIR))
        return None
    newest = names[-1]
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)
    dst = os.path.join(OUT_DIR, newest)
    if os.path.exists(dst) and os.path.getsize(dst) > 0:
        print("已经取过了：%s" % dst)
    else:
        msg = _hdc(["-t", dev, "file", "recv", "%s/%s" % (REMOTE_DIR, newest), OUT_DIR])
        print(msg.strip().splitlines()[-1] if msg.strip() else "file recv 没回话")
    if not os.path.exists(dst):
        print("取不到 %s（这台设备沙箱只读，recv 应当能成；看上面 hdc 的报错）" % newest)
        return None
    with open(dst, encoding="utf-8") as f:
        text = f.read()
    raw = json.loads(text)
    if fnv16(body_of(raw)) != raw.get("checksum"):
        print("这份快照校验和对不上，不摊到局域网里：%s" % newest)
        return None
    if _leaks(_json_dump(raw.get("accounts") or [])):
        print("这份快照的档案里带口令字段，拒绝摊出：%s" % newest)
        return None
    latest = os.path.join(OUT_DIR, LATEST)
    with open(latest, "w", encoding="utf-8") as f:
        f.write(text)
    print("最新一份：%s（%d B）→ 复制成 %s" % (newest, os.path.getsize(dst), LATEST))
    return latest

def serve(port):
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=OUT_DIR)
    with socketserver.ThreadingTCPServer(("0.0.0.0", port), handler) as httpd:
        print("\n已在 %d 端口摊开 %s。另一台设备上点「拉取导入」，地址填："
              % (port, OUT_DIR))
        print("    http://10.0.2.2:%d/%s" % (port, LATEST))
        print("（真机在同一局域网里就换成这台电脑的局域网 IP；Ctrl+C 停）")
        sys.stdout.flush()
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n停了。")

def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    args = sys.argv[1:]
    cmd = args[0] if args else "serve"
    dev = _flag(args, "--dev", hh_env.device())
    port = int(_flag(args, "--port", str(DEFAULT_PORT)))
    if cmd == "check":
        path = args[1] if len(args) > 1 else None
        if not path:
            got = glob.glob(os.path.join(OUT_DIR, "hhmem_backup_*.json"))
            if not got:
                print("既没给路径，.tmp/snaps/ 里也没文件；先跑 recv。")
                return 1
            path = sorted(got)[-1]
        return 0 if check(path) else 2
    if cmd == "recv":
        return 0 if recv(dev) else 2
    if cmd == "serve":
        if "--no-recv" not in args:
            if not recv(dev):
                print("没取到快照，服务不起；设备点「导出快照」之后再跑，或加 --no-recv 摊已有的。")
                return 2
        if not os.path.isdir(OUT_DIR):
            os.makedirs(OUT_DIR)
        serve(port)
        return 0
    print(__doc__)
    return 1

def _flag(args, name, default):
    if name in args:
        i = args.index(name)
        if i + 1 < len(args):
            return args[i + 1]
    return default

if __name__ == "__main__":
    import functools
    sys.exit(main())
