import { ChatTurn, Citation } from '../model/AiModels';
import { AiStore } from '../service/AiStore';
import { AiService, StreamHandle } from '../service/AiService';
import { AiContext } from '../service/AiContext';
import { cleanAiText, cleanPartial } from '../common/Markdown';
import { errCopyOf } from '../common/AssistantCopy';
import { INK, SUB, CLAY, RIVER, fs } from '../common/Theme';
import { goAssistant, goDetail, goTopicSection } from '../common/Nav';

const TIPS: string[] = [
  '仰韶彩陶有什么特点？',
  '二里头为什么被称为最早的中国？',
  '我收藏里哪几处值得先去？'
];

const FAB_W: number = 72;
const INSET: number = 14;
const EDGE_TUCK: number = 44;
const SCROLL_TUCK: number = 52;
const IDLE_MS: number = 3600;
const SCROLL_BACK_MS: number = 780;
const STEP: number = 6;
const TOP_KEEP: number = 96;
const GUIDE_W: number = 150;
const GUIDE_H: number = 32;
const GUIDE_MS: number = 5600;
const FOCUS_DELAY: number = 430;

@Component
export struct FloatingAssistant {
  
  @StorageLink('textScale') ts: number = 1;
  @Prop bottomGap: number = 24;
  
  @Prop tag: string = 'home';
  
  @StorageLink('assistantSheet') open: boolean = false;
  @StorageLink('assistantOwner') @Watch('onOwnerChange') ownerTag: string = 'home';
  
  @StorageLink('assistantSeen') seen: boolean = false;
  @State guide: boolean = false;
  
  @StorageLink('aiRev') @Watch('syncTurns') aiRev: number = 0;
  
  @StorageLink('fabScrollAt') @Watch('onScrollSignal') fabScrollAt: number = 0;
  @State breath: number = 1;
  @State msgs: ChatTurn[] = [];
  @State live: string = '';
  @State busy: boolean = false;
  @State input: string = '';
  @State err: string = '';
  @State lastQ: string = '';
  @State clearAsk: boolean = false;
  
  @State side: string = 'right';
  @State tx: number = 0;
  @State ty: number = 0;
  @State tuck: number = 0;
  @State stageW: number = 366;
  @State stageH: number = 809;
  private handle: StreamHandle | null = null;
  private raw: string = '';
  private curQ: string = '';
  private scroller: Scroller = new Scroller();
  private lastFollow: number = 0;
  private breathTimer: number = -1;
  private breathT0: number = 0;
  private tgtTx: number = 0;
  private tgtTy: number = 0;
  private tgtTuck: number = 0;
  private tweenTimer: number = -1;
  private idleTimer: number = -1;
  private scrollTimer: number = -1;
  private clearTimer: number = -1;
  private guideTimer: number = -1;
  
  private showing: boolean = false;
  private autoFocused: boolean = false;
  private idleTuck: boolean = false;
  private scrollHide: boolean = false;
  private dragTx: number = 0;
  private dragTy: number = 0;
  private lastDragAt: number = 0;

  aboutToAppear(): void {
    this.msgs = AiStore.get().turns.slice();
    
    let savedSide = AppStorage.get<string>('fabSide');
    if (savedSide === 'left' || savedSide === 'right') {
      this.side = savedSide;
    }
    let savedY = AppStorage.get<number>('fabY');
    if (savedY !== undefined && savedY <= 0) {
      this.ty = savedY;
    }
    this.tx = this.dockTx();
    this.tgtTx = this.tx;
    this.tgtTy = this.ty;
    this.touch();
    
    this.guide = !this.seen && this.mine();
    if (this.guide) {
      this.guideTimer = setTimeout((): void => {
        this.guide = false;
        this.guideTimer = -1;
      }, GUIDE_MS);
    }
    
    this.breathT0 = Date.now();
    this.breathTimer = setInterval((): void => {
      let phase = ((Date.now() - this.breathT0) % 3200) / 3200;
      let wave = (1 - Math.cos(phase * Math.PI * 2)) / 2;
      this.breath = 1 + 0.08 * wave;
    }, 40);
  }

  syncTurns(): void {
    if (!this.busy) {
      this.msgs = AiStore.get().turns.slice();
    }
  }

  private mine(): boolean {
    return this.ownerTag === this.tag;
  }

  private sheetOn(): boolean {
    return this.mine() && this.open;
  }

