"""tools 里共用的一台机器参数：hdc 在哪、连哪台设备、Dify 打在哪个地址、Key 从哪读。

这批脚本原来把 DevEco 的安装路径、127.0.0.1:5555、.tmp/app_key.txt 都写死在文件里，
换一台电脑（队友、组委会、决赛评委）就是第一遍跑不起来的原因，所以统一收在这里，
按 **环境变量 > 自动探测 > 明确报错（直接告诉你该设哪个变量）** 的顺序取值。

支持的环境变量：
  HH_HDC        hdc.exe（或 hdc）的完整路径
  HH_DEVICE     hdc -t 用的设备号；不设就取 `hdc list targets` 的第一行
  HH_DIFY_BASE  从宿主机直连本机 Dify 的地址，默认 http://127.0.0.1/v1
                （模拟器里请填 http://10.0.2.2/v1，那是给 App 用的，别混）
  HH_APP_KEY    Dify 的 App Key，优先级最高
  HH_KEY_FILE   存 Key 的文本文件，默认 <项目根>/.tmp/app_key.txt
  HH_ZHIPU_KEY  直连智谱那几个脚本用的 Key
  HH_ZHIPU_FILE 存智谱 Key 的文本文件，默认 <项目根>/.tmp/zhipu_key.txt

Key 一律不打印、不落盘到仓库：只报长度和前缀，需要值的时候现取现用。
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

_HDC_CANDIDATES = [
    r"C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe",
    r"C:/Program Files/Huawei/DevEco Studio/sdk/openharmony/toolchains/hdc.exe",
    r"C:/Program Files/Huawei/OpenHarmony/sdk/toolchains/hdc.exe",
]

_hdc_cache = None
_dev_cache = None

class EnvError(Exception):
    pass

def _msg(what, how):
    return ("认不出这台机器上的 %s。请设环境变量 %s，例如：\n  set %s=%s"
            % (what, how[0], how[0], how[1]))

def hdc():
    """hdc 可执行文件路径：环境变量 > PATH > 常见安装目录 > 报错。"""
    global _hdc_cache
    if _hdc_cache:
        return _hdc_cache
    env = os.environ.get("HH_HDC")
    if env and os.path.exists(env):
        _hdc_cache = env
        return env
    which = shutil.which("hdc")
    if which:
        _hdc_cache = which
        return which
    for p in _HDC_CANDIDATES:
        if os.path.exists(p):
            _hdc_cache = p
            return p
    roots = [r"C:/Program Files/Huawei",
             os.path.join(os.path.expanduser("~"), "AppData", "Local", "Huawei"),
             os.path.join(os.path.expanduser("~"), "AppData", "Local", "OpenHarmony")]
    for r in roots:
        if not os.path.isdir(r):
            continue
        for dirpath, dirnames, filenames in os.walk(r):
            if dirpath.count(os.sep) - r.count(os.sep) > 5:
                del dirnames[:]
                continue
            if "hdc.exe" in filenames or "hdc" in filenames:
                _hdc_cache = os.path.join(dirpath, "hdc.exe" if os.name == "nt" else "hdc")
                return _hdc_cache
    raise EnvError(_msg("hdc", ("HH_HDC", r"C:/Program Files/Huawei/DevEco Studio/sdk/"
                               "default/openharmony/toolchains/hdc.exe")))

def device():
    """设备号：环境变量 > hdc list targets 的第一行 > 模拟器默认值。

    刚开完模拟器的头一两分钟，hdc server 常常卡住（`list targets` 直接不返回，
    `hdc kill` 之后才好）。探测失败不该把脚本拖死，所以这里超时就用默认值，
    真连不上时后面每条 shell 命令自己会报出来。
    """
    global _dev_cache
    if _dev_cache:
        return _dev_cache
    env = os.environ.get("HH_DEVICE")
    if env:
        _dev_cache = env
        return env
    try:
        out = _run([hdc(), "list", "targets"], timeout=15)
    except Exception:
        out = ""
        sys.stderr.write("hdc list targets 没回话（server 卡住？）；试 `hdc kill`，现在按默认设备走。\n")
    for line in out.splitlines():
        line = line.strip()
        if line and "[empty]" not in line.lower():
            _dev_cache = line
            return _dev_cache
    _dev_cache = "127.0.0.1:5555"
    if "[empty]" in out.lower():
        sys.stderr.write("没探到设备，先用 hdc list targets 看看；现在按 127.0.0.1:5555 试。\n")
    return _dev_cache

def shell(args, timeout=60):
    """在设备上跑一条 shell 命令，返回 stdout+stderr。"""
    r = subprocess.run([hdc(), "-t", device(), "shell", args],
                       capture_output=True, text=True, encoding="utf-8", errors="replace",
                       timeout=timeout)
    return (r.stdout or "") + (r.stderr or "")

def base():
    """宿主机直连本机 Dify 的地址（脚本侧用，不是 App 设置页里那个）。"""
    return os.environ.get("HH_DIFY_BASE", "http://127.0.0.1/v1").rstrip("/")

def _read_key(env, file_env, default_file):
    v = os.environ.get(env)
    if v:
        return v.strip()
    path = os.environ.get(file_env, os.path.join(ROOT, default_file))
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            s = f.read().strip()
        if s:
            return s
    return None

def app_key():
    """Dify 的 App Key。取不到就报清楚从哪能给，绝不猜、绝不打印。"""
    k = _read_key("HH_APP_KEY", "HH_KEY_FILE", ".tmp/app_key.txt")
    if k:
        return k
    from_docker = _key_from_docker()
    if from_docker:
        return from_docker
    raise EnvError(
        "没有 Dify 的 App Key。三种给法任选：\n"
        "  1) set HH_APP_KEY=app-xxxx（只在当前命令行有效，别写进任何文件）\n"
        "  2) 把 Key 写到 %s（这个文件已被 .gitignore 挡着，不会进提交包）\n"
        "  3) 本机 Docker 里跑着 Dify 时自动从 postgres 取，见 dify/README.md 的取 Key 一节"
        % os.path.join(ROOT, ".tmp", "app_key.txt"))

def _key_from_docker():
    """本机 Dify 容器在跑的话，从它的库里取唯一那个 app token（只取，不打印）。"""
    if not shutil.which("docker"):
        return None
    sql = ("select t.token from api_tokens t join apps a on a.id = t.app_id "
           "where a.name like '%河小导%' limit 1")
    for cname in ("docker-db_postgres-1", "dify-db-1", "docker-postgres-1"):
        try:
            r = subprocess.run(["docker", "exec", cname, "psql", "-U", "postgres", "-d", "dify",
                                "-t", "-A", "-c", sql],
                               capture_output=True, text=True, timeout=20)
        except Exception:
            continue
        for line in (r.stdout or "").splitlines():
            line = line.strip()
            if line.startswith("app-"):
                return line
    try:
        r = subprocess.run(["docker", "exec", "docker-db_postgres-1", "psql", "-U", "postgres",
                            "-d", "dify", "-t", "-A", "-c", "select token from api_tokens"],
                           capture_output=True, text=True, timeout=20)
    except Exception:
        return None
    vals = [x.strip() for x in (r.stdout or "").splitlines() if x.strip().startswith("app-")]
    return vals[0] if len(vals) == 1 else None

def zhipu_key():
    """直连智谱那几个脚本的 Key；和 Dify 的 Key 是两把，各读各的，不会互相顶替。"""
    k = _read_key("HH_ZHIPU_KEY", "HH_ZHIPU_FILE", ".tmp/zhipu_key.txt")
    if k:
        return k
    raise EnvError(
        "没有智谱的 Key。set HH_ZHIPU_KEY=... 或写到 %s。"
        % os.path.join(ROOT, ".tmp", "zhipu_key.txt"))

def brief(v):
    """给日志用的一行：只有长度和前缀，没有任何 Key 内容。"""
    if not v:
        return "空"
    return "长度 %d，前缀 %s" % (len(v), v[:4])

def _run(cmd, timeout=30):
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=timeout)
    return (r.stdout or "") + (r.stderr or "")

def selftest():
    """python tools/hh_env.py —— 把这台机器上探到的东西打一遍，不含任何 Key 内容。"""
    sys.stdout.reconfigure(encoding="utf-8")
    print("项目根：", ROOT)
    try:
        print("hdc：", hdc())
    except EnvError as e:
        print("hdc：", e)
    try:
        print("设备：", device())
    except Exception as e:
        print("设备：", e)
    print("Dify 宿主地址：", base())
    try:
        print("App Key：", brief(app_key()))
    except EnvError as e:
        print("App Key：", "没有（下面是怎么给）")
        print(e)
    try:
        print("智谱 Key：", brief(zhipu_key()))
    except EnvError:
        print("智谱 Key：没有（只有直连智谱的两个脚本会用到）")

if __name__ == "__main__":
    selftest()
