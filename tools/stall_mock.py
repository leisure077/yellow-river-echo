"""假 Dify：换一台电脑也能把河小导的界面整条跑通，顺便备着六组演示问答。

App 只认两头发：GET /v1/parameters（设置页「测一下」）和 POST /v1/chat-messages
（流式问答）。这里两个都答，所以接上之后界面、引用位、看门狗照常工作。
答案是从 tools/kb/docs 的真实段落里写死的，不接知识库、不接模型——别当回答质量讲。

    python tools/stall_mock.py 8899 0       # 演示档：不静默，问那六组有内容
    python tools/stall_mock.py 8899 30      # 看门狗档：静默 30s 才吐第一个字

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

CANNED = [
    (("仰韶", "渑池", "彩陶文化"),
     "仰韶村遗址在三门峡渑池县，黄河南岸的台地上，是仰韶文化的命名地。1921 年安特生在这里试掘，"
     "第一次确认中国存在新石器时代的彩陶文化，后来整个文化就用这个村子命名。遗址约 30 万平方米，"
     "底下压着仰韶早期、庙底沟期和龙山时期三段遗存，中国史前研究是从这里开始有实物证据的。",
     ("s01-仰韶村遗址.md",
      "仰韶村遗址位于三门峡市渑池县仰韶村，地处黄河南岸台地，是仰韶文化的命名地。1921年安特生在此试掘，"
      "首次确认中国存在新石器时代彩陶文化，此后以遗址命名了仰韶文化。", 0.93)),
    (("二里头", "夏都", "最早的城市", "宫城"),
     "二里头遗址在洛阳市偃师区的洛河南岸，面积约 300 万平方米，年代大约公元前 1750 到前 1520 年。"
     "这里有中国最早的城市主干道网、宫城和多进院落的宫殿基址，还有青铜冶铸和绿松石的作坊，"
     "多数学者认为它是夏代中晚期的都城。代表性出土物是绿松石龙形器，两千多片绿松石拼出来的。",
     ("s04-二里头遗址.md",
      "二里头遗址位于洛阳市偃师区洛河南岸，面积约300万平方米。遗址发现中国最早的城市主干道网、宫城和"
      "多进院落宫殿基址，以及青铜冶铸、绿松石手工业作坊。", 0.91)),
    (("文创", "冰箱贴", "买什么", "纪念品"),
     "站内的文创目录里挂的都是概念设计数据，不是在售商品。举一个例子：鱼纹彩陶冰箱贴，¥39，软陶胎、"
     "表面哑光釉，单枚约 7.5×6 厘米，手工描线，背面嵌磁片，牛皮纸盒里附一张纹样说明卡。"
     "鱼纹是仰韶彩陶上最常见的母题之一，多画在盆、钵的口沿下方或内壁，从早段到晚段一点点从写实走向抽象。",
     ("goods-文创市集.md",
      "站内文创商品目录，均为概念演示数据。鱼纹是仰韶文化彩陶上最常见的母题之一，多画在盆、钵的口沿下方"
      "或内壁，鱼身常被简化成三角形与直线的组合。", 0.88)),
    (("课程", "教学", "小学生", "怎么画", "手作"),
     "有一门「仰韶彩陶的鱼纹怎么画」，手作坊、入门难度、18 分钟，关联仰韶村遗址。四步走："
     "先是练泥制坯，把气泡挤干净围出盆形；再起稿分区，用细炭条在肩腹部定出纹样带；"
     "然后勾线成形，矿物颜料调稀，鱼身一条弧线一次画完，来回描补就僵了；最后填彩留白，"
     "鱼鳞和鳍用黑彩点出来，红陶胎大面积留着不动。",
     ("courses-沿河课程.md",
      "仰韶彩陶的鱼纹怎么画（c01）：分类手作，难度入门，时长 18 分钟，关联遗址 s01。"
      "从揉泥开始，在盆形坯上把鱼纹画到位，再阴干入窑。", 0.86)),
    (("花园口", "铁桥", "谁设计"),
     "这个问题我答不了：知识库里没有花园口大铁桥的资料，也不猜一个名字给你。"
     "现在库里收的是沿河 20 处遗存和文创、课程这些站内内容，"
     "要查这座桥得去看铁路桥梁的专门史料。", None),
    (("传给别人", "隐私", "上传", "会不会收藏", "安全", "备份"),
     "收藏、笔记、足迹都存在这台设备的本地偏好文件里，不上传、不进任何账号体系，卸载即清。"
     "只有一处要说明白：设置里那个「带上我的收藏与笔记」默认是关的，"
     "打开之后你收藏的条目会随这一次的提问发给 Dify，用来把回答组织得贴着你走过的地方；"
     "关着的时候发过去的只有你敲进去的那句话。", None),
]

FALLBACK = ("演示档备着六组问题：仰韶村遗址、二里头遗址、沿河文创、彩陶手作课程、"
            "「花园口大铁桥是谁设计的」（库里没有就不编）、还有收藏笔记会不会传给别人。"
            "换别的机器要真回答，按 dify/README 起一套 Dify。")

def pick(query):
    for keys, answer, cite in CANNED:
        if any(k in query for k in keys):
            return answer, cite
    return FALLBACK, None

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
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

        answer, cite = pick(body.get("query") or "")
        time.sleep(STALL)
        for i in range(0, len(answer), 14):
            send({"event": "message", "answer": answer[i:i + 14], "created_at": int(time.time()),
                  "conversation_id": "mock-conv", "message_id": "mock-msg"})
            time.sleep(0.08)
        resources = []
        if cite is not None:
            doc, content, score = cite
            resources = [{"document_name": doc, "content": content, "score": score}]
        send({"event": "message_end", "conversation_id": "mock-conv", "message_id": "mock-msg",
              "metadata": {"retriever_resources": resources}})

    def log_message(self, *a):
        pass

if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    print("mock listening on 0.0.0.0:%d, stall=%.0fs" % (PORT, STALL), flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
