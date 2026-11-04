import { router } from '@kit.ArkUI';
import { ChatTurn, Citation, ProbeResult } from '../model/AiModels';
import { AiStore } from '../service/AiStore';
import { AiService, StreamHandle } from '../service/AiService';
import { AiContext } from '../service/AiContext';
import { cleanAiText, cleanPartial } from '../common/Markdown';
import { errCopyOf } from '../common/AssistantCopy';
import { INK, SUB, LOESS, CLAY, LINE, RIVER, fs } from '../common/Theme';
import { goDetail, goTopicSection } from '../common/Nav';

const TIPS: string[] = [
  '仰韶彩陶有什么特点？',
  '二里头为什么被称为最早的中国？',
  '我收藏里哪几处值得先去？'
];

// 打字机的节拍：50ms 合并一次增量，既不会一格一格卡顿，也不至于整段跳出
const TYPE_MS: number = 50;

@Entry
@Component
struct AssistantPage {
  // 字号档位变了要整页重画：不持有这行，切档后这一页还是老字号
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('aiRev') rev: number = 0;
  @State turns: ChatTurn[] = [];
  @State input: string = '';
  @State busy: boolean = false;
  @State cfgOpen: boolean = false;
  @State base: string = '';
  @State apiKey: string = '';
  @State personal: boolean = false;
  @State err: string = '';
  @State lastQ: string = '';
  @State clearAsk: boolean = false;
  @State live: string = '';
  @State liveOn: boolean = false;
  // 「测一下」的自检结果只出现在设置卡片里，不打扰游客
  @State probing: boolean = false;
  @State probeMsg: string = '';
  @State lastFail: string = '';
  private scroller: Scroller = new Scroller();
  private handle: StreamHandle | null = null;
  private timer: number = -1;
  private rawTarget: string = '';
  private cleanTarget: string = '';
  private shown: number = 0;
  private streamDone: boolean = false;
  private streamErr: string = '';
  private streamCites: Citation[] = [];
  private askQ: string = '';
  private wasAborted: boolean = false;
  private closing: boolean = false;
  private lastFollow: number = 0;

  aboutToAppear(): void {
    this.reload();
    if (!AiStore.get().configured()) {
      this.cfgOpen = true;
    }
  }

  aboutToDisappear(): void {
    this.stopTimer();
    if (this.handle !== null) {
      this.handle.stop();
      this.handle = null;
    }
  }

  reload(): void {
    let s = AiStore.get();
    this.turns = s.turns.slice();
    this.base = s.baseUrl;
    this.apiKey = s.appKey;
    this.personal = s.personalOn;
    this.lastFail = s.lastFail;
    this.toBottom();
  }

  toBottom(): void {
    setTimeout((): void => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 60);
  }

  // 流式期间每 50ms 都会触发，滚动按 150ms 节流，避免和打字抢帧
  follow(): void {
    let now = Date.now();
    if (now - this.lastFollow < 150) {
      return;
    }
    this.lastFollow = now;
    this.scroller.scrollEdge(Edge.Bottom);
  }

  send(): void {
    let q = this.input.trim();
    if (q.length === 0 || this.busy) {
      return;
    }
    if (!AiStore.get().configured()) {
      this.cfgOpen = true;
      this.err = '先填好 Dify 地址和 App Key 再提问';
      return;
    }
    this.input = '';
    this.run(q, true);
  }

