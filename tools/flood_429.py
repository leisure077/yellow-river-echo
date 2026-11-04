"""制造限流：并发打若干请求把智谱侧打到 1305/429，用来验证 App 的错误兜底。
只发请求，不改任何配置；Ctrl-C 或到点自动停。
"""
import io, json, sys, threading, time, urllib.request

import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hh_env  # 地址/Key 都按 环境变量 > 自动探测 > 明确报错 取，不在脚本里写死

sys.stdout.reconfigure(encoding='utf-8')
KEY = hh_env.app_key()
BASE = hh_env.base()
DUR = float(sys.argv[1]) if len(sys.argv) > 1 else 40
N = int(sys.argv[2]) if len(sys.argv) > 2 else 6

stop = time.time() + DUR
lock = threading.Lock()
seen = {'429': 0, 'ok': 0, 'other': 0}


def fire(i):
    while time.time() < stop:
        body = json.dumps({'inputs': {}, 'query': '第%d次压力请求 %d' % (i, time.time()),
                           'response_mode': 'blocking', 'user': 'flood-%d' % i}).encode()
        req = urllib.request.Request(BASE + '/chat-messages', data=body, headers={
            'Authorization': 'Bearer ' + KEY, 'Content-Type': 'application/json'})
        try:
            urllib.request.urlopen(req, timeout=90).read()
            k = 'ok'
        except urllib.error.HTTPError as e:
            txt = e.read().decode('utf-8', 'replace')
            k = '429' if ('1305' in txt or '429' in txt) else 'other'
            with lock:
                if seen['429'] == 0 and k == '429':
                    print('SAMPLE-ERR ' + txt[:300], flush=True)
        except Exception:
            k = 'other'
        with lock:
            seen[k] += 1


ts = [threading.Thread(target=fire, args=(i,), daemon=True) for i in range(N)]
for t in ts:
    t.start()
for t in ts:
    t.join()
print('flood done:', json.dumps(seen), flush=True)
