export interface Poem {
  line: string;
  author: string;
  source: string;
}

export interface TravelInfo {
  ticket: string;
  openTime: string;
  tips: string;
  updated: string;
}

export interface SiteInfo {
  id: string;
  name: string;
  alias: string;
  city: string;
  eras: string[];
  types: string[];
  cover: string;
  summary: string;
  intro: string;
  archaeology: string;
  history: string;
  poems: Poem[];
  travel: TravelInfo;
  source: string;
}

export interface Suggestion {
  site: SiteInfo;
  reason: string;
  score: number;
}

// ---- 个人数据（参与同步的记录都带 updatedAt 与 deleted） ----

export interface FavRec {
  siteId: string;
  tagIds: string[];
  createdAt: number;
  updatedAt: number;
  deleted: boolean;
}

export interface TagRec {
  id: string;
  name: string;
  createdAt: number;
  updatedAt: number;
  deleted: boolean;
}

export interface NoteRec {
  id: string;
  siteId: string;
  text: string;
  createdAt: number;
  updatedAt: number;
  version: number;
  deviceId: string;
  deleted: boolean;
  // 手动排序戳：整理模式里上下移动时重盖，缺省回落到 updatedAt
  ord?: number;
  // 由多篇笔记合并而来时记录来源，原文仍保留
  srcIds?: string[];
}

export interface ProgressRec {
  siteId: string;
  maxSection: number;
  read: boolean;
  updatedAt: number;
}

export interface TopicRec {
  id: string;
  name: string;
  siteIds: string[];
  createdAt: number;
  updatedAt: number;
  deleted: boolean;
}

export interface ViewLog {
  siteId: string;
  at: number;
}

// 到某一处遗址现场的落点记录（本机数据，暂未进跨端队列）
export interface CheckinRec {
  siteId: string;
  at: number;
}

// 趣味测试的一次作答
export interface QuizRun {
  id: string;
  persona: string;
  at: number;
  picks: number[];
}

// ---- 内容包（文创 / 课程 / 活动 / 社区），随包只读 ----

export interface SpecKV {
  k: string;
  v: string;
}

export interface Goods {
  id: string;
  name: string;
  sub: string;
  cat: string;
  price: number;
  era: string;
  origin: string;
  likes: number;
  tags: string[];
  palette: string;
  // 有实拍图就走图，留空才让 ArtCover 现画
  img: string;
  spec: SpecKV[];
  story: string;
  source: string;
}

export interface CourseStep {
  t: string;
  d: string;
}

export interface Course {
  id: string;
  title: string;
  brief: string;
  cat: string;
  level: string;
  minutes: number;
  palette: string;
  steps: CourseStep[];
  siteId: string;
  source: string;
}

export interface EventInfo {
  id: string;
  title: string;
  kind: string;
  date: string;
  place: string;
  fee: string;
  seats: string;
  brief: string;
  chars: string[];
  siteId: string;
}

export interface PostComment {
  author: string;
  text: string;
  at: number;
}

export interface Post {
  id: string;
  author: string;
  role: string;
  kind: string;
  img: string;
  text: string;
  siteId: string;
  topic: string;
  likes: number;
  at: number;
  comments: PostComment[];
}

// 本机补的评论：动态包里的评论是只读的，用户自己回的写在这台设备上
export interface LocalComment {
  id: string;
  postId: string;
  text: string;
  at: number;
}

// ---- 本机创作与互动数据（不参与跨端同步） ----

// 清单里的一件：id 对应随包 goods，n 是想要的数量
export interface CartLine {
  id: string;
  n: number;
}

export interface WorkRec {
  id: string;
  name: string;
  shape: string;
  motif: string;
  glaze: string;
  word: string;
  box: string;
  createdAt: number;
}

export interface Profile {
  nick: string;
  avatar: number;
  bio: string;
  joinedAt: number;
}

// 本机账号：昵称 + 口令摘要 + 掩码手机号，写在这台设备的 preferences 里，没有服务端。
// 退出登录只把 joinedAt 归零，账号与收藏笔记都留着，下次凭口令回来。
export interface AccountRec {
  nick: string;
  digest: string;
  avatar: number;
  createdAt: number;
  lastAt: number;
  // 注册时校验过的那个号，只存 138****5678 这种掩码；早于验证码功能注册的账号是空串
  phone: string;
}

// 备份文件结构
export interface BackupData {
  formatVer: number;
  appVer: string;
  exportedAt: number;
  siteCount: number;
  checksum: number;
  favorites: FavRec[];
  tags: TagRec[];
  notes: NoteRec[];
  progress: ProgressRec[];
  topics: TopicRec[];
}