  onOwnerChange(): void {
    if (!this.mine()) {
      this.guide = false;
      return;
    }
    if (!this.seen && !this.open) {
      this.guide = true;
      if (this.guideTimer >= 0) {
        clearTimeout(this.guideTimer);
      }
      this.guideTimer = setTimeout((): void => {
        this.guide = false;
        this.guideTimer = -1;
      }, GUIDE_MS);
    }
  }

  aboutToDisappear(): void {
    if (this.guideTimer >= 0) {
      clearTimeout(this.guideTimer);
      this.guideTimer = -1;
    }
    if (this.breathTimer >= 0) {
      clearInterval(this.breathTimer);
      this.breathTimer = -1;
    }
    if (this.tweenTimer >= 0) {
      clearInterval(this.tweenTimer);
      this.tweenTimer = -1;
    }
    this.clearTimeouts();
    if (this.handle !== null) {
      this.handle.stop();
      this.handle = null;
    }
  }

  private clearTimeouts(): void {
    if (this.idleTimer >= 0) {
      clearTimeout(this.idleTimer);
      this.idleTimer = -1;
    }
    if (this.scrollTimer >= 0) {
      clearTimeout(this.scrollTimer);
      this.scrollTimer = -1;
    }
    if (this.clearTimer >= 0) {
      clearTimeout(this.clearTimer);
      this.clearTimer = -1;
    }
  }

  private dockTx(): number {
    let left = -(Math.max(120, this.stageW - 2 * INSET - FAB_W));
    return this.side === 'left' ? left : 0;
  }

  private clampTx(v: number): number {
    let min = -(Math.max(120, this.stageW - 2 * INSET - FAB_W));
    if (v < min) {
      return min;
    }
    return v > 0 ? 0 : v;
  }

  private clampTy(v: number): number {
    
    let min = TOP_KEEP - (this.stageH - this.bottomGap - FAB_W);
    if (min > 0) {
      min = 0;
    }
    if (v < min) {
      return min;
    }
    return v > 0 ? 0 : v;
  }

  private stepTo(cur: number, target: number): number {
    if (cur === target) {
      return cur;
    }
    let d = target - cur;
    if (Math.abs(d) <= STEP) {
      return target;
    }
    return cur + (d > 0 ? STEP : -STEP);
  }

  private moveTo(tx: number, ty: number, tuck: number): void {
    this.tgtTx = tx;
    this.tgtTy = ty;
    this.tgtTuck = tuck;
    if (this.tweenTimer >= 0) {
      return;
    }
    this.tweenTimer = setInterval((): void => {
      let nx = this.stepTo(this.tx, this.tgtTx);
      let ny = this.stepTo(this.ty, this.tgtTy);
      let nt = this.stepTo(this.tuck, this.tgtTuck);
      let moving = nx !== this.tx || ny !== this.ty || nt !== this.tuck;
      this.tx = nx;
      this.ty = ny;
      this.tuck = nt;
      if (!moving && this.tweenTimer >= 0) {
        clearInterval(this.tweenTimer);
        this.tweenTimer = -1;
      }
    }, 22);
  }

  private tuckTarget(): number {
    if (this.sheetOn() || this.busy) {
      return 0;
    }
    if (this.scrollHide) {
      return SCROLL_TUCK;
    }
    return this.idleTuck ? EDGE_TUCK : 0;
  }

  private refreshTuck(): void {
    this.moveTo(this.dockTx(), this.ty, this.tuckTarget());
  }

  private touch(): void {
    this.idleTuck = false;
    if (this.idleTimer >= 0) {
      clearTimeout(this.idleTimer);
      this.idleTimer = -1;
    }
    this.refreshTuck();
    this.idleTimer = setTimeout((): void => {
      this.idleTuck = true;
      this.refreshTuck();
    }, IDLE_MS);
  }

  onScrollSignal(): void {
    this.scrollHide = true;
    if (this.scrollTimer >= 0) {
      clearTimeout(this.scrollTimer);
    }
    this.scrollTimer = setTimeout((): void => {
      this.scrollHide = false;
      this.scrollTimer = -1;
      this.refreshTuck();
    }, SCROLL_BACK_MS);
    this.refreshTuck();
  }

  private fabDragStart(): void {
    this.dragTx = this.tx;
    this.dragTy = this.ty;
    this.tgtTx = this.tx;
    this.tgtTy = this.ty;
    this.tgtTuck = this.tuck;
    this.touch();
  }

