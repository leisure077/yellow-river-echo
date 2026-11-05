import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { Citation, DifyMeta, DifyReq, DifyStreamEvent, ProbeResult, RetrieverRes } from '../model/AiModels';
import { AiStore } from './AiStore';
import { SiteRepo } from './SiteRepo';
import { cleanAiText } from '../common/Markdown';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HH_AI';

export interface StreamHooks {
  onChunk: (raw: string) => void;
  onDone: (citations: Citation[], aborted: boolean) => void;
  onError: (msg: string) => void;
}

export interface StreamHandle {
  stop: () => void;
}

export class AiService {
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
      store.clearLastFail();
      AiService.info('答完 status=' + status + ' 首字 ' + (ttft > 0 ? (ttft - t0) : -1)
        + 'ms 总 ' + (Date.now() - t0) + 'ms 字数 ' + raw.length
        + (aborted ? '（用户中断）' : ''));
      hooks.onDone(citations, aborted);
    };

    let stale = (code: number, detail: string): boolean => {
      if (store.conversationId.length === 0) {
        return false;
      }
      if (code === 404) {
        return true;
      }
      return detail.toLowerCase().indexOf('conversation') >= 0;
    };

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
          let m = ev.message ?? '未知原因';
          fail(AiService.rateLimited(m) ? AiService.ERR_RATE_LIMIT : AiService.ERR_MODEL + '：' + m,
            status, m);
          return;
        }
      }
    };

    let settle = (): void => {
      if (stopped || finished) {
        return;
      }
      if (status !== 0 && status !== 200) {
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
      if (status === 0) {
        return;
      }
      settle();
    });

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
    return this.siteIdOf(name).length > 0 ? 'site' : '';
  }

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
