"""回归：切到 glm-4.7-flash + 提示词 V2 之后，跑 6 个问题查四件事。
首字延迟 / 有无英文泄漏 / 开头是否直接给结论 / 内部编号有没有念出来。
结果写 .tmp/regress_glm47.txt（含完整回答，方便看排版）。
"""
import io, json, re, sys, time, urllib.request

import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hh_env  # 地址/Key 都按 环境变量 > 自动探测 > 明确报错 取，不在脚本里写死

sys.stdout.reconfigure(encoding='utf-8')

BASE = hh_env.base()
KEY = hh_env.app_key()
OUT = '.tmp/regress_glm47.txt'

CASES = [
    ('缺口-遗址', '庙底沟遗址有什么值得看的，我想给孩子讲彩陶'),
    ('缺口-课程', '有没有适合小学生的沿河课程'),
    ('命中-遗址', '仰韶村遗址在哪里，有什么值得看的'),
    ('命中-文创', '黄河沿岸有哪些文创产品'),
    ('隐私', '你们会不会把我收藏的记录传给别人'),
    ('防编造', '黄河花园口大铁桥是谁设计的'),
]

SMALLTALK = ('您好', '你好', '我是河小导', '很高兴', '您好呀')


def ascii_heavy(s):
    chars = [c for c in s if not c.isspace()]
    if not chars:
        return False
    return len([c for c in chars if ord(c) < 128]) / len(chars) > 0.7


def run(q):
    body = json.dumps({'inputs': {}, 'query': q, 'response_mode': 'streaming',
                       'conversation_id': '', 'user': 'regress-glm47'}).encode('utf-8')
    req = urllib.request.Request(BASE + '/chat-messages', data=body, headers={
        'Authorization': 'Bearer ' + KEY, 'Content-Type': 'application/json',
        'Accept': 'text/event-stream'})
    t0 = time.time()
    ttft = None
    parts = []
    cites = []
    err = None
    with urllib.request.urlopen(req, timeout=180) as r:
        for raw in r:
            line = raw.decode('utf-8', 'replace').strip()
            if not line.startswith('data:'):
                continue
            try:
                ev = json.loads(line[5:].strip())
            except Exception:
                continue
            e = ev.get('event')
            if e == 'message':
                a = ev.get('answer') or ''
                if a:
                    if ttft is None:
                        ttft = time.time() - t0
                    parts.append(a)
            elif e == 'error':
                err = str(ev.get('code')) + ' ' + str(ev.get('message'))[:120]
            elif e == 'message_end':
                for m in (ev.get('metadata') or {}).get('retriever_resources', []) or []:
                    cites.append(m.get('document_name') or m.get('name') or '?')
    return ''.join(parts), ttft, time.time() - t0, cites, err


log = io.open(OUT, 'a', encoding='utf-8')
log.write('\n===== %s glm-4.7-flash + prompt V2 =====\n' % time.strftime('%H:%M:%S'))
rows = []
for name, q in CASES:
    text, ttft, tot, cites, err = run(q)
    leak = [l.strip() for l in text.split('\n') if len(l.strip()) >= 6 and ascii_heavy(l)]
    ids = re.findall(r'[seg][0-9]{2}\b', text)
    md = re.findall(r'\*\*|^#|\|---|```', text, re.M)
    first = text.strip().split('\n')[0][:16] if text.strip() else ''
    small = first.startswith(SMALLTALK)
    bullets = text.count('·')
    rows.append((name, ttft, tot, len(text), len(leak), len(ids), len(md), len(cites), small, err))
    log.write('---- %s | Q: %s\n' % (name, q))
    log.write('ttft=%s total=%.2f len=%d cites=%d 中文圆点=%d 开头寒暄=%s 编号=%s Markdown残留=%s 英文行=%d err=%s\n' % (
        ('%.2f' % ttft) if ttft else '-', tot, len(text), len(cites), bullets, small, ids, md, len(leak), err))
    log.write('ANSWER:\n' + text + '\n')
    print('%-9s ttft=%-6s total=%-6s len=%-5d leak=%d ids=%d md=%d cites=%d 寒暄开头=%-5s err=%s' % (
        name, ('%.2f' % ttft) if ttft else '-', '%.2f' % tot, len(text), len(leak), len(ids),
        len(md), len(cites), str(small), str(err)[:40]))
log.close()
