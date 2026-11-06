"""直连智谱验证 glm-4.7-flash：thinking 关掉之后是否还漏推理文本、首字延迟多少。
只读探测，不改任何配置。Key 走 hh_env（HH_ZHIPU_KEY > .tmp/zhipu_key.txt），不打印。
"""
import io, json, re, sys, time, urllib.request

import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hh_env

sys.stdout.reconfigure(encoding='utf-8')
KEY = hh_env.zhipu_key()
URL = 'https://open.bigmodel.cn/api/paas/v4/chat/completions'

CASES = [
    ('缺口-遗址', '庙底沟遗址有什么值得看的，我想给孩子讲彩陶'),
    ('缺口-课程', '有没有适合小学生的沿河课程'),
    ('命中-遗址', '仰韶村遗址在哪里，有什么值得看的'),
    ('命中-文创', '黄河沿岸有哪些文创产品'),
]

def ask(model, q, extra):
    body = {'model': model, 'messages': [{'role': 'user', 'content': q}], 'stream': True}
    body.update(extra)
    req = urllib.request.Request(URL, data=json.dumps(body).encode('utf-8'), headers={
        'Authorization': 'Bearer ' + KEY, 'Content-Type': 'application/json',
        'Accept': 'text/event-stream'})
    t0 = time.time()
    ttft = None
    content = []
    reason = []
    err = None
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            for raw in r:
                line = raw.decode('utf-8', 'replace').strip()
                if not line.startswith('data:'):
                    continue
                payload = line[5:].strip()
                if payload == '[DONE]':
                    break
                try:
                    ev = json.loads(payload)
                except Exception:
                    continue
                if 'error' in ev or (ev.get('code') not in (None, 0) and ev.get('code')):
                    err = str(ev.get('code')) + ' ' + str(ev.get('message'))[:80]
                    break
                ch = (ev.get('choices') or [{}])[0]
                d = ch.get('delta') or {}
                c = d.get('content') or ''
                rc = d.get('reasoning_content') or ''
                if rc:
                    reason.append(rc)
                if c:
                    if ttft is None:
                        ttft = time.time() - t0
                    content.append(c)
    except urllib.error.HTTPError as e:
        err = 'HTTP %s %s' % (e.code, e.read().decode('utf-8', 'replace')[:160])
    except Exception as e:
        err = type(e).__name__ + ' ' + str(e)[:120]
    return ''.join(content), ''.join(reason), ttft, time.time() - t0, err

def ascii_lines(text):
    out = []
    for ln in text.split('\n'):
        s = ln.strip()
        if len(s) < 6:
            continue
        chars = [c for c in s if not c.isspace()]
        if len([c for c in chars if ord(c) < 128]) / max(1, len(chars)) > 0.7:
            out.append(s)
    return out

for model, extra in [('glm-4.7-flash', {'thinking': {'type': 'disabled'}}),
                     ('glm-4.7-flash', {'thinking': {'type': 'enabled'}})]:
    print('########', model, extra)
    for name, q in CASES:
        c, r, ttft, tot, err = ask(model, q, extra)
        tag = len(re.findall(r'<.?think', c, re.I))
        print('  %-10s err=%-40s ttft=%-6s total=%-6s content=%-5d reasoning=%-5d think_tags=%d ascii_lines=%d' % (
            name, err, ('%.2f' % ttft) if ttft else '-', '%.2f' % tot, len(c), len(r), tag, len(ascii_lines(c))))
        for s in ascii_lines(c)[:2]:
            print('      LEAK? ' + s[:120])
        print('      head: ' + repr(c[:110]))