  run(q: string, pushUser: boolean): void {
    let store = AiStore.get();
    this.err = '';
    this.clearAsk = false;
    this.askQ = q;
    this.rawTarget = '';
    this.cleanTarget = '';
    this.shown = 0;
    this.live = '';
    this.streamDone = false;
    this.streamErr = '';
    this.streamCites = [];
    this.wasAborted = false;
    this.closing = false;
    if (pushUser) {
      store.pushTurn({
        role: 'user', text: q, at: Date.now(), citations: [], failed: false, isAborted: false
      });
    }
    this.turns = store.turns.slice();
    this.busy = true;
    this.liveOn = true;
    this.toBottom();
    this.startTimer();

    let ctx = AiContext.build(q);
    this.handle = AiService.get().start(q, ctx, {
      onChunk: (raw: string): void => {
        this.rawTarget = raw;
      },
      onDone: (citations: Citation[], aborted: boolean): void => {
        this.handle = null;
        this.streamDone = true;
        this.streamCites = citations;
        this.wasAborted = aborted;
        if (aborted) {
          this.fastForward();
        }
      },
      onError: (msg: string): void => {
        this.handle = null;
        this.streamDone = true;
        this.streamErr = msg;
      }
    });
  }

  startTimer(): void {
    this.stopTimer();
    this.timer = setInterval((): void => {
      this.pump();
    }, TYPE_MS);
  }

