"""假 Dify：专门造一个「本机存着的会话号在服务端不存在」的场景，用来验会话自愈。

真实复现路径是今天演示时踩到的那一种：先用假服务问过一句，本地存下了 mock 的会话号，
换回真 Dify 之后每个问题都带着这个陌生号上去，服务端回 404 / Conversation Not Exists，
旧版本就一路报「档案室挡回来了」，只能靠人工点「清空对话」才能救回来。

用法：
    python tools/stale_conv_mock.py 8898
App 的地址填 http://10.0.2.2:8898/v1（模拟器里 10.0.2.2 才是本机）。

行为：
  - 请求里 conversation_id 非空  -> 404 + Dify 风格的 {"code":"not_chat_app_conversation", ...}
  - 请求里 conversation_id 为空  -> 正常 SSE 回答，并回一个新会话号
所以 App 第一次问会撞 404，自愈清号后第二次就该正常出答案；
界面上「不用点清空对话」就是这条改动的验收标准。
"""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8898

NOT_FOUND = json.dumps({
    "code": "not_chat_app_conversation",
    "message": "Conversation Not Exists.",
    "status": 404,
}).encode("utf-8")

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.endswith("/parameters"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"opening_statement":"mock","suggested_questions":[]}')
            return
        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(n).decode("utf-8") or "{}")
        except Exception:
            body = {}
        conv = (body.get("conversation_id") or "").strip()
        if conv:
            print("<- 带旧会话号 %s… -> 404 Conversation Not Exists" % conv[:8], flush=True)
            self.send_response(404)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(NOT_FOUND)))
            self.end_headers()
            self.wfile.write(NOT_FOUND)
            return
        print("<- 会话号为空 -> 正常 SSE 回答", flush=True)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        def send(obj):
            self.wfile.write(("data: %s\n\n" % json.dumps(obj, ensure_ascii=False)).encode())
            self.wfile.flush()

        cid = "healed-%d" % int(time.time())
        for piece in ["自愈之后这句是", "服务端新开的会话，", "说明旧会话号已经被清掉了。"]:
            send({"event": "message", "answer": piece, "created_at": int(time.time()),
                  "conversation_id": cid, "message_id": "m1"})
            time.sleep(0.15)
        send({"event": "message_end", "conversation_id": cid, "message_id": "m1",
              "metadata": {"retriever_resources": []}})

    def log_message(self, *a):
        pass

if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    print("stale-conv mock listening on 0.0.0.0:%d" % PORT, flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
