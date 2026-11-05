import { router } from '@kit.ArkUI';
import { SiteInfo, QuizRun } from '../model/Models';
import { SiteRepo } from '../service/SiteRepo';
import { MemoryStore } from '../service/MemoryStore';
import { StudioStore } from '../service/StudioStore';
import { SiteCard } from '../view/SiteCard';
import { RiverRibbon } from '../common/River';
import {
  INK, SUB, LOESS, CLAY, LINE, PAPER, fs, dayText
} from '../common/Theme';

interface QuizOption {
  t: string;
  hits: string[];
}

interface QuizQ {
  title: string;
  hint: string;
  opts: QuizOption[];
}

interface Persona {
  key: string;
  ch: string;
  name: string;
  line: string;
  detail: string;
  era: string;
}

const PERSONAS: Persona[] = [
  { key: 'yangshao', ch: '彩', name: '画彩的人', line: '你先看纹样，再看器形。',
    detail: '鱼纹、旋纹、几何边——你习惯先确认它好不好看，再问它是干什么用的。', era: '仰韶' },
  { key: 'longshan', ch: '黑', name: '磨黑的人', line: '你信手感，半毫米也算数。',
    detail: '薄如蛋壳的黑陶靠的是快轮和手感。你对精度有洁癖，讨厌差不多就行。', era: '龙山' },
  { key: 'xiashang', ch: '卜', name: '问卜的人', line: '遇事先问，问过才安心。',
    detail: '甲骨文是一场场问答留下的档案。你做决定前，想把问题问清楚、把答案刻下来。', era: '夏商' },
  { key: 'zhou', ch: '礼', name: '列鼎的人', line: '你讲顺序，讲位次，讲该谁先用。',
    detail: '天子驾六不是排场，是规则。你东西要编号，日程要排序，规矩立在前面。', era: '周' },
  { key: 'hantang', ch: '彩2', name: '烧彩的人', line: '你爱热闹，爱看东西从远方来。',
    detail: '三彩马沿着丝路走进洛阳。你对"外来物种"最有兴趣，窑火和市集都让你兴奋。', era: '汉唐' },
  { key: 'song', ch: '城', name: '叠城的人', line: '你习惯往深处看，一层一层数。',
    detail: '开封城摞城，一座压一座。你不满足于表面，非要把年代排到底。', era: '宋' }
];

const QUESTIONS: QuizQ[] = [
  { title: '库房里只能碰一件，你伸手去拿——', hint: '凭第一反应',
    opts: [
      { t: '一只画着鱼纹的陶盆', hits: ['yangshao'] },
      { t: '一只薄得透光的黑陶杯', hits: ['longshan'] },
      { t: '一片刻着字的龟甲', hits: ['xiashang'] },
      { t: '一件带纹饰的铜鼎', hits: ['zhou'] }
    ] },
  { title: '你更想在哪个位置待上一整天', hint: '不用讲道理',
    opts: [
      { t: '窑前，守着火看釉色变', hits: ['hantang'] },
      { t: '河边剖面旁，量土层厚度', hits: ['song', 'longshan'] },
      { t: '车马坑栏边，数辙印', hits: ['zhou'] },
      { t: '摊开的简牍前，抄字', hits: ['xiashang'] }
    ] },
  { title: '要给一条河做档案，你先记什么', hint: '第一栏写什么',
    opts: [
      { t: '两岸出过什么器物', hits: ['yangshao'] },
      { t: '哪一年改过河道', hits: ['song'] },
      { t: '谁在这儿打过仗', hits: ['zhou'] },
      { t: '出土记录怎么写', hits: ['longshan', 'xiashang'] }
    ] },
  { title: '这几种颜色，你最喜欢', hint: '看一眼就选',
    opts: [
      { t: '陶胎的红褐', hits: ['yangshao'] },
      { t: '打磨后的漆黑', hits: ['longshan'] },
      { t: '青铜的绿锈', hits: ['xiashang'] },
      { t: '琉璃的青灰', hits: ['hantang'] }
    ] },
  { title: '你习惯怎么把事情记下来', hint: '平时的做法',
    opts: [
      { t: '画下来', hits: ['yangshao'] },
      { t: '刻下来、写下来', hits: ['xiashang'] },
      { t: '按层排，排成序列', hits: ['song', 'longshan'] },
      { t: '编上号，一件不漏', hits: ['zhou'] }
    ] },
  { title: '一次远行，你最想看', hint: '会为哪个挪行程',
    opts: [
      { t: '老城叠在老城下面', hits: ['song'] },
      { t: '石窟里的一千面像', hits: ['hantang'] },
      { t: '一座没挖开的王陵', hits: ['xiashang', 'zhou'] },
      { t: '器物出土的原位置', hits: ['longshan', 'yangshao'] }
    ] },
  { title: '你更信哪一种证据', hint: '只能留一种',
    opts: [
      { t: '地层里挨着的两样东西', hits: ['longshan', 'song'] },
      { t: '史书上写明的年份', hits: ['zhou'] },
      { t: '器物上的指纹和烟痕', hits: ['yangshao'] },
      { t: '一匹马从哪儿来', hits: ['hantang'] }
    ] },
  { title: '让你亲手做一件东西', hint: '最后一题',
    opts: [
      { t: '拉一只杯', hits: ['longshan'] },
      { t: '画一圈彩', hits: ['yangshao'] },
      { t: '拓一片纹', hits: ['hantang', 'zhou'] },
      { t: '铸一枚印', hits: ['xiashang'] }
    ] }
];

