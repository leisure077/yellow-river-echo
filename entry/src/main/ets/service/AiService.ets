import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { Citation, DifyMeta, DifyReq, DifyStreamEvent, ProbeResult, RetrieverRes } from '../model/AiModels';
import { AiStore } from './AiStore';
import { SiteRepo } from './SiteRepo';
import { cleanAiText } from '../common/Markdown';

// 排错日志统一走这个 tag：换了电脑、由别人接手时，一条命令就能看清
// 「这次请求打到哪个地址、HTTP 状态码、首字多久、整段多久」——
// hdc shell "hilog | grep HH_AI"。
// 只打地址、数字和状态，绝不打 App Key，也不打游客的问题和回答。
const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HH_AI';

export interface StreamHooks {
  // 每次收到增量都回传「截至目前的原文」，页面自己做 50ms 合并与打字机
  onChunk: (raw: string) => void;
  onDone: (citations: Citation[], aborted: boolean) => void;
  onError: (msg: string) => void;
}

export interface StreamHandle {
  stop: () => void;
}

// Dify 客户端：response_mode = streaming，走 SSE。
// 停止即销毁连接，服务端随之停止生成，不留后台任务。
export class AiService {
  // 界面按这两个标记决定文案，别在这里拼游客要看的话
  static readonly ERR_RATE_LIMIT: string = 'rate_limited';
  static readonly ERR_EMPTY: string = 'empty_answer';
  static readonly ERR_MODEL: string = '模型侧报错';
  private static readonly inst: AiService = new AiService();
  static get(): AiService {
    return AiService.inst;
  }

