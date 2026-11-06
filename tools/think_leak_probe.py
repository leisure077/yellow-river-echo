import json, re, sys, urllib.request

import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hh_env

sys.stdout.reconfigure(encoding='utf-8')

BASE = hh_env.base()
KEY = hh_env.app_key()

CASES = [
    ('庙底沟', '庙底沟遗址有什么值得看的，我想给孩子讲彩陶'),
    ('丝巾纹样', '庙底沟的彩陶纹样做成丝巾了吗，多少钱'),
    ('路线', '带老人走三门峡段，两天的路线怎么排'),
    ('课程', '有没有适合小学生的沿河课程'),
    ('隐私', '你们会不会把我收藏的记录传给别人'),
    ('编造', '黄河花园口大铁桥是谁设计的'),
]

for name, q in CASES:
    body = json.dumps({
        'inputs': {},
        'query': q,
        'response_mode': 'streaming',
        'conversation_id': '',
        'user': 'think-probe',
    }).encode('utf-8')
    req = urllib.request.Request(BASE + '/chat-messages', data=body, headers={
        'Authorization': 'Bearer ' + KEY,
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
    })
    answer = []
    think_field = []
    with urllib.request.urlopen(req, timeout=120) as r:
        for raw in r:
            line = raw.decode('utf-8', 'replace').strip()
            if not line.startswith('data:'):
                continue
            try:
                ev = json.loads(line[5:].strip())
            except Exception:
                continue
            if ev.get('event') == 'message':
                answer.append(ev.get('answer') or '')
                for k in ('reasoning_content', 'thinking'):
                    v = ev.get(k)
                    if v:
                        think_field.append((k, len(v)))
            elif ev.get('event') == 'message_end':
                pass
    text = ''.join(answer)
    tagged = len(re.findall(r'<.?think', text, re.I))
    closed = len(re.findall(r'</think', text, re.I))
    suspects = []
    for ln in text.split('\n'):
        s = ln.strip()
        if len(s) < 6:
            continue
        chars = [c for c in s if not c.isspace()]
        ascii_n = len([c for c in chars if ord(c) < 128])
        if ascii_n / max(1, len(chars)) > 0.7:
            suspects.append(s)
    print('==== %s  len=%d  <think=%d   /think=%d  ascii_lines=%d  separate_field=%s' % (
        name, len(text), tagged, closed, len(suspects), think_field[:3]))
    for s in suspects:
        print('   LEAK? ' + s[:160])
    print(repr(text[:200]))
    print('')