function personaOf(key: string): Persona {
  for (let p of PERSONAS) {
    if (p.key === key) {
      return p;
    }
  }
  return PERSONAS[0];
}

@Entry
@Component
struct QuizPage {
  @StorageLink('studioRev') studioRev: number = 0;
  @StorageLink('textScale') ts: number = 1;
  @State idx: number = 0;
  @State picks: number[] = [];
  @State done: boolean = false;
  @State resultKey: string = '';
  @State reco: SiteInfo[] = [];

  aboutToAppear(): void {
    this.reco = [];
  }

  private tally(): string {
    let score: Map<string, number> = new Map();
    for (let i = 0; i < this.picks.length && i < QUESTIONS.length; i++) {
      let pick = this.picks[i];
      if (pick < 0 || pick >= QUESTIONS[i].opts.length) {
        continue;
      }
      let o = QUESTIONS[i].opts[pick];
      for (let k = 0; k < o.hits.length; k++) {
        let cur = score.get(o.hits[k]) ?? 0;
        score.set(o.hits[k], cur + (k === 0 ? 2 : 1));
      }
    }
    let best = '';
    let bestN = -1;
    for (let p of PERSONAS) {
      let n = score.get(p.key) ?? 0;
      if (n > bestN) {
        bestN = n;
        best = p.key;
      }
    }
    return bestN > 0 ? best : 'yangshao';
  }

  private buildReco(key: string): SiteInfo[] {
    let p = personaOf(key);
    let repo = SiteRepo.get();
    let fav = MemoryStore.get().favIds();
    let hit: SiteInfo[] = [];
    let fill: SiteInfo[] = [];
    for (let s of repo.sites) {
      if (s.eras.indexOf(p.era) >= 0) {
        if (fav.indexOf(s.id) >= 0) {
          fill.push(s);
        } else {
          hit.push(s);
        }
      }
    }
    let out = hit.slice(0, 3);
    for (let s of fill) {
      if (out.length >= 3) {
        break;
      }
      out.push(s);
    }
    if (out.length < 3) {
      for (let s of repo.sites) {
        if (out.length >= 3) {
          break;
        }
        if (out.indexOf(s) < 0 && s.eras.indexOf(p.era) < 0) {
          out.push(s);
        }
      }
    }
    return out;
  }

  choose(i: number): void {
    this.picks.push(i);
    if (this.picks.length >= QUESTIONS.length) {
      let key = this.tally();
      this.resultKey = key;
      this.reco = this.buildReco(key);
      StudioStore.get().addQuizRun(key, this.picks.slice());
      this.done = true;
      return;
    }
    this.idx = this.picks.length;
  }

  reset(): void {
    this.picks = [];
    this.idx = 0;
    this.done = false;
    this.resultKey = '';
    this.reco = [];
  }

