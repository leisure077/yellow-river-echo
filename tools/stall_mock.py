# -*- coding: utf-8 -*-
"""假 Dify：只用来把「首字前静默多少秒」变成一个可控量。

看门狗改的是时间阈值，光靠真机冷启动没法稳定复现某个静默时长，
所以这里起一个最小的 SSE 服务：地址填 http://<host>:<port>/v1，
App 就会把它当成 Dify 用。用法：

    python tools/stall_mock.py 8899 30      # 静默 30s 后才吐第一个字

配套断言（都打在 App 界面上）：
  - 静默 30s：旧阈值 25s 会判超时，新阈值 60s 应该正常出完整回答；
  - 静默 70s：超过新阈值，应该出 AssistantCopy 里那句「档案翻得有点久」。
"""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8899
STALL = float(sys.argv[2]) if len(sys.argv) > 2 else 30.0


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n).decode("utf-8") or "{}")
        q = (body.get("query") or "")[:20]
        print("%s <- %s（静默 %.0fs）" % (self.path, q, STALL), flush=True)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        def send(obj):
            self.wfile.write(("data: %s\n\n" % json.dumps(obj, ensure_ascii=False)).encode())
            self.wfile.flush()

        time.sleep(STALL)
        for piece in ["模拟回答：", "这段是静默 ", "%.0f" % STALL, " 秒之后才开始吐的字，", "用来验看门狗阈值。"]:
            send({"event": "message", "answer": piece, "created_at": int(time.time()),
                  "conversation_id": "mock-conv", "message_id": "mock-msg"})
            time.sleep(0.2)
        send({"event": "message_end", "conversation_id": "mock-conv", "message_id": "mock-msg",
              "metadata": {"retriever_resources": []}})

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    print("mock listening on 0.0.0.0:%d, stall=%.0fs" % (PORT, STALL), flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
