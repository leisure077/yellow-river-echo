export interface ErrCopy {
  line: string;
  sub: string;
}

const RATE_LIMIT: string = 'rate_limited';
const EMPTY_ANSWER: string = 'empty_answer';

function has(s: string, needle: string): boolean {
  return s.indexOf(needle) >= 0;
}

function tailOf(t: string): string {
  if (t.length === 0 || /[A-Za-z0-9]/.test(t)) {
    return '';
  }
  return t.length > 40 ? t.substring(0, 40) + '…' : t;
}

export function errCopyOf(raw: string): ErrCopy {
  let t = (raw ?? '').trim();
  if (t.length === 0) {
    return { line: '河小导刚才走神了，再问一次试试。', sub: '' };
  }
  let low = t.toLowerCase();

  if (t === RATE_LIMIT || has(low, '429') || has(t, '1305') || has(t, '1302')
    || has(t, '额度') || has(t, '太频繁')) {
    return {
      line: '哎呀，当前问的人太多啦，档案室一时忙不过来。您稍等片刻再问一次，我一直在。',
      sub: ''
    };
  }
  if (t === EMPTY_ANSWER) {
    return { line: '河小导刚才走神了，再问一次试试。', sub: '' };
  }
  if (has(t, '回答已中断') || has(t, '已中断')) {
    return { line: '这段先放下了，想听的话再说一声。', sub: tailOf(t) };
  }
  if (has(t, '先在设置') || (has(t, 'App Key') && has(t, '地址'))) {
    return { line: '我还没连上档案室，先到设置里填好地址和 App Key。', sub: tailOf(t) };
  }
  if (has(t, '格式不对')) {
    return { line: '档案室的门牌号写错了，地址要以 http:// 或 https:// 开头。', sub: tailOf(t) };
  }
  if (has(t, 'App Key 无效') || has(t, '失效') || has(low, '401')) {
    return { line: '这把钥匙开不了门，到 Dify 重新复制一份 App Key 吧。', sub: tailOf(t) };
  }
  if (has(t, '地址不对') || has(low, '404')) {
    return { line: '按这个地址找不到档案室，确认填的是 Dify 的 /v1 地址。', sub: tailOf(t) };
  }
  if (has(t, '连不上') || has(low, 'resolve host') || has(low, 'offline') || has(low, 'network')
    || has(low, 'connection') || has(low, 'connect')) {
    return {
      line: '河小导够不着档案室：这个地址现在连不上。看看 Dify 是否在跑，或在设置里点「测一下」。',
      sub: tailOf(t)
    };
  }
  if (has(low, 'timeout') || has(t, '超时') || has(t, '没有响应') || has(t, '没有回应')) {
    return { line: '档案翻得有点久，河小导先等到这儿。再问一次试试，问题短一点会更快。', sub: tailOf(t) };
  }
  if (has(t, '模型侧报错') || has(t, '模型没有返回')) {
    return { line: '档案室那边答不上来，我换个说法再试试。', sub: tailOf(t) };
  }
  if (has(t, '请求被拒')) {
    return { line: '这个问题被档案室挡回来了，换一种问法试试。', sub: tailOf(t) };
  }
  return { line: '河小导没听清这一下，再说一遍？', sub: tailOf(t) };
}