  private fabDragMove(dx: number, dy: number): void {
    this.tx = this.clampTx(this.dragTx + dx);
    this.ty = this.clampTy(this.dragTy + dy);
    this.tgtTx = this.tx;
    this.tgtTy = this.ty;
  }

  private fabDragEnd(): void {
    this.lastDragAt = Date.now();
    let center = this.stageW - INSET - FAB_W / 2 + this.tx;
    this.side = center < this.stageW / 2 ? 'left' : 'right';
    this.ty = this.clampTy(this.ty);
    AppStorage.setOrCreate('fabSide', this.side);
    AppStorage.setOrCreate('fabY', this.ty);
    
    this.idleTuck = false;
    this.moveTo(this.dockTx(), this.ty, 0);
    if (this.idleTimer >= 0) {
      clearTimeout(this.idleTimer);
    }
    this.idleTimer = setTimeout((): void => {
      this.idleTuck = true;
      this.refreshTuck();
    }, IDLE_MS);
  }

  private fabAlpha(): number {
    let a = this.tuck > 0 ? Math.max(0.5, 1 - this.tuck / 60) : 1;
    return this.sheetOn() ? a * 0.55 : a;
  }

  private fabShiftX(): number {
    return this.tx + (this.side === 'left' ? -this.tuck : this.tuck);
  }

  private headImg(): Resource {
    if (this.busy) {
      return $rawfile('assistant/mascot_think.png');
    }
    if (this.msgs.length > 0) {
      return $rawfile('assistant/mascot_happy.png');
    }
    return $rawfile('assistant/mascot_wave.png');
  }

  private follow(force: boolean): void {
    let now = Date.now();
    if (!force && now - this.lastFollow < 150) {
      return;
    }
    this.lastFollow = now;
    setTimeout((): void => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 40);
  }

  private sendInput(): void {
    let q = this.input.trim();
    if (q.length === 0 || this.busy) {
      return;
    }
    if (!AiStore.get().configured()) {
      this.err = '先在设置里填好 Dify 地址和 App Key';
      return;
    }
    this.input = '';
    this.run(q, true);
  }

  private sendTip(tip: string): void {
    if (this.busy) {
      return;
    }
    if (!AiStore.get().configured()) {
      this.err = '先在设置里填好 Dify 地址和 App Key';
      return;
    }
    this.input = '';
    this.run(tip, true);
  }

  private run(q: string, pushUser: boolean): void {
    this.err = '';
    this.lastQ = '';
    this.curQ = q;
    this.live = '';
    this.raw = '';
    if (pushUser) {
      this.attach({
        role: 'user', text: q, at: Date.now(), citations: [], failed: false, isAborted: false
      });
    }
    this.busy = true;
    this.touch();
    this.follow(true);
    this.handle = AiService.get().start(q, AiContext.build(q), {
      onChunk: (raw: string): void => {
        this.raw = raw;
        this.live = cleanPartial(raw);
        this.follow(false);
      },
      onDone: (citations: Citation[], aborted: boolean): void => {
        this.handle = null;
        this.finish(citations, aborted);
      },
      onError: (msg: string): void => {
        this.handle = null;
        this.busy = false;
        this.live = '';
        this.err = msg;
        this.lastQ = q;
      }
    });
  }

  private attach(t: ChatTurn): void {
    this.msgs = this.msgs.concat([t]);
    AiStore.get().pushTurn(t);
  }

  private finish(citations: Citation[], aborted: boolean): void {
    this.busy = false;
    this.touch();
    this.live = '';
    let text = cleanAiText(this.raw);
    this.raw = '';
    if (text.length > 0) {
      let t: ChatTurn = {
        role: 'ai', text: text, at: Date.now(), citations: citations,
        failed: false, isAborted: aborted
      };
      this.msgs = this.msgs.concat([t]);
      AiStore.get().pushTurn(t);
    } else if (aborted) {
      
      this.err = '回答已中断';
      this.lastQ = this.curQ;
    } else {
      
      this.err = AiService.ERR_EMPTY;
      this.lastQ = this.curQ;
    }
    this.follow(true);
  }

  private stop(): void {
    if (this.handle !== null) {
      this.handle.stop();
      return;
    }
    this.busy = false;
    this.live = '';
  }

  private goFull(): void {
    
    if (this.handle !== null) {
      this.handle.stop();
    }
    this.open = false;
    setTimeout((): void => {
      goAssistant();
    }, 80);
  }

