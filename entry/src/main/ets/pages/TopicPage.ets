import { router, promptAction } from '@kit.ArkUI';
import { SiteRepo } from '../service/SiteRepo';
import { MemoryStore } from '../service/MemoryStore';
import { SiteInfo, TopicRec } from '../model/Models';
import { fs, ERAS, INK, SUB, LOESS, CLAY, coverRes } from '../common/Theme';
import { goDetail } from '../common/Nav';
import { SiteCard } from '../view/SiteCard';

interface Pt {
  x: number;
  y: number;
}

interface NodeView {
  id: string;
  name: string;
  era: string;
  cover: string;
  x: number;
  y: number;
  r: number;
}

interface Rel {
  aid: string;
  bid: string;
  aName: string;
  bName: string;
  kind: string;
  label: string;
}

interface ChipArg {
  idx: number;
  title: string;
}

@Entry
@Component
struct TopicPage {
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('dataRev') @Watch('redraw') rev: number = 0;
  @State scope: string = '';
  @State netMode: boolean = true;
  @State creating: boolean = false;
  @State newName: string = '';
  @State editMembers: boolean = false;
  @State nodesView: NodeView[] = [];
  @State rels: Rel[] = [];
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private painted: boolean = false;

  redraw(): void {
    if (this.netMode) {
      this.paint();
    }
  }

  paint(): void {
    if (!this.painted) {
      return;
    }
    this.draw();
  }

  topics(): TopicRec[] {
    return MemoryStore.get().topicsActive();
  }

  title(): string {
    if (this.scope.length === 0) {
      return '知识网络';
    }
    let t = MemoryStore.get().topicOf(this.scope);
    return t === undefined ? '知识网络' : t.name;
  }

  nodes(): SiteInfo[] {
    let ns: SiteInfo[] = [];
    if (this.scope.length === 0) {
      ns = SiteRepo.get().sites.slice();
    } else {
      let t = MemoryStore.get().topicOf(this.scope);
      if (t === undefined) {
        ns = SiteRepo.get().sites.slice();
      } else {
        for (let id of t.siteIds) {
          let s = SiteRepo.get().byId(id);
          if (s !== undefined) {
            ns.push(s);
          }
        }
      }
    }
    ns.sort((a: SiteInfo, b: SiteInfo): number => {
      let ia = ERAS.indexOf(a.eras[0]);
      let ib = ERAS.indexOf(b.eras[0]);
      if (ia < 0) {
        ia = 99;
      }
      if (ib < 0) {
        ib = 99;
      }
      if (ia !== ib) {
        return ia - ib;
      }
      return a.id < b.id ? -1 : 1;
    });
    return ns;
  }

  short(s: SiteInfo): string {
    let n = s.name.replace('遗址', '').replace('古墓群', '墓群').replace('墓地', '');
    return n.length > 5 ? n.substring(0, 5) : n;
  }

  sharedEra(a: SiteInfo, b: SiteInfo): string {
    for (let e of a.eras) {
      if (b.eras.indexOf(e) >= 0) {
        return e;
      }
    }
    return '';
  }

  sharedTag(a: SiteInfo, b: SiteInfo): string {
    let fa = MemoryStore.get().favOf(a.id);
    let fb = MemoryStore.get().favOf(b.id);
    if (fa === undefined || fb === undefined) {
      return '';
    }
    for (let t of fa.tagIds) {
      if (fb.tagIds.indexOf(t) >= 0) {
        return MemoryStore.get().tagName(t);
      }
    }
    return '';
  }

  relOf(a: SiteInfo, b: SiteInfo): Rel | undefined {
    let era = this.sharedEra(a, b);
    if (era.length > 0) {
      return { aid: a.id, bid: b.id, aName: this.short(a), bName: this.short(b),
        kind: 'era', label: `同属${era}` };
    }
    if (a.city === b.city) {
      return { aid: a.id, bid: b.id, aName: this.short(a), bName: this.short(b),
        kind: 'city', label: `同在${a.city}` };
    }
    let tag = this.sharedTag(a, b);
    if (tag.length > 0) {
      return { aid: a.id, bid: b.id, aName: this.short(a), bName: this.short(b),
        kind: 'tag', label: `同标${tag}` };
    }
    return undefined;
  }

  colorOf(kind: string): string {
    if (kind === 'era') {
      return LOESS;
    }
    if (kind === 'city') {
      return CLAY;
    }
    return SUB;
  }

  qPoint(p0: Pt, pc: Pt, p1: Pt, t: number): Pt {
    let u = 1 - t;
    return { x: u * u * p0.x + 2 * u * t * pc.x + t * t * p1.x,
      y: u * u * p0.y + 2 * u * t * pc.y + t * t * p1.y };
  }