  @Builder
  optionRow(q: QuizQ, i: number) {
    Row({ space: 10 }) {
      Text(['甲', '乙', '丙', '丁'][i])
        .fontSize(fs(this.ts, 13))
        .fontColor(CLAY)
        .width(26)
        .height(26)
        .borderRadius(13)
        .backgroundColor(PAPER)
        .textAlign(TextAlign.Center)
      Text(q.opts[i].t)
        .fontSize(fs(this.ts, 15))
        .fontColor(INK)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 13, bottom: 13 })
    .backgroundColor($r('app.color.card_bg'))
    .border({ width: 1, color: LINE })
    .borderRadius(12)
    .onClick((): void => {
      this.choose(i);
    })
  }

  @Builder
  ferryDots() {
    Row({ space: 6 }) {
      ForEach(QUESTIONS, (q: QuizQ, i: number): void => {
        Column()
          .width(i === this.idx && !this.done ? 18 : 7)
          .height(7)
          .borderRadius(4)
          .backgroundColor(i < this.picks.length ? CLAY :
            (i === this.idx && !this.done ? LOESS : '#D9CDB6'))
          .animation({ duration: 220, curve: Curve.EaseOut })
      }, (q: QuizQ, i: number): string => `${i}`)
    }
  }

  @Builder
  questionCard() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(`第 ${this.idx + 1} / ${QUESTIONS.length} 问`)
          .fontSize(fs(this.ts, 11))
          .fontColor(SUB)
        Blank()
        Text('趣味自测 · 非学术测评')
          .fontSize(fs(this.ts, 10))
          .fontColor(SUB)
          .borderRadius(8)
          .border({ width: 1, color: LINE })
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      }
      .width('100%')

      Text(QUESTIONS[this.idx].title)
        .fontSize(fs(this.ts, 19))
        .fontColor(INK)
        .fontWeight(FontWeight.Bold)
        .lineHeight(fs(this.ts, 28))
      Text(QUESTIONS[this.idx].hint)
        .fontSize(fs(this.ts, 11))
        .fontColor(SUB)

      ForEach(QUESTIONS[this.idx].opts, (o: QuizOption, i: number): void => {
        this.optionRow(QUESTIONS[this.idx], i)
      }, (o: QuizOption, i: number): string => `${this.idx}-${i}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  resultCard() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Text(personaOf(this.resultKey).ch)
          .fontSize(fs(this.ts, 22))
          .fontColor('#FBF4E7')
          .fontWeight(FontWeight.Bold)
          .width(52)
          .height(52)
          .borderRadius(12)
          .backgroundColor(CLAY)
          .textAlign(TextAlign.Center)
        Column({ space: 4 }) {
          Text(personaOf(this.resultKey).name)
            .fontSize(fs(this.ts, 20))
            .fontColor(INK)
            .fontWeight(FontWeight.Bold)
          Text(personaOf(this.resultKey).line)
            .fontSize(fs(this.ts, 13))
            .fontColor(CLAY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Text(personaOf(this.resultKey).detail)
        .fontSize(fs(this.ts, 13))
        .fontColor(INK)
        .lineHeight(fs(this.ts, 21))

      RiverRibbon({ bandHeight: 62, showDots: true, activeId: '',
        note: `你的年代是${personaOf(this.resultKey).era}，位置在河道示意图上。` })

      Column({ space: 8 }) {
        Text('先去这三处现场')
          .fontSize(fs(this.ts, 15))
          .fontColor(INK)
          .fontWeight(FontWeight.Medium)
        ForEach(this.reco, (s: SiteInfo): void => {
          SiteCard({ site: s })
        }, (s: SiteInfo): string => s.id)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Button('再测一次')
        .fontSize(fs(this.ts, 14))
        .fontColor('#FFFFFF')
        .backgroundColor(CLAY)
        .width('100%')
        .onClick((): void => {
          this.reset();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(14)
  }

  @Builder
  historyCard() {
    Column({ space: 8 }) {
      Text('测过的记录')
        .fontSize(fs(this.ts, 15))
        .fontColor(INK)
        .fontWeight(FontWeight.Medium)
      ForEach(StudioStore.get().quizRuns, (r: QuizRun): void => {
        Row({ space: 8 }) {
          Text(personaOf(r.persona).name)
            .fontSize(fs(this.ts, 14))
            .fontColor(INK)
            .layoutWeight(1)
          Text(`${r.picks.length} 问`)
            .fontSize(fs(this.ts, 11))
            .fontColor(SUB)
          Text(dayText(r.at))
            .fontSize(fs(this.ts, 11))
            .fontColor(SUB)
        }
        .width('100%')
        .padding({ top: 9, bottom: 9 })
      }, (r: QuizRun): string => r.id)
      Text('记录只存本机，未联网。')
        .fontSize(fs(this.ts, 10))
        .fontColor(SUB)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Text('‹ 返回')
          .fontSize(fs(this.ts, 14))
          .fontColor(INK)
          .onClick((): void => {
            router.back();
          })
        Text('趣味自测 · 你是哪种人手')
          .fontSize(fs(this.ts, 15))
          .fontColor(INK)
          .fontWeight(FontWeight.Medium)
        Blank()
        if (this.picks.length > 0 && !this.done) {
          Text('清空')
            .fontSize(fs(this.ts, 12))
            .fontColor(SUB)
            .onClick((): void => {
              this.reset();
            })
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 10 })

      Scroll() {
        Column({ space: 16 }) {
          if (this.done) {
            this.resultCard()
            if (StudioStore.get().quizRuns.length > 1) {
              this.historyCard()
            }
          } else {
            this.ferryDots()
            this.questionCard()
            Text('八道题，凭第一反应。结果只按你在本机选下的顺序算，同分取年代在前的一型。')
              .fontSize(fs(this.ts, 10))
              .fontColor(SUB)
              .lineHeight(fs(this.ts, 16))
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 28 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
