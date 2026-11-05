
export interface Citation {
  siteId: string;
  name: string;
  score: number;
  snippet: string;
  
  type: string;
}

export interface ChatTurn {
  role: string;
  text: string;
  at: number;
  citations: Citation[];
  failed: boolean;
  isAborted: boolean;
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

export interface DifyStreamEvent {
  event?: string;
  answer?: string;
  conversation_id?: string;
  message?: string;
  metadata?: DifyMeta;
}

export interface ProbeResult {
  ok: boolean;
  
  code: number;
  
  ms: number;
  
  msg: string;
}
