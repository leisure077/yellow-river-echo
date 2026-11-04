# -*- coding: utf-8 -*-
"""把提交源码包导出这一步变成"能跑的检查"，而不是"我看过目录，挺干净的"。

用法：
    python tools/export_package.py                 # 从 HEAD 导出并验五项
    python tools/export_package.py --ref <sha|tag>  # 指定要交的那个提交
    python tools/export_package.py --verify         # 再加第六项：解压重编一遍（要 DevEco，约 20s）
    python tools/export_package.py --check <path.zip>  # 只验已有的包，不重新导

为什么用 git archive 而不是复制目录：工作树里常年放着 build/、oh_modules/、.hvigor、
截图、hilog、.tmp/ 里的本地 Key，还有 DevEco 随时可能写进 build-profile.json5 的签名材料。
git archive 只按 git 索引出内容，这些天然进不去。
代价是**未提交的改动也不会进包**，所以脚本第一件事就是把 HEAD 和工作树状态报清楚，
让人确认"要交的就是这个提交"。

五组断言，对应赛题那句"清理编译生成文件、缓存文件，保证组委会可复现项目编译运行"：
  1 产物与缓存    —— 一个都不该在
  2 凭据与本机路径  —— Key、证书、口令字段、本机用户目录下的绝对路径都不该在
  3 签名配置      —— build-profile.json5 的 signingConfigs 必须是空数组，
                    否则评委拿到包第一步就 build 失败（证书在他们机器上不存在）
  4 复现必需文件  —— 少任何一个都编不起来
  5 体积          —— 只报数，不判分（组委会没给上限时，这个数字用来自己拍板）
  6 复现构建（--verify）—— 把包解压到干净目录，只按 README 那条命令重新编一遍，再验产物
                    hap 里带着本轮新增的那几句。前五条只证明"包里没脏东西"，
                    这一条才证明"它能编，而且编出来的就是包里这份代码"。
"""
import io
import os
import re
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, ".tmp", "pkg")

# 1) 产物与缓存：命中即为不干净
JUNK = [
    (r"(^|/)build/", "编译产物 build/"),
    (r"(^|/)oh_modules/", "依赖缓存 oh_modules/"),
    (r"(^|/)node_modules/", "依赖缓存 node_modules/"),
    (r"(^|/)\.hvigor", "构建缓存 .hvigor"),
    (r"(^|/)\.preview", "预览产物 .preview"),
    (r"(^|/)__pycache__/", "Python 字节码 __pycache__/"),
    (r"\.pyc$", "Python 字节码 .pyc"),
    (r"\.hap$", "打包件 .hap"),
    (r"\.hsp$", "打包件 .hsp"),
    (r"\.log$", "日志 .log"),
    (r"(^|/)shots/", "自验截图 shots/"),
    (r"(^|/)\.tmp/", "本机中间产物 .tmp/"),
    (r"(^|/)\.idea/", "IDE 工程 .idea/"),
    (r"(^|/)\.gradle/", "构建缓存 .gradle/"),
    (r"local\.properties$", "本机路径 local.properties"),
    (r"\.DS_Store$", "系统残留"),
    (r"(^|/)dist/", "前端产物 dist/"),
]

# 2) 凭据与本机痕迹：对每个文件的文本内容做匹配（二进制按字节读，跳过）。
# 每条可以带第三个参数限定后缀：签名口令字段只在意配置文件——它是"评委机器上没有证书
# 文件、构建直接失败"的信号，文档里提这个名字不算泄漏（README 就在描述这条规则本身）。
LEAKS = [
    (rb"app-[A-Za-z0-9_-]{16,}", "Dify App Key 原文", None),
    (rb"sk-[A-Za-z0-9_-]{16,}", "智谱/OpenAI 风格 Key 原文", None),
    (rb"LTAI[A-Za-z0-9]{8,}", "阿里云 AccessKey", None),
    (rb"-----BEGIN [A-Z ]*PRIVATE KEY-----", "私钥", None),
    (rb"key[Pp]assword", "签名密钥口令字段", (".json5", ".json")),
    (rb"store[Pp]assword", "签名库口令字段", (".json5", ".json")),
    (rb"\.ohos[/\\]config", "本机签名证书目录", None),
    (rb"[A-Za-z]:[/\\]Users[/\\]", "本机绝对路径（写死到别人机器上就断了）", None),
]

