"""本地假 Dify：只用来触发 App 的限流分支，看错误卡片长什么样。
默认 429：HTTP 429 + Dify 风格 JSON（走 errorOf 分支）。
--sse：HTTP 200 + SSE error 事件，message 里塞智谱 1305 的英文原文（走 consume 分支）。
跑完就停，不改任何配置。
"""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

ZHIPU_1305 = ('Error code: 429 - {\'error\': {\'message\': \'The server had an issue with your '
              'request. 该模型当前访问量过大，请您稍后再试 (error code: 1305)\', '
              '\'type\': \'rate_limit_error\'}}')

BODY_429 = json.dumps({
    'code': 'too_many_requests',
    'message': 'Too many requests. Please try again later.',
    'status': 429,
}).encode('utf-8')

SSE_ERR = ('data: ' + json.dumps({
    'event': 'error',
    'code': 'invalid_param',
    'message': ZHIPU_1305,
    'status': 400,
}, ensure_ascii=False) + '\n\n').encode('utf-8')

SSE_MODE = '--sse' in sys.argv
PORT = int(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith('--') else 8899

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length') or 0)
        self.rfile.read(n)
        if SSE_MODE:
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Content-Length', str(len(SSE_ERR)))
            self.end_headers()
            self.wfile.write(SSE_ERR)
            self.wfile.flush()
            print('SSE error(1305) ->', self.path, flush=True)
        else:
            self.send_response(429)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(BODY_429)))
            self.end_headers()
            self.wfile.write(BODY_429)
            print('429 ->', self.path, flush=True)

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def log_message(self, *a):
        pass

print('mock dify on', PORT, 'mode', 'sse-1305' if SSE_MODE else 'http-429', flush=True)
HTTPServer(('0.0.0.0', PORT), H).serve_forever()
