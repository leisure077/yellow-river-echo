"""量一下 Dify 侧流式问答的首字延迟 / 分片手感。
只读：向 /v1/chat-messages 发 streaming 请求，统计每个 event 的时间戳。
地址与凭证走 hh_env：HH_DIFY_BASE/HH_APP_KEY > .tmp/app_key.txt > 本机 Dify 库，绝不打印。
"""
import json
import ssl
import sys
import time
import urllib.request

import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hh_env

BASE = hh_env.base()
KEY = hh_env.app_key()

QUERIES = [
    ("遗址", "二里头遗址有什么值得看的？", ""),
    ("路线", "我想一天看完三门峡附近的遗址，怎么安排？", ""),
    ("隐私", "你看看我都收藏了哪些遗址？", ""),
    ("闲聊", "帮我写一个 Python 快排", ""),
    ("推理", "把仰韶、龙山、二里头按年代排个序，并说说各自最代表性的器物。", ""),
    ("计算", "37 个人分 128 件陶片，每人几件、余几件？", ""),
]

def run(tag, query, conv):
    body = {
        "inputs": {"personal_context": ""},
        "query": query,
        "response_mode": "streaming",
        "conversation_id": conv,
        "user": "latency-probe",
    }
    req = urllib.request.Request(
        BASE + "/chat-messages",
        data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": "Bearer " + KEY,
            "Content-Type": "application/json; charset=utf-8",
        },
    )
    t0 = time.time()
    ttft = None
    pieces = 0
    chars = 0
    gaps = []
    buf = ""
    answer = ""
    cites = []
    cid = ""
    last = t0
    with urllib.request.urlopen(req, timeout=180) as resp:
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            now = time.time()
            try:
                ev = json.loads(line[5:])
            except Exception:
                continue
            et = ev.get("event")
            if et == "message":
                d = ev.get("answer") or ""
                if ttft is None and len(d) > 0:
                    ttft = now - t0
                else:
                    gaps.append(now - last)
                last = now
                pieces += 1
                chars += len(d)
                answer += d
                cid = ev.get("conversation_id") or cid
            elif et == "message_end":
                cid = ev.get("conversation_id") or cid
                cites = (ev.get("metadata") or {}).get("retriever_resources") or []
            elif et in ("error", "invitation_code"):
                buf = json.dumps(ev, ensure_ascii=False)[:300]
    total = time.time() - t0
    med = sorted(gaps)[len(gaps) // 2] if gaps else 0.0
    p95 = gaps[int(len(gaps) * 0.95)] if len(gaps) > 3 else 0.0
    out = {
        "case": tag,
        "ttft_s": round(ttft or -1, 2),
        "total_s": round(total, 2),
        "pieces": pieces,
        "chars": chars,
        "med_gap_s": round(med, 3),
        "p95_gap_s": round(p95, 3),
        "citations": [c.get("document_name") for c in cites],
        "err": buf,
        "conversation_id": cid,
    }
    return out, answer

def main():
    log = open(".tmp/dify_latency.txt", "a", encoding="utf-8")
    for tag, q, conv in QUERIES:
        res, ans = run(tag, q, conv)
        print(json.dumps(res, ensure_ascii=False))
        log.write(json.dumps(res, ensure_ascii=False) + "\n")
        log.write("---- " + tag + " 回答 ----\n" + ans + "\n")
        sys.stdout.flush()
    log.close()

if __name__ == "__main__":
    main()
