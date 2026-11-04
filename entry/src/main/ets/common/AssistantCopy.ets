// 河小导的"人话"文案层：AiService 抛回来的是技术错误，直接念给用户太硬。
// 这里按错误特征分组成一句口语主句 + 一行小字技术细节，
// 界面只负责排布，重试/去设置的入口都还在原来的位置上。
// 小字只做排错用，纯英文或带错误码的原文一律不上屏（见 tailOf）。

export interface ErrCopy {
  // 主句：河小导的口吻
  line: string;
  // 小字：可选的技术细节；不需要时给空串
  sub: string;
}

// AiService 用这两个标记代替原始报错，界面才能安心给温柔话术
const RATE_LIMIT: string = 'rate_limited';
const EMPTY_ANSWER: string = 'empty_answer';

function has(s: string, needle: string): boolean {
  return s.indexOf(needle) >= 0;
}

// 只保留中文那截；带英文串或错误码的原文一律不回显
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

  // 限流：HTTP 429、智谱 1305（访问量过大）/1302（速度限制）都归到这里，
  // 一大段英文报错在 AiService 就被拦掉了，这里只负责说得软一点
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
  // 看门狗到点（60s 没新字节）。本地部署下最常见的原因是模型刚被卸载、正在重新装载，
  // 不是网络断了，所以话术只说"翻得久"，并把重试的口子留给用户；旧文案里的"云端"也不成立。
  if (has(low, 'timeout') || has(t, '超时') || has(t, '没有响应') || has(t, '没有回应')) {
    return { line: '档案翻得有点久，河小导先等到这儿。再问一次试试，问题短一点会更快。', sub: tailOf(t) };
  }
  if (has(low, 'resolve host') || has(low, 'offline') || has(low, 'network')
    || has(low, 'connection') || has(low, 'connect') || has(t, '连不上')) {
    return { line: '这会儿像是没网，河小导够不着云端档案。检查一下网络再试试？', sub: tailOf(t) };
  }
  if (has(t, '模型侧报错') || has(t, '模型没有返回')) {
    return { line: '档案室那边答不上来，我换个说法再试试。', sub: tailOf(t) };
  }
  if (has(t, '请求被拒')) {
    return { line: '这个问题被档案室挡回来了，换一种问法试试。', sub: tailOf(t) };
  }
  return { line: '河小导没听清这一下，再说一遍？', sub: tailOf(t) };
}