  stopTimer(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  // 每次节拍都按最新原文重算可见文本：流没结束时半行保守清洗，结束后走正式清洗
  pump(): void {
    if (!this.liveOn || this.closing) {
      this.stopTimer();
      return;
    }
    this.cleanTarget = this.streamDone ? cleanAiText(this.rawTarget) : cleanPartial(this.rawTarget);
    if (this.shown < this.cleanTarget.length) {
      let remain = this.cleanTarget.length - this.shown;
      // 差距越大步进越大，避免模型吐得快时打字机永远追不上
      let step = Math.max(2, Math.ceil(remain / 6));
      this.shown = Math.min(this.cleanTarget.length, this.shown + step);
      this.live = this.cleanTarget.substring(0, this.shown);
      this.follow();
    }
    if (this.streamDone && this.shown >= this.cleanTarget.length) {
      this.finish();
    }
  }

  // 用户按停止：已收到的内容一次性补齐，立刻收尾，不留定时器也不留连接
  fastForward(): void {
    this.cleanTarget = cleanAiText(this.rawTarget);
    this.shown = this.cleanTarget.length;
    this.live = this.cleanTarget;
    this.finish();
  }

  finish(): void {
    if (this.closing) {
      return;
    }
    this.closing = true;
    this.stopTimer();
    this.busy = false;
    this.liveOn = false;
    let store = AiStore.get();
    let text = this.cleanTarget;
    if (text.length > 0) {
      store.pushTurn({
        role: 'ai', text: text, at: Date.now(), citations: this.streamCites,
        failed: false, isAborted: this.wasAborted
      });
      this.turns = store.turns.slice();
    }
    if (this.streamErr.length > 0) {
      this.err = text.length > 0 ? this.streamErr + '（回答已中断）' : this.streamErr;
      this.lastQ = this.askQ;
      // 状态码和耗时是服务里同步记下的，设置卡片展开时给排错的人看
      this.lastFail = store.lastFail;
    } else if (text.length === 0) {
      this.err = AiService.ERR_EMPTY;
      this.lastQ = this.askQ;
      this.lastFail = store.lastFail;
    } else {
      this.lastFail = store.lastFail;
    }
    this.live = '';
    this.rawTarget = '';
    this.toBottom();
  }

  stop(): void {
    if (this.handle !== null) {
      this.handle.stop();
      return;
    }
    this.streamDone = true;
    this.fastForward();
  }

  async saveCfg(): Promise<void> {
    if (this.apiKey.trim().length === 0) {
      this.err = 'App Key 不能为空';
      return;
    }
    await AiStore.get().saveSettings(this.base, this.apiKey);
    this.cfgOpen = false;
    this.err = '';
  }

  // 设置页的「测一次」：地址和 Key 用当前输入框里的值（没保存也能测），
  // 只打一次 /v1/parameters，不消耗模型额度，也不留下问答记录。
  probeOnce(): void {
    if (this.probing) {
      return;
    }
    this.probing = true;
    this.probeMsg = '正在试…';
    AiService.get().probe(this.base, this.apiKey).then((r: ProbeResult): void => {
      this.probing = false;
      this.probeMsg = r.msg;
      // 连上的话，之前那次失败的现场也就不必再提了
      if (r.ok) {
        this.lastFail = '';
      }
    }).catch((e: Error): void => {
      this.probing = false;
      this.probeMsg = '没测成：' + e.message;
    });
  }

  // 地址里的 127.0.0.1 只在一种情况下是对的：本机用 hdc 端口转发把服务映射进设备。
  // 别人第一次接的时候最容易踩这个坑，所以只提醒、不拦（拦了会把 rport 用法堵死）。
  addrHint(): string {
    let b = this.base.trim().toLowerCase();
    if (b.length === 0) {
      return '填 Dify 的 /v1 地址。本机自建：模拟器里填 http://10.0.2.2/v1；'
        + '真机走局域网填电脑的 IP，走 USB 转发（hdc rport）才填 http://127.0.0.1:端口/v1。';
    }
    if (b.indexOf('127.0.0.1') >= 0 || b.indexOf('localhost') >= 0) {
      return '注意：127.0.0.1 指的是这台设备自己。模拟器里请用 http://10.0.2.2/v1；'
        + '真机只有做了 hdc 端口转发时才能用 127.0.0.1。';
    }
    return '';
  }

  // App Key 是一长串，输入框窄、又是密文显示，最容易漏粘。这里只看长度和前缀，绝不回显内容。
  // 本机这套 Dify 的 Key 实测 28 字（app- + 24），所以只把「短到不可能是整串」当异常。
  keyHint(): string {
    let k = this.apiKey.trim();
    if (k.length === 0) {
      return '在 Dify 应用的「访问 API」页复制 App Key（app- 开头一整串），整段粘贴进来。';
    }
    if (!k.startsWith('app-')) {
      return '看着不像 Dify 的 App Key：它应以 app- 开头，多半是粘掉了开头。';
    }
    if (k.length < 12) {
      return '这一串只有 ' + k.length + ' 字，不像整串（本机 Dify 发的是 28 字）：重新整段复制粘贴。';
    }
    return '';
  }

  askTip(s: string): void {
    if (this.busy) {
      return;
    }
    this.input = s;
    this.send();
  }

  retry(): void {
    let q = this.lastQ;
    if (q.length === 0 || this.busy) {
      return;
    }
    this.lastQ = '';
    this.run(q, false);
  }

  @Builder
  head() {
    Row({ space: 10 }) {
      Text('‹ 返回')
        .fontSize(fs(this.ts, 14))
        .fontColor(INK)
        .onClick((): void => {
          router.back();
        })
      Column({ space: 2 }) {
        Text('河小导')
          .fontSize(fs(this.ts, 16))
          .fontColor(INK)
          .fontWeight(FontWeight.Medium)
        Text('黄河续响平台 · 文化向导')
          .fontSize(fs(this.ts, 10))
          .fontColor(SUB)
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
      Text(this.cfgOpen ? '完成' : '设置')
        .fontSize(fs(this.ts, 12))
        .fontColor(this.cfgOpen ? CLAY : SUB)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .onClick((): void => {
          this.cfgOpen = !this.cfgOpen;
          this.err = '';
          this.probeMsg = '';
          this.clearAsk = false;
          // 只刷新排错现场，不回灌输入框：用户可能刚改了地址还没点保存
          this.lastFail = AiStore.get().lastFail;
        })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 10 })
  }

  @Builder
  cfgCard() {
    Scroll() {
      Column({ space: 12 }) {
        Text('接入设置')
          .fontSize(fs(this.ts, 15))
          .fontColor(INK)
          .fontWeight(FontWeight.Medium)
          .width('100%')

        Text('Dify 地址')
          .fontSize(fs(this.ts, 11))
          .fontColor(SUB)
          .width('100%')
        TextInput({ placeholder: '例如 http://10.0.2.2/v1（模拟器打本机 Dify）', text: this.base })
          .height(40)
          .fontSize(fs(this.ts, 12))
          .backgroundColor('#FBF6EC')
          .borderRadius(10)
          .border({ width: 1, color: LINE })
          .onChange((v: string): void => {
            this.base = v;
          })
        if (this.addrHint().length > 0) {
          Text(this.addrHint())
            .fontSize(fs(this.ts, 10))
            .fontColor(SUB)
            .lineHeight(fs(this.ts, 14))
            .width('100%')
        }

        Text('App Key')
          .fontSize(fs(this.ts, 11))
          .fontColor(SUB)
          .width('100%')
        TextInput({ placeholder: 'app-xxxxxxxx', text: this.apiKey })
          .type(InputType.Password)
          .height(40)
          .fontSize(fs(this.ts, 12))
          .backgroundColor('#FBF6EC')
          .borderRadius(10)
          .border({ width: 1, color: LINE })
          .onChange((v: string): void => {
            this.apiKey = v;
          })
        if (this.keyHint().length > 0) {
          Text(this.keyHint())
            .fontSize(fs(this.ts, 10))
            .fontColor(SUB)
            .lineHeight(fs(this.ts, 14))
            .width('100%')
        }

        // 自检只打一次 /v1/parameters：不调模型、不占额度，专门给换电脑的人定位「哪一段没通」
        Row({ space: 10 }) {
          Text(this.probing ? '试中…' : '测一下')
            .fontSize(fs(this.ts, 12))
            .fontColor(this.probing ? SUB : RIVER)
            .textAlign(TextAlign.Center)
            .width(88)
            .height(34)
            .borderRadius(17)
            .border({ width: 1, color: this.probing ? LINE : RIVER })
            .onClick((): void => {
              this.probeOnce();
            })
          if (this.probeMsg.length > 0) {
            Text(this.probeMsg)
              .fontSize(fs(this.ts, 10))
              .fontColor(this.probeMsg.indexOf('通了') >= 0 ? RIVER : CLAY)
              .lineHeight(fs(this.ts, 14))
              .layoutWeight(1)
          }
          Blank()
        }
        .width('100%')

        if (this.lastFail.length > 0) {
          Text('最近一次失败：' + this.lastFail + '（只给排错看，不影响使用）')
            .fontSize(fs(this.ts, 10))
            .fontColor(SUB)
            .lineHeight(fs(this.ts, 14))
            .width('100%')
        }

        Row({ space: 10 }) {
          Column({ space: 3 }) {
            Text('带上我的收藏与笔记')
              .fontSize(fs(this.ts, 13))
              .fontColor(INK)
            Text('开启后，助手会结合您的收藏与笔记作答；关闭则只依据问题本身。')
              .fontSize(fs(this.ts, 10))
              .fontColor(SUB)
              .lineHeight(fs(this.ts, 15))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.personal })
            .selectedColor(CLAY)
            .onChange((on: boolean): void => {
              this.personal = on;
              AiStore.get().setPersonal(on).catch((e: Error): void => {
                console.warn('personal toggle: ' + e.message);
              });
            })
        }
        .width('100%')

        if (this.err.length > 0) {
          Text(this.err)
            .fontSize(fs(this.ts, 11))
            .fontColor(CLAY)
            .width('100%')
        }

        Row({ space: 10 }) {
          Text('保存')
            .fontSize(fs(this.ts, 13))
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .backgroundColor(CLAY)
            .onClick((): void => {
              this.saveCfg();
            })
          Text(this.clearAsk ? '再点一次清空' : '清空对话')
            .fontSize(fs(this.ts, 12))
            .fontColor(this.clearAsk ? CLAY : SUB)
            .textAlign(TextAlign.Center)
            .width(108)
            .height(40)
            .borderRadius(20)
            .border({ width: 1, color: this.clearAsk ? CLAY : LINE })
            .onClick((): void => {
              if (!this.clearAsk) {
                this.clearAsk = true;
                return;
              }
              this.clearAsk = false;
              AiStore.get().clearChat().then((): void => {
                this.turns = [];
              });
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(12)
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .padding({ left: 14, right: 14, bottom: 16 })
  }

  @Builder
  citeChip(c: Citation) {
    Text('引 · ' + c.name)
      .fontSize(fs(this.ts, 10))
      .fontColor(c.type === 'site' ? RIVER : '#8B6B2A')
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(9)
      .backgroundColor(c.type === 'site' ? Color.Transparent : 'rgba(200,161,96,0.12)')
      .border({ width: 1, color: c.type === 'site' ? 'rgba(74,123,140,0.45)' : 'rgba(200,161,96,0.55)' })
      .margin({ right: 6, top: 6 })
      .onClick((): void => {
        if (c.type === 'site') {
          if (c.siteId.length > 0) {
            goDetail(c.siteId);
          }
        } else {
          goTopicSection(c.type);
        }
      })
  }

  @Builder
  turnView(t: ChatTurn) {
    if (t.role === 'user') {
      Row() {
        Blank()
        Text(t.text)
          .fontSize(fs(this.ts, 13))
          .fontColor(Color.White)
          .lineHeight(fs(this.ts, 20))
          .padding({ left: 12, right: 12, top: 9, bottom: 9 })
          .backgroundColor(CLAY)
          .borderRadius({ topLeft: 14, topRight: 4, bottomLeft: 14, bottomRight: 14 })
          .constraintSize({ maxWidth: '82%' })
      }
      .width('100%')
    } else {
      Column({ space: 2 }) {
        Text(t.text)
          .fontSize(fs(this.ts, 13))
          .fontColor(t.failed ? CLAY : INK)
          .lineHeight(fs(this.ts, 21))
          .copyOption(CopyOptions.LocalDevice)
        if (t.isAborted === true) {
          Text('· 回答已中断')
            .fontSize(fs(this.ts, 10))
            .fontColor(SUB)
            .margin({ top: 3 })
        }
        if (t.citations.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(t.citations, (c: Citation): void => {
              this.citeChip(c)
            }, (c: Citation): string => c.type + '|' + c.siteId + '|' + c.name)
          }
          .width('100%')
          .margin({ top: 4 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(12)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius({ topLeft: 4, topRight: 14, bottomLeft: 14, bottomRight: 14 })
      .border({ width: t.failed ? 1 : 0, color: 'rgba(166,85,61,0.35)' })
    }
  }

  @Builder
  liveBubble() {
    Column({ space: 2 }) {
      if (this.live.length > 0) {
        Text(this.live)
          .fontSize(fs(this.ts, 13))
          .fontColor(INK)
          .lineHeight(fs(this.ts, 21))
      }
      if (this.live.length === 0) {
        Text('河小导正在翻档案…')
          .fontSize(fs(this.ts, 11))
          .fontColor(SUB)
      } else if (!this.streamDone) {
        Text('▍')
          .fontSize(fs(this.ts, 12))
          .fontColor(CLAY)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius({ topLeft: 4, topRight: 14, bottomLeft: 14, bottomRight: 14 })
  }

  @Builder
  emptyState() {
    Column({ space: 12 }) {
      Stack() {
        Column()
          .width(64)
          .height(64)
          .borderRadius(32)
          .backgroundColor('#EFE3CE')
        Text('导')
          .fontSize(fs(this.ts, 28))
          .fontColor(CLAY)
          .fontWeight(FontWeight.Bold)
      }
      Text('沿河有事，问我')
        .fontSize(fs(this.ts, 16))
        .fontColor(INK)
        .fontWeight(FontWeight.Medium)
      Text('我知道站内 20 处遗址、课程和活动，也能按你的收藏推荐路线。答不了的会直说，不编年代和票价。')
        .fontSize(fs(this.ts, 11))
        .fontColor(SUB)
        .lineHeight(fs(this.ts, 18))
        .textAlign(TextAlign.Center)
        .padding({ left: 18, right: 18 })
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(TIPS, (s: string): void => {
          Text(s)
            .fontSize(fs(this.ts, 11))
            .fontColor(INK)
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .borderRadius(14)
            .backgroundColor('#FBF6EC')
            .border({ width: 1, color: LINE })
            .margin({ right: 6, top: 8 })
            .onClick((): void => {
              this.askTip(s);
            })
        }, (s: string): string => s)
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding({ top: 40 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  chatBody() {
    List({ scroller: this.scroller, space: 12 }) {
      ForEach(this.turns, (t: ChatTurn, i: number): void => {
        ListItem() {
          this.turnView(t)
        }
      }, (t: ChatTurn, i: number): string => `${t.at}-${i}-${t.role}`)

      if (this.turns.length === 0) {
        ListItem() {
          this.emptyState()
        }
      }
      if (this.liveOn) {
        ListItem() {
          this.liveBubble()
        }
      }
      if (this.err.length > 0) {
        ListItem() {
          Row({ space: 9 }) {
            Image($rawfile('assistant/mascot_think.png'))
              .width(32)
              .height(32)
              .objectFit(ImageFit.Contain)
            Column({ space: 2 }) {
              Text(errCopyOf(this.err).line)
                .fontSize(fs(this.ts, 12))
                .fontColor(INK)
                .lineHeight(fs(this.ts, 18))
                .width('100%')
              if (errCopyOf(this.err).sub.length > 0) {
                Text(errCopyOf(this.err).sub)
                  .fontSize(fs(this.ts, 9))
                  .fontColor(SUB)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            if (this.lastQ.length > 0) {
              Text('再问一次')
                .fontSize(fs(this.ts, 11))
                .fontColor(CLAY)
                .fontWeight(FontWeight.Medium)
                .padding({ left: 8, right: 4, top: 2, bottom: 2 })
                .onClick((): void => {
                  this.retry();
                })
            }
          }
          .padding(10)
          .width('100%')
          .backgroundColor('rgba(166,85,61,0.08)')
          .borderRadius(8)
          .alignItems(VerticalAlign.Center)
        }
      }
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .padding({ left: 14, right: 14, bottom: 8 })
  }

  @Builder
  inputBar() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        TextInput({ placeholder: '问遗址、器物或路线…', text: this.input })
          .layoutWeight(1)
          .height(42)
          .fontSize(fs(this.ts, 13))
          .backgroundColor('#FBF6EC')
          .borderRadius(21)
          .border({ width: 1, color: LINE })
          .enterKeyType(EnterKeyType.Send)
          .onChange((v: string): void => {
            this.input = v;
          })
          .onSubmit((): void => {
            this.send();
          })
        if (this.busy) {
          Text('停')
            .fontSize(fs(this.ts, 13))
            .fontColor(CLAY)
            .textAlign(TextAlign.Center)
            .width(42)
            .height(42)
            .borderRadius(21)
            .border({ width: 1, color: CLAY })
            .backgroundColor('#FBF6EC')
            .onClick((): void => {
              this.stop();
            })
        } else {
          Text('问')
            .fontSize(fs(this.ts, 13))
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .width(42)
            .height(42)
            .borderRadius(21)
            .backgroundColor(CLAY)
            .onClick((): void => {
              this.send();
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 10 })
    .backgroundColor($r('app.color.card_bg'))
    .border({ width: { top: 1 }, color: $r('app.color.line') })
  }

  build() {
    Column() {
      this.head()
      if (this.cfgOpen) {
        this.cfgCard()
      } else {
        this.chatBody()
        this.inputBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
