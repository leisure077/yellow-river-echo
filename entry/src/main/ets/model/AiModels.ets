// 河小导（Dify 客户端）的数据形状。
// 只保留页面要用的字段，Dify 返回的其余内容不落库。

export interface Citation {
  siteId: string;
  name: string;
  score: number;
  snippet: string;
  // 引用出自哪类知识库文档：'site' 遗址 / 'goods' 文创 / 'courses' 课程 / 'events' 活动。
  // 决定 Chip 的配色和点进去落到哪个页面；旧历史缺这个字段时由 AiStore 回填。
  type: string;
}

export interface ChatTurn {
  role: string; // 'user' | 'ai'
  text: string;
  at: number;
  citations: Citation[];
  failed: boolean;
  isAborted: boolean; // 用户点停或连接中断，只用来区分展示与排错
}

export interface DifyInputs {
  personal_context: string;
}

export interface DifyReq {
  inputs: DifyInputs;
  query: string;
  response_mode: string;
  conversation_id: string;
  user: string;
}

export interface RetrieverRes {
  document_name?: string;
  content?: string;
  score?: number;
}

export interface DifyMeta {
  retriever_resources?: RetrieverRes[];
}

export interface DifyChatResp {
  answer?: string;
  conversation_id?: string;
  message_id?: string;
  metadata?: DifyMeta;
}

export interface DifyError {
  code?: string;
  message?: string;
  status?: number;
}

// response_mode: streaming 时每一行 data: 反序列化后的形状
export interface DifyStreamEvent {
  event?: string;
  answer?: string;
  conversation_id?: string;
  message?: string;
  metadata?: DifyMeta;
}

// 设置页「测一下」的结果：只描述能不能连上，不带回答内容
export interface ProbeResult {
  ok: boolean;
  // HTTP 状态码；0 表示根本没拿到状态码（DNS/连接/超时）
  code: number;
  // 整次探测耗时，毫秒
  ms: number;
  // 给设置页直接显示的一句话
  msg: string;
}