  drawBridge(c: CanvasRenderingContext2D, p0: Pt, p1: Pt, ctr: Pt, color: string,
    width: number, dashed: boolean): void {
    let mid: Pt = { x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2 };
    let pc: Pt = { x: mid.x + (ctr.x - mid.x) * 0.28, y: mid.y + (ctr.y - mid.y) * 0.28 };
    c.strokeStyle = color;
    c.lineWidth = width;
    if (dashed) {
      c.setLineDash([6, 4]);
    }
    c.beginPath();
    c.moveTo(p0.x, p0.y);
    c.quadraticCurveTo(pc.x, pc.y, p1.x, p1.y);
    c.stroke();
    c.setLineDash([]);
    if (dashed) {
      return;
    }
    let dist = Math.sqrt((p1.x - p0.x) * (p1.x - p0.x) + (p1.y - p0.y) * (p1.y - p0.y));
    let n = Math.max(3, Math.floor(dist / 30));
    c.lineWidth = 1;
    for (let i = 1; i <= n; i++) {
      let t = i / (n + 1);
      let p = this.qPoint(p0, pc, p1, t);
      let dx = 2 * (1 - t) * (pc.x - p0.x) + 2 * t * (p1.x - pc.x);
      let dy = 2 * (1 - t) * (pc.y - p0.y) + 2 * t * (p1.y - pc.y);
      let len = Math.sqrt(dx * dx + dy * dy);
      if (len < 0.01) {
        continue;
      }
      let nx = -dy / len;
      let ny = dx / len;
      c.beginPath();
      c.moveTo(p.x - nx * 5, p.y - ny * 5);
      c.lineTo(p.x + nx * 5, p.y + ny * 5);
      c.stroke();
    }
  }

  draw(): void {
    let c = this.ctx;
    let w = c.width;
    let h = c.height;
    c.clearRect(0, 0, w, h);
    this.rels = [];
    this.nodesView = [];
    let ns = this.nodes();
    if (ns.length === 0 || w <= 0) {
      return;
    }
    let ctr: Pt = { x: w / 2, y: h / 2 };
    let r = ns.length <= 4 ? 36 : ns.length <= 9 ? 30 : ns.length <= 14 ? 24 : 19;
    let rx = w / 2 - r - 22;
    let ry = h / 2 - r - 26;
    let pts: Pt[] = [];
    if (ns.length === 1) {
      pts.push({ x: ctr.x, y: ctr.y });
    } else {
      for (let i = 0; i < ns.length; i++) {
        let a = -Math.PI / 2 + Math.PI * 2 * i / ns.length;
        pts.push({ x: ctr.x + rx * Math.cos(a), y: ctr.y + ry * Math.sin(a) });
      }
      c.strokeStyle = '#EADFC6';
      c.lineWidth = 1.2;
      c.setLineDash([4, 6]);
      c.beginPath();
      c.ellipse(ctr.x, ctr.y, rx, ry, 0, 0, Math.PI * 2);
      c.stroke();
      c.setLineDash([]);
    }

    let rels: Rel[] = [];
    for (let i = 0; i < ns.length; i++) {
      for (let j = i + 1; j < ns.length; j++) {
        let rel = this.relOf(ns[i], ns[j]);
        if (rel !== undefined) {
          rels.push(rel);
        }
      }
    }
    for (let rel of rels) {
      let i = ns.findIndex((s: SiteInfo): boolean => s.id === rel.aid);
      let j = ns.findIndex((s: SiteInfo): boolean => s.id === rel.bid);
      if (i < 0 || j < 0) {
        continue;
      }
      this.drawBridge(c, pts[i], pts[j], ctr, this.colorOf(rel.kind),
        rel.kind === 'era' ? 2 : 1.4, rel.kind === 'tag');
    }
    this.rels = rels;

    let views: NodeView[] = [];
    for (let i = 0; i < ns.length; i++) {
      views.push({ id: ns[i].id, name: this.short(ns[i]), era: ns[i].eras.join('/'),
        cover: ns[i].cover, x: pts[i].x, y: pts[i].y, r: r });
    }
    this.nodesView = views;
  }

  pick(scope: string): void {
    this.scope = scope;
    this.netMode = true;
    setTimeout((): void => {
      this.paint();
    }, 40);
  }

  selIds(): string[] {
    let t = MemoryStore.get().topicOf(this.scope);
    return t === undefined ? [] : t.siteIds;
  }

  async create(): Promise<void> {
    let name = this.newName.trim();
    if (name.length === 0) {
      return;
    }
    await MemoryStore.get().addTopic(name);
    this.newName = '';
    this.creating = false;
    let ts = MemoryStore.get().topicsActive();
    let last = ts[ts.length - 1];
    if (last !== undefined) {
      this.scope = last.id;
      this.netMode = true;
      this.editMembers = true;
      setTimeout((): void => {
        this.paint();
      }, 60);
    }
  }

