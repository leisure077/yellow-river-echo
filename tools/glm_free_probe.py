"""glm-4.7-flash 报 1305（访问量过大），带重试再判一次；同时对比几个免费/轻量模型。
只读探测。Key 从 .tmp/zhipu_key.txt 读。
"""
import io, json, re, sys, time, urllib.request

sys.stdout.reconfigure(encoding='utf-8')
KEY = io.open('.tmp/zhipu_key.txt', encoding='utf-8').read().strip()
URL = 'https://open.bigmodel.cn/api/paas/v4/chat/completions'

Q = '仰韶村遗址在哪里，有什么值得看的？三句话说清楚。'

CANDS = [
    ('glm-4.7-flash', {'thinking': {'type': 'disabled'}}),
    ('glm-4-flash', {}),
    ('glm-4.5-air', {'thinking': {'type': 'disabled'}}),
    ('glm-4.7-flashx', {'thinking': {'type': 'disabled'}}),
]

def one(model, extra, tries=3, gap=12):
    last = None
    for i in range(tries):
        body = {'model': model, 'messages': [{'role': 'user', 'content': Q}], 'stream': True, 'max_tokens': 400}
        body.update(extra)
        req = urllib.request.Request(URL, data=json.dumps(body).encode('utf-8'), headers={
            'Authorization': 'Bearer ' + KEY, 'Content-Type': 'application/json',
            'Accept': 'text/event-stream'})
        t0 = time.time()
        ttft = None
        parts = []
        err = None
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                for raw in r:
                    line = raw.decode('utf-8', 'replace').strip()
                    if not line.startswith('data:'):
                        continue
                    p = line[5:].strip()
                    if p == '[DONE]':
                        break
                    try:
                        ev = json.loads(p)
                    except Exception:
                        continue
                    if ev.get('code') not in (None, '', 0):
                        err = 'code %s %s' % (ev.get('code'), str(ev.get('message'))[:60])
                        break
                    d = ((ev.get('choices') or [{}])[0].get('delta') or {})
                    c = d.get('content') or ''
                    if c:
                        if ttft is None:
                            ttft = time.time() - t0
                        parts.append(c)
        except urllib.error.HTTPError as e:
            err = 'HTTP %s %s' % (e.code, e.read().decode('utf-8', 'replace')[:120])
        except Exception as e:
            err = type(e).__name__ + ' ' + str(e)[:100]
        text = ''.join(parts)
        if text:
            return err, ttft, time.time() - t0, text, i + 1
        last = err
        if '1305' not in str(err) and '429' not in str(err):
            return err, None, time.time() - t0, '', i + 1
        time.sleep(gap)
    return last, None, None, '', tries

for model, extra in CANDS:
    err, ttft, tot, text, n = one(model, extra)
    leak = len(re.findall(r'<.?think', text, re.I))
    print('%-14s attempts=%d ttft=%-6s total=%-6s len=%-5d think_tags=%d err=%s' % (
        model, n, ('%.2f' % ttft) if ttft else '-', ('%.2f' % tot) if tot else '-', len(text), leak, str(err)[:90]))
    if text:
        print('    ', repr(text[:150]))
