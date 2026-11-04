"""直连智谱测首字延迟：对每个候选模型发一次流式请求，记录 TTFT / 总耗时 / 输出字数。
只读操作，不改任何配置。Key 走 hh_env（HH_ZHIPU_KEY > .tmp/zhipu_key.txt），不打印。
"""
import io
import json
import time
import urllib.request

import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hh_env  # 地址/Key 都按 环境变量 > 自动探测 > 明确报错 取，不在脚本里写死

KEY = hh_env.zhipu_key()
URL = 'https://open.bigmodel.cn/api/paas/v4/chat/completions'

SYSTEM = '你是「黄河续响」平台的文化向导「河小导」，用中文口语回答，简短准确。'
CONTEXT = (
    '参考资料：仰韶文化距今约7000-5000年，以彩陶著称，典型器物为小口尖底瓶、'
    '鱼纹彩陶盆，分布于黄河中游。二里头遗址位于河南偃师，被认为是夏代晚期都城，'
    '出土青铜爵、绿松石龙形器。'
)
Q = '仰韶彩陶有什么特点？两句话说清楚。'

MODELS = ['glm-5.3-flash', 'glm-5.3-flashx', 'glm-4.5-air', 'glm-4.7']


def probe(model):
    body = {
        'model': model,
        'messages': [
            {'role': 'system', 'content': SYSTEM},
            {'role': 'user', 'content': CONTEXT + '\n\n' + Q},
        ],
        'stream': True,
        'temperature': 0.7,
        'max_tokens': 200,
    }
    req = urllib.request.Request(
        URL,
        data=json.dumps(body).encode('utf-8'),
        headers={
            'Authorization': 'Bearer ' + KEY,
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
        },
    )
    t0 = time.time()
    ttft = None
    chunks = 0
    text = []
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            for raw in resp:
                line = raw.decode('utf-8', 'ignore').strip()
                if not line.startswith('data:'):
                    continue
                payload = line[5:].strip()
                if payload == '[DONE]':
                    break
                try:
                    ev = json.loads(payload)
                except Exception:
                    continue
                d = (ev.get('choices') or [{}])[0]
                piece = (d.get('delta') or {}).get('content') or ''
                if piece:
                    if ttft is None:
                        ttft = time.time() - t0
                    chunks += 1
                    text.append(piece)
    except Exception as e:
        return {'model': model, 'error': str(e)[:120]}
    return {
        'model': model,
        'ttft_s': round(ttft, 2) if ttft else None,
        'total_s': round(time.time() - t0, 2),
        'chars': len(''.join(text)),
        'pieces': chunks,
    }


if __name__ == '__main__':
    out = []
    for m in MODELS:
        r = probe(m)
        out.append(r)
        io.open('.tmp/zhipu_latency.txt', 'a', encoding='utf-8').write(
            json.dumps(r, ensure_ascii=False) + '\n'
        )