# 跳过内容扫描的二进制目录/后缀：图片、模型、字体这些不参与凭据判断
SKIP_EXT = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".glb", ".gltf", ".bin",
            ".ttf", ".woff", ".woff2", ".mp4", ".mov", ".wav", ".mp3", ".svgz",
            ".ico", ".zip", ".pak")

# 4) 复现必需文件：少了就编不起来
REQUIRED = [
    "build-profile.json5",
    "oh-package.json5",
    "oh-package-lock.json5",
    "hvigorfile.ts",
    "AppScope/app.json5",
    "entry/build-profile.json5",
    "entry/oh-package.json5",
    "entry/src/main/module.json5",
    "entry/src/main/resources/base/element/string.json",
    "README.md",
    "dify/README.md",
    "tools/hh_env.py",
    "tools/export_package.py",
]


def git(*args):
    r = subprocess.run(["git"] + list(args), cwd=ROOT, capture_output=True,
                       text=True, encoding="utf-8", errors="replace")
    return (r.stdout or "") + (r.stderr or "")


def norm(name):
    """git archive 写中文文件名时可能不带 UTF-8 标记，zipfile 会按 cp437 解，这里翻回来。"""
    if any(ord(c) > 127 for c in name):
        try:
            return name.encode("cp437").decode("utf-8")
        except Exception:
            return name
    return name.replace("\\", "/")


def head():
    return git("rev-parse", "--short", "HEAD").strip()


def dirty_report():
    """工作树里那些没进包的东西，必须让人看见——尤其是 IDE 偷偷写的签名配置。"""
    out = []
    tracked = [ln for ln in git("status", "--short", "--untracked-files=no").splitlines() if ln.strip()]
    if tracked:
        out.append("已跟踪但未提交的改动（不会进包）：")
        out += ["  " + ln for ln in tracked]
        if any("build-profile.json5" in ln for ln in tracked):
            out.append("  ⚠ build-profile.json5 有本地改动。DevEco 常往里写 signingConfigs"
                       "（本机证书路径 + 口令）。包里是 HEAD 的版本，请确认 HEAD 那份是 "
                       '"signingConfigs": []。')
    else:
        out.append("工作树的已跟踪文件与 HEAD 一致。")
    untracked = [ln for ln in git("ls-files", "--others", "--exclude-standard").splitlines() if ln.strip()]
    if untracked:
        names = [ln.split("/", 1)[0] if not ln.startswith("/") else ln for ln in untracked]
        top = sorted(set(names))
        out.append("未跟踪文件 %d 个（不进包，正常）：顶层在 %s" % (len(untracked), "、".join(top[:12])))
    return "\n".join(out)