  @Builder
  chip(a: ChipArg) {
    Text(a.title)
      .fontSize(fs(this.ts, 12))
      .fontColor(this.curIdx() === a.idx ? '#FFFFFF' : SUB)
      .backgroundColor(this.curIdx() === a.idx ? CLAY : '#F1E7D5')
      .borderRadius(13)
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .onClick((): void => {
        this.pick(a.idx === 0 ? '' : (this.topics()[a.idx - 1]?.id ?? ''));
      })
  }

  curIdx(): number {
    if (this.scope.length === 0) {
      return 0;
    }
    let ts = this.topics();
    for (let i = 0; i < ts.length; i++) {
      if (ts[i].id === this.scope) {
        return i + 1;
      }
    }
    return 0;
  }

  @Builder
  legend(color: string, label: string, dash: boolean) {
    Row({ space: 4 }) {
      Line().width(18).height(2).startPoint([0, 1]).endPoint([18, 1])
        .stroke(color).strokeDashArray(dash ? [4, 4] : [])
      Text(label).fontSize(fs(this.ts, 11)).fontColor(SUB)
    }
  }

  @Builder
  photoNode(nv: NodeView) {
    Column() {
      Image(coverRes(nv.cover))
        .width(nv.r * 2)
        .height(nv.r * 2)
        .borderRadius(nv.r)
        .objectFit(ImageFit.Cover)
        .border({ width: 1.5, color: LOESS })
        .backgroundColor('#EDE3D2')
      Text(nv.name)
        .fontSize(fs(this.ts, 11))
        .fontColor(INK)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })
      Text(nv.era)
        .fontSize(fs(this.ts, 9))
        .fontColor(SUB)
        .maxLines(1)
    }
    .width(84)
    .alignItems(HorizontalAlign.Center)
    .position({ x: nv.x - 42, y: nv.y - nv.r })
    .onClick((): void => {
      goDetail(nv.id);
    })
  }

  @Builder
  relRow(rel: Rel) {
    Row({ space: 8 }) {
      Column()
        .width(3)
        .height(18)
        .backgroundColor(this.colorOf(rel.kind))
        .borderRadius(2)
      Text(`${rel.aName} 与 ${rel.bName}`)
        .fontSize(fs(this.ts, 14))
        .fontColor(INK)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(rel.label)
        .fontSize(fs(this.ts, 12))
        .fontColor(this.colorOf(rel.kind))
    }
    .width('100%')
    .padding({ left: 10, right: 12, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(8)
    .onClick((): void => {
      goDetail(rel.aid);
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row({ space: 10 }) {
          Text('‹ 返回').fontSize(fs(this.ts, 15)).fontColor(CLAY)
            .onClick((): void => {
              router.back();
            })
          Text(this.title()).fontSize(fs(this.ts, 18)).fontColor(INK).fontWeight(FontWeight.Bold).layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.netMode ? '看列表' : '看网络')
            .fontSize(fs(this.ts, 13)).fontColor(CLAY)
            .onClick((): void => {
              this.netMode = !this.netMode;
              if (this.netMode) {
                setTimeout((): void => {
                  this.paint();
                }, 60);
              }
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 6 })

        Row({ space: 6 }) {
          Scroll() {
            Row({ space: 8 }) {
              this.chip({ idx: 0, title: '整条河' })
              ForEach(this.topics(), (t: TopicRec, i: number): void => {
                this.chip({ idx: i + 1, title: t.name })
              }, (t: TopicRec): string => t.id)
            }
            .padding({ left: 14, right: 8 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          Text(this.creating ? '收起' : '＋ 新主题')
            .fontSize(fs(this.ts, 12)).fontColor(LOESS)
            .border({ width: 1, color: '#E0D2B4' })
            .borderRadius(13)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .margin({ right: 14 })
            .onClick((): void => {
              this.creating = !this.creating;
            })
        }
        .width('100%')
        .padding({ bottom: 6 })

        if (this.creating) {
          Row({ space: 8 }) {
            TextInput({ text: this.newName, placeholder: '比如：夏商文明探访' })
              .height(36).fontSize(fs(this.ts, 13)).layoutWeight(1)
              .onChange((v: string): void => {
                this.newName = v;
              })
            Button('建')
              .height(36).fontSize(fs(this.ts, 13)).backgroundColor(LOESS)
              .onClick(async (): Promise<void> => {
                await this.create();
              })
          }
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 6 })
        }

        if (this.netMode) {
          Stack({ alignContent: Alignment.TopStart }) {
            Canvas(this.ctx)
              .width('100%')
              .height('100%')
              .onReady((): void => {
                this.painted = true;
                this.draw();
              })
            ForEach(this.nodesView, (nv: NodeView): void => {
              this.photoNode(nv)
            }, (nv: NodeView): string =>
              `${nv.id}_${Math.round(nv.x)}_${Math.round(nv.y)}_${nv.r}_${this.scope}`)
            if (this.painted && this.nodesView.length === 0) {
              Column({ space: 8 }) {
                Text('这个主题还没有成员').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
                Text('勾几处遗址进来，桥和关系清单就出来了').fontSize(fs(this.ts, 11)).fontColor(SUB)
                Button('去选成员')
                  .height(34).fontSize(fs(this.ts, 13)).backgroundColor(CLAY)
                  .onClick((): void => {
                    this.editMembers = true;
                  })
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }
          }
          .width('100%')
          .height(330)
          .margin({ left: 10, right: 10 })
          .borderRadius(12)
          .backgroundColor($r('app.color.card_bg'))
          .clip(true)

          Row({ space: 14 }) {
            this.legend(LOESS, '同年代架桥', false)
            this.legend(CLAY, '同城市架桥', false)
            this.legend(SUB, '同标签虚桥', true)
            Blank()
            Text('点节点看详情').fontSize(fs(this.ts, 10)).fontColor(SUB)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 4 })

          Row() {
            Text('关系清单').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Bold)
            Text(`${this.rels.length} 条`).fontSize(fs(this.ts, 12)).fontColor(SUB).margin({ left: 6 })
            Blank()
            Text('点节点看详情').fontSize(fs(this.ts, 11)).fontColor(CLAY)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })

          List({ space: 8 }) {
            ForEach(this.rels, (rel: Rel): void => {
              ListItem() {
                this.relRow(rel)
              }
            }, (rel: Rel): string => `${rel.aid}_${rel.bid}_${rel.kind}`)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ left: 14, right: 14 })
        } else {
          List({ space: 8 }) {
            ForEach(this.nodes(), (s: SiteInfo): void => {
              ListItem() {
                SiteCard({ site: s })
              }
            }, (s: SiteInfo): string => s.id)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ left: 14, right: 14 })
        }

        Row({ space: 10 }) {
          Text(`${this.netMode ? this.nodesView.length : this.nodes().length} 个节点 · ${this.rels.length} 座桥，椭圆是年代顺序的时间轨道`)
            .fontSize(fs(this.ts, 11)).fontColor(SUB).layoutWeight(1)
          if (this.scope.length > 0) {
            Text('编辑成员').fontSize(fs(this.ts, 13)).fontColor(CLAY)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .border({ width: 1, color: '#E0CDBB' })
              .borderRadius(16)
              .onClick((): void => {
                this.editMembers = true;
              })
            Text('删主题').fontSize(fs(this.ts, 13)).fontColor(SUB)
              .onClick(async (): Promise<void> => {
                let name = this.title();
                await MemoryStore.get().deleteTopic(this.scope);
                this.scope = '';
                this.editMembers = false;
                promptAction.showToast({ message: `主题「${name}」已删除` });
                setTimeout((): void => {
                  this.paint();
                }, 60);
              })
          } else {
            Text('把常一起看的遗址存成主题').fontSize(fs(this.ts, 11)).fontColor(SUB)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 14 })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.editMembers) {
        Column()
          .width('100%').height('100%')
          .backgroundColor('#66000000')
          .onClick((): void => {
            this.editMembers = false;
          })
        Column({ space: 8 }) {
          Row() {
            Text('勾选要放进主题的遗址').fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Medium)
              .layoutWeight(1)
            Text(`已选 ${this.selIds().length} 处`).fontSize(fs(this.ts, 12)).fontColor(SUB)
          }
          .width('100%')
          List() {
            ForEach(SiteRepo.get().sites, (s: SiteInfo): void => {
              ListItem() {
                Row() {
                  Text(s.name).fontSize(fs(this.ts, 14)).fontColor(INK).layoutWeight(1)
                  Text(s.city).fontSize(fs(this.ts, 11)).fontColor(SUB)
                  Checkbox()
                    .select(this.selIds().includes(s.id))
                    .selectedColor(CLAY)
                    .onChange((on: boolean): void => {
                      let t = MemoryStore.get().topicOf(this.scope);
                      if (t !== undefined && (t.siteIds.includes(s.id) !== on)) {
                        MemoryStore.get().toggleTopicSite(t.id, s.id);
                      }
                    })
                }
                .width('100%')
                .padding({ top: 6, bottom: 6 })
              }
            }, (s: SiteInfo): string => `${s.id}_${this.selIds().includes(s.id) ? 1 : 0}`)
          }
          .height(300)
          .scrollBar(BarState.Auto)
          Button('完成')
            .backgroundColor(LOESS)
            .onClick((): void => {
              this.editMembers = false;
              setTimeout((): void => {
                this.paint();
              }, 60);
            })
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius({ topLeft: 16, topRight: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