  private openSheet(): void {
    
    if (!this.mine()) {
      return;
    }
    this.open = true;
    this.guide = false;
    
    if (!this.seen) {
      this.seen = true;
      AiStore.get().markAskSeen();
    }
    this.touch();
    
    setTimeout((): void => {
      this.follow(true);
    }, 320);
    
    if (!this.autoFocused) {
      this.autoFocused = true;
      this.tryFocus(3);
    }
  }

  private tryFocus(left: number): void {
    setTimeout((): void => {
      let ok = focusControl.requestFocus('fabInput');
      console.info('fabInput focus=' + ok + ' left=' + left);
      if (!ok && left > 0) {
        this.tryFocus(left - 1);
      }
    }, FOCUS_DELAY);
  }

  private clearHistory(): void {
    if (this.handle !== null) {
      this.handle.stop();
      this.handle = null;
    }
    if (this.clearTimer >= 0) {
      clearTimeout(this.clearTimer);
      this.clearTimer = -1;
    }
    this.clearAsk = false;
    this.busy = false;
    this.live = '';
    this.raw = '';
    this.curQ = '';
    this.lastQ = '';
    this.err = '';
    this.msgs = [];
    
    AiStore.get().clearChat().catch((e: Error): void => {
      console.warn('clear chat: ' + e.message);
    });
  }

  @Builder
  fab() {
    Stack({ alignContent: Alignment.Center }) {
      Circle()
        .width(64)
        .height(64)
        .fill('rgba(200,161,96,0.20)')
        .scale({ x: this.breath, y: this.breath })
      Image($rawfile('assistant/mascot_wave.png'))
        .width(58)
        .height(58)
        .objectFit(ImageFit.Contain)
        .scale({ x: 1 + (this.breath - 1) * 0.4, y: 1 + (this.breath - 1) * 0.4 })
    }
    .width(72)
    .height(72)
    .borderRadius(36)
    .backgroundColor($r('app.color.card_bg'))
    .shadow({ radius: 12, color: 'rgba(166,85,61,0.26)', offsetY: 4 })
    .margin({ right: INSET, bottom: this.bottomGap })
    
    .translate({ x: this.fabShiftX(), y: this.ty })
    
    .scale(this.sheetOn() ? { x: 0.86, y: 0.86 } : { x: 1, y: 1 })
    .opacity(this.fabAlpha())
    
    .hitTestBehavior(HitTestMode.Block)
    .gesture(
      PanGesture({ distance: 6, direction: PanDirection.All })
        .onActionStart((event: GestureEvent): void => {
          this.fabDragStart();
        })
        .onActionUpdate((event: GestureEvent): void => {
          this.fabDragMove(event.offsetX, event.offsetY);
        })
        .onActionEnd((event: GestureEvent): void => {
          this.fabDragEnd();
        })
    )
    .onClick((): void => {
      
      if (Date.now() - this.lastDragAt < 260) {
        return;
      }
      this.openSheet();
    })
    
    .bindSheet(this.sheetOn(), this.sheetView(), {
      height: 500,
      dragBar: false,
      showClose: false,
      backgroundColor: $r('app.color.card_bg'),
      keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE,
      onAppear: (): void => {
        this.showing = true;
      },
      onDisappear: (): void => {
        
        if (this.showing) {
          this.showing = false;
          if (this.mine()) {
            this.open = false;
          }
          this.refreshTuck();
        }
      }
    })
  }

