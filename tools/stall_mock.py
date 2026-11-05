# -*- coding: utf-8 -*-
"""假 Dify：只用来把「首字前静默多少秒」变成一个可控量。

看门狗改的是时间阈值，光靠真机冷启动没法稳定复现某个静默时长，
所以这里起一个最小的 SSE 服务：地址填 http://<host>:<port>/v1，
App 就会把它当成 Dify 用。用法：

    python tools/stall_mock.py 8899 0       # 不静默，接成真后端用（评委现场演示走这档）
    python tools/stall_mock.py 8899 30      # 静默 30s 后才吐第一个字

GET /v1/parameters 也答（带 Bearer 就回 200，不带回 401，别的路径 404），
所以设置页的「测一下」在这套假后端上能变绿；缺这一段它就永远报接口不对。

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
    def do_GET(self):
        # App 设置页的「测一下」打的是 GET /v1/parameters，只认状态码不解析正文
        # （见 AiService.probe()）。没有这段，评委拿假 Dify 演界面时那一行永远是红的。
        p = self.path.split("?")[0].rstrip("/")
        if not p.endswith("/parameters"):
            self.send_response(404)
            self.end_headers()
            return
        if not (self.headers.get("Authorization") or "").startswith("Bearer "):
            self.send_response(401)
            self.end_headers()
            return
        body = json.dumps({
            "result": "success",
            "model_mode": "chat",
            "opening_statement": "这是假 Dify，只用来把界面跑通。",
            "suggested_questions": ["仰韶村遗址在哪里"],
            "data": {"voice": {}, "file_upload": {}},
        }, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        # 中文 Windows 的 cmd 里 curl 发的是 GBK 字节，这里严格 utf-8 解码会整条请求崩掉。
        # query 只用来打日志，解码不了就让它乱着，别把服务拖死。
        raw = self.rfile.read(n).decode("utf-8", "replace")
        try:
            body = json.loads(raw or "{}")
        except ValueError:
            body = {}
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