def export(ref):
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)
    short = ref[:7]
    path = os.path.join(OUT_DIR, "yellow-river-echo-src-%s.zip" % short)
    if os.path.exists(path):
        os.remove(path)
    r = subprocess.run(["git", "archive", "--format=zip", "-o", path, ref],
                       cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    err = (r.stdout or "") + (r.stderr or "")
    if not os.path.exists(path):
        raise SystemExit("git archive 失败：" + err.strip())
    return path


def check(path, ref):
    z = zipfile.ZipFile(path)
    names = [norm(n) for n in z.namelist()]
    # git archive 带路径前缀时（--prefix）统一去掉，便于比对
    files = [n for n in names if not n.endswith("/")]
    fails, notes = [], []

    def section(t):
        notes.append("\n== %s ==" % t)

    # --- 0 包身份 ---
    section("包")
    notes.append("文件 %d 个；zip %s；来源提交 %s"
                 % (len(files), _hsize(os.path.getsize(path)), ref[:7]))
    if len(files) == 0:
        fails.append("包是空的")

    # --- 1 产物与缓存 ---
    section("1 产物与缓存")
    hit = {}
    for n in files:
        for pat, label in JUNK:
            if re.search(pat, n):
                hit.setdefault(label, []).append(n)
    if hit:
        for label, ns in hit.items():
            fails.append("%s：%d 个，例如 %s" % (label, len(ns), ns[0]))
    else:
        notes.append("没命中任何产物/缓存规则（build、oh_modules、.hvigor、__pycache__、"
                     "*.hap、*.log、shots、.tmp、.idea、local.properties 全查过）")

    # --- 2 凭据与本机痕迹 ---
    section("2 凭据与本机路径")
    leaks = []
    for n in files:
        if n.lower().endswith(SKIP_EXT):
            continue
        data = z.read(n)
        for pat, label, only in LEAKS:
            if only and not n.lower().endswith(only):
                continue
            m = re.search(pat, data)
            if m:
                leaks.append((label, n, m.group(0)[:12]))
    if leaks:
        for label, n, sample in leaks:
            fails.append("%s —— %s（片段 %s…，值不打印）" % (label, n, sample))
    else:
        notes.append("文本文件里没匹配到 Key / 私钥 / 口令字段 / 证书目录 / 本机绝对路径")

    # --- 3 签名配置 ---
    # 只有根 build-profile.json5 有 signingConfigs；entry/ 那份是模块配置，本来就没这个字段。
    section("3 签名配置")
    target = [n for n in files if n.endswith("build-profile.json5")]
    if not target:
        fails.append("包里找不到 build-profile.json5")
    for n in target:
        body = z.read(n).decode("utf-8", "replace")
        m = re.search(r'"signingConfigs"\s*:\s*(\[[^\]]*\])', body, re.S)
        if not m:
            if n == "build-profile.json5":
                fails.append("%s 里没有 signingConfigs 字段，无法确认是否干净" % n)
            else:
                notes.append("%s：模块级配置，不含签名段 ✓" % n)
        elif re.sub(r"\s", "", m.group(1)) != "[]":
            fails.append("%s 的 signingConfigs 非空 —— 里面是这台机器的证书与口令，"
                         "评委机器上没有这些文件，构建会直接失败。包里必须是 []" % n)
        else:
            notes.append("%s：signingConfigs 为空数组 ✓" % n)

    # --- 4 复现必需文件 ---
    section("4 复现必需文件")
    missing = [r for r in REQUIRED if r not in files]
    if missing:
        fails.append("缺少 %s" % "、".join(missing))
    else:
        notes.append("%d 项都在（含 README、dify/README、tools/hh_env.py）" % len(REQUIRED))

    # --- 5 体积 ---
    section("5 体积")
    total = sum(z.getinfo(n).file_size for n in files)
    big = sorted(files, key=lambda n: -z.getinfo(n).file_size)[:8]
    notes.append("解压后 %s；最大 8 项：" % _hsize(total))
    for n in big:
        notes.append("   %8s  %s" % (_hsize(z.getinfo(n).file_size), n))

    return fails, notes, files, total


def _hsize(b):
    if b > 1024 * 1024:
        return "%.1f MB" % (b / 1048576.0)
    if b > 1024:
        return "%.1f KB" % (b / 1024.0)
    return "%d B" % b


# 产物里必须有这几句：本轮改的排错入口确实被打进了 hap，而不是只改了源码
SENTINELS = ["测一下", "最近一次失败", "HH_AI"]
BUILD_DIR = os.path.join(OUT_DIR, "buildcheck")


def deveco_root():
    """从 hdc 的路径倒推 DevEco Studio 安装目录。

    正常安装下 hdc 落在 <DevEco>/sdk/default/openharmony/toolchains/hdc.exe，
    往上五层就是安装根目录；不在这里写死盘符，换机器跟着 HH_HDC 走。
    """
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import hh_env
        p = hh_env.hdc()
    except Exception as e:
        raise SystemExit("认不出这台机器的 DevEco/hdc，没法做复现构建。%s" % e)
    d = os.path.normpath(p)
    for _ in range(5):
        d = os.path.dirname(d)
    return d


def verify(path):
    """把包解压到一个干净目录，只按 README §2 那条命令重新构建。

    这一步才是"组委会可复现项目编译运行"的正面证据：前面五项断言只证明包里
    没有脏东西，证明不了它能编。构建日志原样留着，失败时看最后二十行。
    """
    print("\n== 6 复现构建：解压后直接编 ==")
    import shutil
    if os.path.isdir(BUILD_DIR):
        shutil.rmtree(BUILD_DIR, ignore_errors=True)
    os.makedirs(BUILD_DIR)
    zipfile.ZipFile(path).extractall(BUILD_DIR)
    n = sum(len(f) for _, _, f in os.walk(BUILD_DIR))
    print("已解压 %d 个文件到 %s" % (n, BUILD_DIR))

    dev = deveco_root()
    node = os.path.join(dev, "tools", "node", "node.exe" if os.name == "nt" else "node")
    wjs = os.path.join(dev, "tools", "hvigor", "bin", "hvigorw.js")
    for p, what in ((node, "node"), (wjs, "hvigorw.js")):
        if not os.path.exists(p):
            raise SystemExit("DevEco 里找不到 %s（%s）；请确认 DevEco 根目录是 %s" % (what, p, dev))
    env = dict(os.environ, DEVECO_SDK_HOME=os.path.join(dev, "sdk"))
    r = subprocess.run([node, wjs, "--mode", "module", "-p", "product=default",
                        "-p", "buildMode=debug", "assembleHap"],
                       cwd=BUILD_DIR, env=env, capture_output=True,
                       text=True, encoding="utf-8", errors="replace", timeout=1800)
    log = (r.stdout or "") + (r.stderr or "")
    ok = "BUILD SUCCESSFUL" in log
    print("构建 %s" % ("成功" if ok else "失败"))
    for line in [ln for ln in log.splitlines() if "BUILD" in ln or "skip sign" in ln
                 or "ERROR" in ln][:6]:
        print("   " + line.strip())
    if not ok:
        print("\n".join(log.splitlines()[-20:]))
        return False

    haps = []
    for dirpath, _, filenames in os.walk(os.path.join(BUILD_DIR, "entry", "build")):
        haps += [os.path.join(dirpath, f) for f in filenames if f.endswith(".hap")]
    if not haps:
        print("✗ 构建说成功但找不到 .hap 产物")
        return False
    hap = max(haps, key=os.path.getsize)
    print("产物 %s（%s）" % (hap, _hsize(os.path.getsize(hap))))
    z = zipfile.ZipFile(hap)
    blob = b"".join(z.read(n) for n in z.namelist() if n.endswith(".abc"))
    miss = [s for s in SENTINELS if s.encode("utf-8") not in blob]
    for s in SENTINELS:
        print("   产物里含「%s」：%s" % (s, "否" if s in miss else "是"))
    if miss:
        print("✗ 这几句没进产物 —— 包里那份源码不是当前代码")
        return False
    print("复现构建通过：包解压 → 只按 README 的命令 → 出 hap → 新代码在产物里")
    return True


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    args = sys.argv[1:]
    ref = head()
    if "--ref" in args:
        ref = git("rev-parse", args[args.index("--ref") + 1]).strip()
    if "--check" in args:
        path = args[args.index("--check") + 1]
    else:
        print("当前 HEAD：%s" % ref)
        print(dirty_report())
        print("")
        path = export(ref)

    fails, notes, files, total = check(path, ref)
    for line in notes:
        print(line)
    print("\n包路径：%s" % path)
    if fails:
        print("\n不通过 %d 项：" % len(fails))
        for f in fails:
            print("  ✗ " + f)
        print("\n这个包别交。")
        return 1
    print("\n五项断言全过，这个包可以交。")
    if "--verify" in args:
        if not verify(path):
            print("\n断言过了但复现构建没过 —— 也别交。")
            return 1
    else:
        print("（还没做复现构建；加 --verify 让脚本解压本包并重新编一遍，"
              "那才是\"组委会可复现\"的正面证据）")
    print("提醒：包里是 %s 的内容，此后任何改动都要重新跑本脚本再导一次。" % ref[:7])
    return 0


if __name__ == "__main__":
    sys.exit(main())
