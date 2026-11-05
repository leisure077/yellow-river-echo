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
  ord?: number;
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

export interface CheckinRec {
  siteId: string;
  at: number;
}

export interface QuizRun {
  id: string;
  persona: string;
  at: number;
  picks: number[];
}


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

export interface LocalComment {
  id: string;
  postId: string;
  text: string;
  at: number;
}


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

export interface AccountRec {
  nick: string;
  digest: string;
  avatar: number;
  createdAt: number;
  lastAt: number;
  phone: string;
}

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