  @Builder
  head() {
    Row({ space: 10 }) {
      Image(this.headImg())
        .width(40)
        .height(40)
        .objectFit(ImageFit.Contain)
      Column({ space: 2 }) {
        Text('河小导')
          .fontSize(fs(this.ts, 15))
          .fontColor(INK)
          .fontWeight(FontWeight.Medium)
        Text(this.busy ? '正在翻档案…' : '黄河续响平台 · 文化向导')
          .fontSize(fs(this.ts, 10))
          .fontColor(SUB)
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
      Text(this.msgs.length === 0 ? '已清空' : (this.clearAsk ? '确认清空' : '清空历史'))
        .fontSize(fs(this.ts, 11))
        .fontColor(this.msgs.length === 0 ? '#C4BAAC' : (this.clearAsk ? CLAY : SUB))
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(12)
        .border({
          width: 1,
          color: this.msgs.length === 0 ? 'rgba(122,110,98,0.16)'
            : (this.clearAsk ? 'rgba(166,85,61,0.55)' : 'rgba(122,110,98,0.30)')
        })
        .onClick((): void => {
          if (this.msgs.length === 0 && !this.busy) {
            this.err = '';
            return;
          }
          if (!this.clearAsk) {
            this.clearAsk = true;
            if (this.clearTimer >= 0) {
              clearTimeout(this.clearTimer);
            }
            
            this.clearTimer = setTimeout((): void => {
              this.clearAsk = false;
              this.clearTimer = -1;
            }, 4000);
            return;
          }
          this.clearHistory();
        })
      Text('去全屏 ›')
        .fontSize(fs(this.ts, 11))
        .fontColor(RIVER)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(12)
        .border({ width: 1, color: 'rgba(74,123,140,0.40)' })
        .onClick((): void => {
          this.goFull();
        })
      Text('×')
        .fontSize(fs(this.ts, 18))
        .fontColor(SUB)
        .padding({ left: 6, right: 2 })
        .onClick((): void => {
          this.open = false;
        })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  tipChip(tip: string) {
    Text(tip)
      .fontSize(fs(this.ts, 11))
      .fontColor(RIVER)
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .borderRadius(14)
      .border({ width: 1, color: 'rgba(74,123,140,0.40)' })
      .margin({ right: 6, top: 6 })
      .onClick((): void => {
        this.sendTip(tip);
      })
  }

  @Builder
  emptyState() {
    Column({ space: 8 }) {
      Image($rawfile('assistant/mascot_think.png'))
        .width(84)
        .height(84)
        .objectFit(ImageFit.Contain)
      Text('问我沿线的事')
        .fontSize(fs(this.ts, 15))
        .fontColor(INK)
        .fontWeight(FontWeight.Medium)
      Text('遗址、器物、路线，都可以直接问')
        .fontSize(fs(this.ts, 11))
        .fontColor(SUB)
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(TIPS, (tip: string): void => {
          this.tipChip(tip)
        }, (tip: string): string => tip)
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 6, right: 6 })
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
      .margin({ right: 6, top: 4 })
      .onClick((): void => {
        
        if ((c.type === 'site' && c.siteId.length === 0) ||
          (c.type !== 'site' && c.type !== 'goods' && c.type !== 'courses' && c.type !== 'events')) {
          return;
        }
        this.open = false;
        setTimeout((): void => {
          if (c.type === 'site') {
            goDetail(c.siteId);
          } else {
            goTopicSection(c.type);
          }
        }, 60);
      })
  }

  @Builder
  msgView(t: ChatTurn) {
    if (t.role === 'user') {
      Row() {
        Blank()
        Text(t.text)
          .fontSize(fs(this.ts, 13))
          .fontColor('#FFFFFF')
          .lineHeight(fs(this.ts, 19))
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(CLAY)
          .borderRadius({ topLeft: 12, topRight: 4, bottomLeft: 12, bottomRight: 12 })
          .constraintSize({ maxWidth: '80%' })
      }
      .width('100%')
    } else {
      Column({ space: 5 }) {
        Text(t.text)
          .fontSize(fs(this.ts, 13))
          .fontColor(INK)
          .lineHeight(fs(this.ts, 20))
          .width('100%')
        if (t.isAborted === true) {
          Text('· 回答已中断')
            .fontSize(fs(this.ts, 10))
            .fontColor(SUB)
            .width('100%')
        }
        if (t.citations.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(t.citations, (c: Citation): void => {
              this.citeChip(c)
            }, (c: Citation): string => c.type + '|' + c.siteId + '|' + c.name)
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.page_bg'))
      .borderRadius(12)
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  liveBubble() {
    Column() {
      Text(this.live.length > 0 ? this.live + '▍' : '河小导正在翻档案…')
        .fontSize(fs(this.ts, 13))
        .fontColor(INK)
        .lineHeight(fs(this.ts, 20))
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.page_bg'))
    .borderRadius(12)
  }

  @Builder
  thread() {
    Scroll(this.scroller) {
      Column({ space: 10 }) {
        ForEach(this.msgs, (t: ChatTurn): void => {
          this.msgView(t)
        }, (t: ChatTurn): string => `${t.at}-${t.role}`)
        if (this.busy) {
          this.liveBubble()
        }
      }
      .width('100%')
      .padding({ top: 2, bottom: 6 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }

  @Builder
  errView() {
    Row({ space: 9 }) {
      Image($rawfile('assistant/mascot_think.png'))
        .width(30)
        .height(30)
        .objectFit(ImageFit.Contain)
      Column({ space: 2 }) {
        Text(errCopyOf(this.err).line)
          .fontSize(fs(this.ts, 11))
          .fontColor(INK)
          .lineHeight(fs(this.ts, 17))
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
          .fontColor(RIVER)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(12)
          .border({ width: 1, color: 'rgba(74,123,140,0.40)' })
          .onClick((): void => {
            let q = this.lastQ;
            this.lastQ = '';
            this.run(q, false);
          })
      } else {
        Text('去设置 ›')
          .fontSize(fs(this.ts, 11))
          .fontColor(RIVER)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(12)
          .border({ width: 1, color: 'rgba(74,123,140,0.40)' })
          .onClick((): void => {
            this.open = false;
            setTimeout((): void => {
              goAssistant();
            }, 60);
          })
      }
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .backgroundColor('rgba(166,85,61,0.07)')
    .borderRadius(10)
    .margin({ top: 6 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  inputBar() {
    Row({ space: 8 }) {
      TextInput({ text: this.input, placeholder: '问遗址、器物或路线…' })
        .key('fabInput')
        .layoutWeight(1)
        .height(42)
        .borderRadius(21)
        .backgroundColor($r('app.color.page_bg'))
        .fontSize(fs(this.ts, 13))
        .fontColor(INK)
        .placeholderColor(SUB)
        .padding({ left: 14, right: 14 })
        .enterKeyType(EnterKeyType.Send)
        .onChange((v: string): void => {
          this.input = v;
        })
        .onSubmit((): void => {
          this.sendInput();
        })
      Text(this.busy ? '停' : '问')
        .width(42)
        .height(42)
        .textAlign(TextAlign.Center)
        .fontSize(fs(this.ts, 13))
        .fontColor(this.busy ? CLAY : '#FFFFFF')
        .backgroundColor(this.busy ? $r('app.color.page_bg') : CLAY)
        .borderRadius(21)
        .border({ width: this.busy ? 1 : 0, color: CLAY })
        .onClick((): void => {
          if (this.busy) {
            this.stop();
          } else {
            this.sendInput();
          }
        })
    }
    .width('100%')
    .margin({ top: 8, bottom: 2 })
  }

  @Builder
  sheetView() {
    Column() {
      Column()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor('#D9CDB6')
        .margin({ top: 8, bottom: 2 })
      this.head()
      Divider()
        .strokeWidth(1)
        .color($r('app.color.line'))
      if (this.msgs.length === 0 && !this.busy) {
        this.emptyState()
      } else {
        this.thread()
      }
      if (this.err.length > 0) {
        this.errView()
      }
      this.inputBar()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 14, bottom: 8 })
    .backgroundColor($r('app.color.card_bg'))
    
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, distance: 24 })
        .onActionEnd((event: GestureEvent): void => {
          if (event.offsetY > 60) {
            this.open = false;
          }
        })
    )
  }

  @Builder
  guideBubble() {
    Text('有不懂的随时问我哦')
      .fontSize(fs(this.ts, 12))
      .fontColor(INK)
      .textAlign(TextAlign.Center)
      .width(GUIDE_W)
      .height(GUIDE_H)
      .borderRadius(16)
      .backgroundColor($r('app.color.card_bg'))
      .border({ width: 1, color: 'rgba(166,85,61,0.35)' })
      .shadow({ radius: 8, color: 'rgba(43,38,34,0.16)', offsetY: 2 })
      .position(this.guidePos())
      .hitTestBehavior(HitTestMode.Block)
      .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
      .onClick((): void => {
        this.openSheet();
      })
  }

  private guidePos(): Position {
    let ballX = this.stageW - INSET - FAB_W + this.fabShiftX();
    let x = this.side === 'left' ? ballX + 8 : ballX + FAB_W - GUIDE_W - 4;
    let y = this.stageH - this.bottomGap - FAB_W + this.ty - GUIDE_H - 8;
    return { x: x, y: y };
  }

  build() {
    
    Stack({ alignContent: Alignment.BottomEnd }) {
      this.fab()
      if (this.guide && this.mine() && !this.sheetOn()) {
        this.guideBubble()
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .onAreaChange((oldValue: Area, newValue: Area): void => {
      let w = newValue.width;
      let h = newValue.height;
      if (typeof w === 'number') {
        this.stageW = w;
      }
      if (typeof h === 'number') {
        this.stageH = h;
      }
      
      this.moveTo(this.dockTx(), this.clampTy(this.ty), this.tuckTarget());
    })
  }
}