  private static info(s: string): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', s);
  }

  start(query: string, personalContext: string, hooks: StreamHooks): StreamHandle {
    // 页面持有的是这个外层句柄，全程不换；会话号自愈时会另起一条请求，
    // 只把内层换掉，「停止」才不会出现按在已经死掉的旧连接上。
    let inner: StreamHandle = { stop: (): void => {} };
    let swap = (h: StreamHandle): void => {
      inner = h;
    };
    swap(this.run(query, personalContext, hooks, true, swap));
    return {
      stop: (): void => {
        inner.stop();
      }
    };
  }

  // allowHeal=false 的那一轮是自愈后的重发：再失败就直接把错报给用户，不打转。
  private run(query: string, personalContext: string, hooks: StreamHooks,
              allowHeal: boolean, swap: (h: StreamHandle) => void): StreamHandle {
    let store = AiStore.get();
    if (!store.configured()) {
      setTimeout((): void => hooks.onError('先在设置里填写 Dify 地址和 App Key'), 0);
      return { stop: (): void => {} };
    }
    let url = this.endpoint(store.baseUrl);
    if (url.length === 0) {
      setTimeout((): void => hooks.onError('接口地址格式不对，应以 http:// 或 https:// 开头'), 0);
      return { stop: (): void => {} };
    }

    let body: DifyReq = {
      inputs: { personal_context: personalContext },
      query: query,
      response_mode: 'streaming',
      conversation_id: store.conversationId,
      user: store.userTag()
    };
    let header: Record<string, string> = {
      'Authorization': 'Bearer ' + store.appKey,
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream'
    };

    let req = http.createHttp();
    let decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    // SSE 的一个事件可能被 TCP 切成多段，pending 负责把半截事件留到下一包再拼
    let pending = '';
    let raw = '';
    let citations: Citation[] = [];
    let convId = store.conversationId;
    let status = 0;
    let errBody = '';
    let ended = false;
    let finished = false;
    let stopped = false;
    let lastData = Date.now();
    let watchdog = -1;
    // 首字延迟单独记一个点：本地部署慢的时候，它是判断「卡在检索还是卡在生成」的依据
    let t0 = Date.now();
    let ttft = 0;
    let self = this;

    let release = (): void => {
      if (watchdog >= 0) {
        clearInterval(watchdog);
        watchdog = -1;
      }
      try {
        req.destroy();
      } catch (e) {
        // 连接可能已被销毁，忽略
      }
    };

    let finishOk = (aborted: boolean): void => {
      if (finished) {
        return;
      }
      finished = true;
      release();
      if (convId.length > 0 && convId !== store.conversationId) {
        store.setConversation(convId).catch((e: Error): void => {
          console.warn('conversation save: ' + e.message);
        });
      }
      // 这一次通了，之前留着的失败现场就没有参考价值了
      store.clearLastFail();
      AiService.info('答完 status=' + status + ' 首字 ' + (ttft > 0 ? (ttft - t0) : -1)
        + 'ms 总 ' + (Date.now() - t0) + 'ms 字数 ' + raw.length
        + (aborted ? '（用户中断）' : ''));
      hooks.onDone(citations, aborted);
    };

    // 本机存着会话号时才谈得上失效；404 或报错原文里带 conversation 都算。
    // 判错了最多是白重发一次，第二次仍旧把原始错误如实交给用户。
    let stale = (code: number, detail: string): boolean => {
      if (store.conversationId.length === 0) {
        return false;
      }
      if (code === 404) {
        return true;
      }
      return detail.toLowerCase().indexOf('conversation') >= 0;
    };

    // detail 传服务端返回的原文（状态码那一侧的 body / SSE 的 message），
    // 用来认「会话号失效」这类特征，同时作为设置页显示的最近失败原因。
    let fail = (msg: string, code: number, detail: string): void => {
      if (finished) {
        return;
      }
      if (allowHeal && stale(code, detail)) {
        finished = true;
        release();
        AiService.info('会话号失效，清掉本地会话重发一次');
        store.setConversation('').catch((e: Error): void => {
          console.warn('conversation reset: ' + e.message);
        });
        setTimeout((): void => {
          swap(self.run(query, personalContext, hooks, false, swap));
        }, 0);
        return;
      }
      finished = true;
      release();
      store.markFail(code, Date.now() - t0, detail);
      AiService.info('失败 status=' + code + ' 用时 ' + (Date.now() - t0) + 'ms：' + msg);
      hooks.onError(msg);
    };

    let consume = (block: string): void => {
      let lines = block.split('\n');
      for (let line of lines) {
        let s = line.trim();
        if (!s.startsWith('data:')) {
          continue;
        }
        let payload = s.substring(5).trim();
        if (payload.length === 0 || payload === '[DONE]') {
          continue;
        }
        let ev: DifyStreamEvent;
        try {
          ev = JSON.parse(payload) as DifyStreamEvent;
        } catch (e) {
          continue;
        }
        let cid = ev.conversation_id ?? '';
        if (cid.length > 0) {
          convId = cid;
        }
        let name = ev.event ?? '';
        if (name === 'message') {
          let piece = ev.answer ?? '';
          if (piece.length > 0) {
            if (ttft === 0) {
              ttft = Date.now();
            }
            raw += piece;
            hooks.onChunk(raw);
          }
        } else if (name === 'message_end') {
          citations = self.citationsOf(ev.metadata);
        } else if (name === 'error') {
          // 限流最常见的是智谱 1305/1302，插件会把一大段英文原文塞进 message，
          // 这里先认特征，认出来就不让原文往下走
          let m = ev.message ?? '未知原因';
          fail(AiService.rateLimited(m) ? AiService.ERR_RATE_LIMIT : AiService.ERR_MODEL + '：' + m,
            status, m);
          return;
        }
      }
    };

    // 状态码落定后统一收尾：非 200 先按错误处理，200 则把残留半帧消费掉
    let settle = (): void => {
      if (stopped || finished) {
        return;
      }
      if (status !== 0 && status !== 200) {
        // 状态码回来得晚时，错误体可能已经在 pending 里当 SSE 攒着了
        let errText = errBody.length > 0 ? errBody : pending;
        fail(self.errorOf(status, errText), status, errText);
        return;
      }
      if (pending.trim().length > 0) {
        consume(pending);
      }
      finishOk(false);
    };

    req.on('dataReceive', (data: ArrayBuffer): void => {
      if (stopped || finished) {
        return;
      }
      lastData = Date.now();
      let text = '';
      try {
        text = decoder.decodeToString(new Uint8Array(data), { stream: true });
      } catch (e) {
        return;
      }
      if (status !== 0 && status !== 200) {
        errBody += text;
        return;
      }
      pending = (pending + text).replace(/\r/g, '');
      let cut = pending.indexOf('\n\n');
      while (cut >= 0) {
        let block = pending.substring(0, cut);
        pending = pending.substring(cut + 2);
        consume(block);
        if (finished) {
          return;
        }
        cut = pending.indexOf('\n\n');
      }
    });

    req.on('dataEnd', (): void => {
      ended = true;
      if (stopped || finished) {
        return;
      }
      // 小响应体时 dataEnd 可能先于 requestInStream 的 then 回调，
      // 此时 status 仍是 0，要等 Promise 落定后再判定，否则 401 会被当成空回答
      if (status === 0) {
        return;
      }
      settle();
    });

    // http 没有 error 事件：连接中途断掉时 dataEnd 也不会来，靠看门狗兜底。
    // 三个时间要按大小排好：connectTimeout 8s（只管握手）< 看门狗 60s（管的是「还有没有新字节」）
    // < readTimeout 90s（http 侧的整体读超时，真到它这里就是连接被掐了）。
    // 看门狗窗口给到 60s 的原因：本机 Dify + Ollama 冷态（embedding 模型被卸载后重新装回显存）
    // 实测首字 34.5s，设了 OLLAMA_KEEP_ALIVE=-1 后是 13s，但重启过电脑就会退回前者；
    // 25s 会把这种「还在查」的请求误判成网络断了。真断了 60s 也一样能兜住。
    // 换别人的机器时先跑一次「测一下」，再看 hilog 里的首字耗时，不要直接改这里的数字。
    watchdog = setInterval((): void => {
      if (finished) {
        return;
      }
      if (Date.now() - lastData > 60000) {
        fail('长时间没有回应', status, 'watchdog 60s 无新字节');
      }
    }, 2000);

    AiService.info('提问 → ' + url + ' 会话 ' + (convId.length > 0 ? convId : '新'));

    req.requestInStream(url, {
      method: http.RequestMethod.POST,
      header: header,
      extraData: JSON.stringify(body),
      connectTimeout: 8000,
      readTimeout: 90000,
      usingCache: false
    }).then((code: number): void => {
      status = code;
      if (ended) {
        settle();
      }
    }).catch((e: BusinessError): void => {
      if (stopped || finished) {
        return;
      }
      fail('连不上 Dify：' + (e.message ?? ''), 0, e.message ?? '');
    });

    return {
      stop: (): void => {
        if (finished) {
          return;
        }
        stopped = true;
        finishOk(true);
      }
    };
  }

  // 用户可能只填到域名，也可能已经带了 /v1，这里统一补齐到 /v1
  private v1(base: string): string {
    let b = base.trim();
    if (!b.startsWith('http://') && !b.startsWith('https://')) {
      return '';
    }
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (!b.endsWith('/v1')) {
      b = b + '/v1';
    }
    return b;
  }

  private endpoint(base: string): string {
    let v = this.v1(base);
    return v.length === 0 ? '' : v + '/chat-messages';
  }

  // 设置页的「测一下」：只 GET 一次 /v1/parameters，让 Dify 在应用配置里回一小段 JSON。
  // 它不进知识库、不调模型、不占 token，却能把四类现场问题分开：
  // 地址写错(404) / Key 不对(401) / 服务没起或网络不通(拿不到状态码) / 一切正常(200)。
  // 评委在别人电脑上第一次接的时候，先看这一行再看报错文案，能省掉大半来回。
  probe(base: string, key: string): Promise<ProbeResult> {
    return new Promise<ProbeResult>((resolve: (r: ProbeResult) => void): void => {
      let out: ProbeResult = { ok: false, code: 0, ms: 0, msg: '' };
      let v = this.v1(base);
      if (v.length === 0) {
        out.msg = '地址不对：应以 http:// 或 https:// 开头';
        resolve(out);
        return;
      }
      let k = key.trim();
      if (k.length === 0) {
        out.msg = '先填 App Key';
        resolve(out);
        return;
      }
      let url = v + '/parameters';
      // 地址可以进日志（它本来就写在设置页里），Key 不行
      AiService.info('探测 → ' + url);
      let t0 = Date.now();
      let req = http.createHttp();
      let header: Record<string, string> = {
        'Authorization': 'Bearer ' + k,
        'Accept': 'application/json'
      };
      let done = (ok: boolean, code: number, msg: string): void => {
        out.ok = ok;
        out.code = code;
        out.ms = Date.now() - t0;
        out.msg = msg;
        try {
          req.destroy();
        } catch (e) {
          // 已经销毁，忽略
        }
        AiService.info('探测结果 code=' + code + ' 用时 ' + out.ms + 'ms：' + msg);
        resolve(out);
      };
      req.request(url, {
        method: http.RequestMethod.GET,
        header: header,
        connectTimeout: 8000,
        readTimeout: 15000,
        usingCache: false
      }).then((res: http.HttpResponse): void => {        let code = res.responseCode;
        if (code === 200) {
          done(true, code, '通了，' + (Date.now() - t0) + 'ms。地址和 Key 都能用。');
        } else if (code === 401 || code === 403) {
          done(false, code, '地址通、Key 不通（' + code + '）：去 Dify 应用页重复制 App Key。');
        } else if (code === 404) {
          done(false, code, '地址通、接口不对（404）：确认填的是 Dify 的 /v1 地址，别填成网站首页。');
        } else {
          done(false, code, '服务回 ' + code + '：' + (Date.now() - t0) + 'ms。');
        }
      }).catch((e: BusinessError): void => {
        done(false, 0, '连不上：' + (e.message ?? '未知原因')
          + '（检查 Dify 是否在跑、地址是不是本机地址）');
      });
    });
  }

  // 限流特征：HTTP 429、智谱 1305（访问量过大）/1302（速度限制）、
  // 或插件原样带出的 too many requests / rate limit 字样。
  static rateLimited(raw: string): boolean {
    let t = (raw ?? '').toLowerCase();
    if (t.length === 0) {
      return false;
    }
    return t.indexOf('429') >= 0 || t.indexOf('1305') >= 0 || t.indexOf('1302') >= 0
      || t.indexOf('too many requests') >= 0 || t.indexOf('rate limit') >= 0
      || t.indexOf('访问速度') >= 0 || t.indexOf('访问量') >= 0;
  }

  private errorOf(code: number, raw: string): string {
    if (code === 429 || AiService.rateLimited(raw)) {
      return AiService.ERR_RATE_LIMIT;
    }
    let detail = '';
    try {
      let err = JSON.parse(raw) as DifyStreamEvent;
      detail = err.message ?? '';
    } catch (e) {
      detail = '';
    }
    if (code === 401) {
      return 'App Key 无效或已失效，请到 Dify 重新复制';
    }
    if (code === 404) {
      return '地址不对：确认填的是 Dify 的 /v1 地址';
    }
    if (code === 429) {
      return '调用太频繁，或该 Key 的额度用完了';
    }
    if (code === 400 && detail.length > 0) {
      return '请求被拒：' + detail;
    }
    return '服务返回 ' + code + (detail.length > 0 ? '：' + detail : '');
  }

  private citationsOf(meta: DifyMeta | undefined): Citation[] {
    let out: Citation[] = [];
    let list = meta?.retriever_resources;
    if (list === undefined) {
      return out;
    }
    for (let r of list) {
      this.addCitation(out, r);
    }
    return out;
  }

  private addCitation(out: Citation[], r: RetrieverRes): void {
    let doc = (r.document_name ?? '').trim();
    if (doc.length === 0) {
      return;
    }
    let kind = this.kindOf(doc);
    if (kind.length === 0) {
      return;
    }
    let siteId = kind === 'site' ? this.siteIdOf(doc) : '';
    let site = siteId.length > 0 ? SiteRepo.get().byId(siteId) : undefined;
    let name = site !== undefined ? site.name : this.topicNameOf(kind, doc);
    for (let c of out) {
      if (c.siteId === siteId && c.name === name) {
        return;
      }
    }
    let snippet = cleanAiText(r.content ?? '');
    if (snippet.length > 56) {
      snippet = snippet.substring(0, 56) + '…';
    }
    out.push({
      siteId: siteId,
      name: name,
      score: r.score ?? 0,
      snippet: snippet,
      type: kind
    });
  }

  // 知识库文档命名约定：遗址是 s01-仰韶村遗址.md，专题是 goods-文创市集.md /
  // courses-沿河课程.md / events-沿河活动.md / posts-社区动态.md。
  // 只放行白名单：posts 是站内用户分享，不能当作事实依据，整条引用直接丢；
  // 认不出来的文档（临时试验稿、别的知识库）同样不渲染 Chip，返回空串。
  private kindOf(doc: string): string {
    let name = doc;
    if (name.endsWith('.md')) {
      name = name.substring(0, name.length - 3);
    }
    let dash = name.indexOf('-');
    let head = (dash > 0 ? name.substring(0, dash) : name).toLowerCase();
    if (head === 'posts') {
      return '';
    }
    if (head === 'goods' || head === 'courses' || head === 'events') {
      return head;
    }
    // 遗址必须能在 SiteRepo 里对上号，等于把 s01~s20 当白名单用
    return this.siteIdOf(name).length > 0 ? 'site' : '';
  }

  // 专题 Chip 只展示中文专题名，不带 goods- 这类文件名前缀
  private topicNameOf(kind: string, doc: string): string {
    let name = doc;
    if (name.endsWith('.md')) {
      name = name.substring(0, name.length - 3);
    }
    let dash = name.indexOf('-');
    let tail = (dash > 0 ? name.substring(dash + 1) : '').trim();
    if (tail.length > 0) {
      return tail;
    }
    if (kind === 'goods') {
      return '文创市集';
    }
    if (kind === 'courses') {
      return '沿河课程';
    }
    return '沿河活动';
  }

  // 知识库文件名约定为「s01-仰韶村遗址.md」，引用回跳时只认 siteId
  private siteIdOf(doc: string): string {
    let name = doc.trim();
    if (name.endsWith('.md')) {
      name = name.substring(0, name.length - 3);
    }
    let dash = name.indexOf('-');
    if (dash > 0) {
      let head = name.substring(0, dash);
      if (SiteRepo.get().byId(head) !== undefined) {
        return head;
      }
    }
    if (SiteRepo.get().byId(name) !== undefined) {
      return name;
    }
    for (let s of SiteRepo.get().sites) {
      if (name.indexOf(s.name) >= 0) {
        return s.id;
      }
    }
    return '';
  }
}
