import { router, promptAction } from '@kit.ArkUI';
import { SiteRepo } from '../service/SiteRepo';
import { MemoryStore } from '../service/MemoryStore';
import { StudioStore } from '../service/StudioStore';
import { SiteInfo, Suggestion, NoteRec, TagRec, Poem } from '../model/Models';
import { coverRes, INK, SUB, LOESS, CLAY, fs } from '../common/Theme';
import { RiverRibbon } from '../common/River';
import { params, goNote } from '../common/Nav';
import { SiteCard } from '../view/SiteCard';

interface SecCard {
  t: string;
  body: string;
}

@Entry
@Component
struct DetailPage {
  @StorageLink('dataRev') @Watch('reload') rev: number = 0;
  @StorageLink('studioRev') @Watch('syncCheckin') studioRev: number = 0;
  @StorageLink('textScale') ts: number = 1;
  @State site: SiteInfo | undefined = undefined;
  
  @State favOn: boolean = false;
  @State readOn: boolean = false;
  @State notes: NoteRec[] = [];
  @State tags: TagRec[] = [];
  @State sheetOpen: boolean = false;
  @State sheetPicked: string[] = [];
  @State scrollY: number = 0;
  @State poemOn: boolean = false;
  @State sealOn: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    let p = params();
    if (p.id !== undefined) {
      this.site = SiteRepo.get().byId(p.id);
      if (this.site !== undefined) {
        MemoryStore.get().touchView(this.site.id);
        this.sealOn = StudioStore.get().siteChecked(this.site.id);
      }
    }
    this.reload();
  }

  reload(): void {
    let s = this.site;
    if (s !== undefined) {
      this.favOn = MemoryStore.get().isFav(s.id);
      let pr = MemoryStore.get().progressOf(s.id);
      this.readOn = pr !== undefined && pr.read;
      this.notes = MemoryStore.get().notesOfSite(s.id);
    }
    this.tags = MemoryStore.get().tagsActive();
  }

  syncCheckin(): void {
    if (this.site !== undefined) {
      this.sealOn = StudioStore.get().siteChecked(this.site.id);
    }
  }

  secs(): SecCard[] {
    let s = this.site;
    if (s === undefined) {
      return [];
    }
    let out: SecCard[] = [];
    out.push({ t: '概况', body: s.intro });
    out.push({ t: '考古发现', body: s.archaeology });
    out.push({ t: '历史事件', body: s.history });
    let poemText = s.poems.map((x: Poem): string => `${x.line}　——${x.author}${x.source}`).join('\n');
    out.push({ t: '相关诗词', body: poemText.length > 0 ? poemText : '暂未收录可靠篇目，欢迎补充线索。' });
    let tr = s.travel;
    out.push({ t: '文旅信息',
      body: `门票：${tr.ticket}\n开放：${tr.openTime}\n提示：${tr.tips}\n（更新于 ${tr.updated}，出行前请以官方公告为准）` });
    out.push({ t: '来源', body: '文字与考据线索来自：' + s.source });
    return out;
  }

  readLine(): string {
    let s = this.site;
    if (s === undefined) {
      return '';
    }
    let pr = MemoryStore.get().progressOf(s.id);
    if (pr === undefined) {
      return '刚开始读';
    }
    return `读到第 ${pr.maxSection + 1} 节 / 共 ${this.secs().length} 节`;
  }

  barAlpha(): number {
    let v = (this.scrollY - 132) / 60;
    if (v < 0) {
      return 0;
    }
    return v > 1 ? 1 : v;
  }

  checkinText(): string {
    let s = this.site;
    if (s === undefined) {
      return '';
    }
    let rec = StudioStore.get().checkinOf(s.id);
    if (rec === undefined) {
      return '在此打卡';
    }
    let d = new Date(rec.at);
    return `你于 ${d.getMonth() + 1} 月 ${d.getDate()} 日在此打卡`;
  }

  sealChar(): string {
    let s = this.site;
    if (s === undefined) {
      return '河';
    }
    let src = s.alias.length > 0 ? s.alias : s.name;
    return src.substring(0, 1);
  }

  doCheckin(): void {
    let s = this.site;
    if (s === undefined) {
      return;
    }
    if (StudioStore.get().checkinSite(s.id)) {
      promptAction.showToast({ message: '已记下这一步（只存本机）' });
    }
  }

  undoCheckin(): void {
    let s = this.site;
    if (s === undefined) {
      return;
    }
    StudioStore.get().undoCheckinSite(s.id);
  }

  @Builder
  sectionCard(sec: SecCard, idx: number) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(`${idx + 1}`).fontSize(fs(this.ts, 12)).fontColor(Color.White)
          .width(18).height(18).borderRadius(9)
          .backgroundColor(idx < 3 ? CLAY : LOESS)
          .textAlign(TextAlign.Center)
        Text(sec.t).fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Medium)
        Blank()
        if (idx === 3) {
          Text('拟咏已按库内标注').fontSize(fs(this.ts, 9)).fontColor(SUB)
        }
      }
      .width('100%')
      Text(sec.body)
        .fontSize(fs(this.ts, 14))
        .fontColor(INK)
        .lineHeight(fs(this.ts, 23))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
  }

  @Builder
  poemCard() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('4').fontSize(fs(this.ts, 12)).fontColor(Color.White)
          .width(18).height(18).borderRadius(9)
          .backgroundColor(LOESS)
          .textAlign(TextAlign.Center)
        Text('相关诗词').fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Medium)
        Blank()
        Text('库内收录').fontSize(fs(this.ts, 9)).fontColor(SUB)
      }
      .width('100%')

      Row() {
        ForEach(this.site!.poems, (x: Poem, pi: number): void => {
          Column({ space: 3 }) {
            ForEach(x.line.split(''), (ch: string, ci: number): void => {
              Text(ch)
                .fontSize(fs(this.ts, 17))
                .fontColor(INK)
                .lineHeight(fs(this.ts, 26))
            }, (ch: string, ci: number): string => `${pi}-${ci}-${ch}`)
            Text(`${x.author}｜${x.source}`)
              .fontSize(fs(this.ts, 10))
              .fontColor(SUB)
              .margin({ top: 6 })
          }
          .alignItems(HorizontalAlign.Center)
          .opacity(this.poemOn ? 1 : 0)
          .margin({ right: 16 })
          .animation({ duration: 320, delay: pi * 260, curve: Curve.EaseOut })
        }, (x: Poem, pi: number): string => `${pi}-${x.line}`)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .onVisibleAreaChange([0.4], (isVisible: boolean): void => {
      if (isVisible) {
        this.poemOn = true;
      }
    })
  }

  @Builder
  headerItem() {
    Column() {
      Stack({ alignContent: Alignment.BottomStart }) {
        Image(coverRes(this.site!.cover))
          .width('100%').height(200).objectFit(ImageFit.Cover)
          .translate({ y: this.scrollY * 0.4 })

        Column({ space: 4 }) {
          Text(this.site!.name)
            .fontSize(fs(this.ts, 22)).fontColor(Color.White).fontWeight(FontWeight.Bold)
          Text(`${this.site!.city} · ${this.site!.eras.join('/')} · ${this.site!.types.join('/')}`)
            .fontSize(fs(this.ts, 12)).fontColor('#E8E0D2')
        }
        .alignItems(HorizontalAlign.Start)
        .padding(14)

        Stack({ alignContent: Alignment.BottomEnd }) {
          Column() {
            Text(this.sealChar())
              .fontSize(fs(this.ts, 17))
              .fontColor('#F6E2CE')
              .fontWeight(FontWeight.Bold)
          }
          .width(42).height(42)
          .borderRadius(6)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(166,85,61,0.86)')
          .border({ width: 2, color: '#DCC3A8' })
          .margin({ right: 14, bottom: 14 })
          .opacity(this.sealOn ? 0.95 : 0)
          .scale({ x: this.sealOn ? 1 : 1.7, y: this.sealOn ? 1 : 1.7 })
          .rotate({ angle: -8 })
          .animation({ duration: 340, curve: Curve.FastOutSlowIn })
        }
        .width('100%').height('100%')
      }
      .width('100%').height(200).clip(true)
    }
  }

  @Builder
  actionBar() {
    Row({ space: 10 }) {
      Button(this.favOn ? '已收藏' : '收藏')
        .fontSize(fs(this.ts, 13))
        .backgroundColor(this.favOn ? LOESS : CLAY)
        .onClick(async (): Promise<void> => {
          if (this.favOn) {
            await MemoryStore.get().removeFav(this.site!.id);
          } else {
            await MemoryStore.get().addFav(this.site!.id);
          }
        })
      Button('归类')
        .fontSize(fs(this.ts, 13))
        .backgroundColor($r('app.color.line'))
        .fontColor(INK)
        .onClick((): void => {
          let fav = MemoryStore.get().favOf(this.site!.id);
          this.sheetPicked = fav === undefined ? [] : fav.tagIds.slice();
          this.sheetOpen = true;
        })
      Button('写一笔')
        .fontSize(fs(this.ts, 13))
        .backgroundColor($r('app.color.line'))
        .fontColor(INK)
        .onClick((): void => {
          goNote(this.site!.id, '');
        })
      Blank()
      Text(this.readOn ? '已读' : '未读')
        .fontSize(fs(this.ts, 12)).fontColor(SUB)
        .onClick(async (): Promise<void> => {
          let pr = MemoryStore.get().progressOf(this.site!.id);
          let cur = pr !== undefined && pr.read;
          await MemoryStore.get().markRead(this.site!.id, !cur);
        })
    }
    .width('100%')
    .padding({ left: 2, right: 2 })
  }

  @Builder
  checkinRow() {
    Row({ space: 10 }) {
      Column() {
        Text(this.checkinText())
          .fontSize(fs(this.ts, 13))
          .fontColor(this.sealOn ? CLAY : INK)
          .fontWeight(this.sealOn ? FontWeight.Normal : FontWeight.Medium)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.sealOn) {
        Text('撤销')
          .fontSize(fs(this.ts, 12))
          .fontColor(SUB)
          .onClick((): void => {
            this.undoCheckin();
          })
      } else {
        Text('打卡')
          .fontSize(fs(this.ts, 13))
          .fontColor('#FFFFFF')
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .backgroundColor(CLAY)
          .borderRadius(14)
          .onClick((): void => {
            this.doCheckin();
          })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.site !== undefined) {
        List({ space: 10, scroller: this.scroller }) {
          ListItem() {
            this.headerItem()
          }

          ListItem() {
            this.actionBar()
          }

          ListItem() {
            this.checkinRow()
          }

          ListItem() {
            Text(this.readLine()).fontSize(fs(this.ts, 11)).fontColor(SUB)
              .width('100%').padding({ left: 4 })
          }

          ListItem() {
            RiverRibbon({ bandHeight: 66, showDots: true, activeId: this.site.id,
              note: '你在干流上的位置。横轴是年代，纵向偏移是城市自西向东。' })
          }

          ForEach(this.secs(), (sec: SecCard, idx: number): void => {
            ListItem() {
              if (idx === 3 && this.site !== undefined && this.site!.poems.length > 0) {
                this.poemCard()
              } else {
                this.sectionCard(sec, idx)
              }
            }
          }, (sec: SecCard): string => sec.t)

          ListItem() {
            Text(`这里的笔记（${this.notes.length}）`)
              .fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
              .width('100%').padding(4)
          }

          ForEach(this.notes, (n: NoteRec): void => {
            ListItem() {
              Column({ space: 4 }) {
                Text(n.text).fontSize(fs(this.ts, 13)).fontColor(INK).maxLines(3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text('点按编辑').fontSize(fs(this.ts, 10)).fontColor(SUB)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(12)
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(10)
              .onClick((): void => {
                goNote('', n.id);
              })
            }
          }, (n: NoteRec): string => n.id + '_' + this.rev)

          ListItem() {
            Text('同一段河')
              .fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
              .width('100%').padding(4)
          }

          ForEach(SiteRepo.get().related(this.site, 4), (sg: Suggestion): void => {
            ListItem() {
              SiteCard({ site: sg.site, note: sg.reason })
            }
          }, (sg: Suggestion): string => sg.site.id)

          ListItem() {
            Column().height(24)
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .padding({ left: 14, right: 14 })
        .onDidScroll((offset: number, state: ScrollState): void => {
          let next = this.scrollY + offset;
          this.scrollY = next < 0 ? 0 : next;
        })
        .onScrollIndex((first: number, last: number): void => {
          
          let max = this.secs().length - 1;
          let secIdx = Math.min(Math.max(last - 5, 0), max);
          if (this.site !== undefined) {
            MemoryStore.get().bumpSection(this.site.id, secIdx);
          }
        })
      } else {
        Column() {
          Text('没找到这条资源').fontSize(fs(this.ts, 15)).fontColor(INK)
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      }

      Row({ space: 10 }) {
        Text('‹ 返回')
          .fontSize(fs(this.ts, 14))
          .fontColor(this.barAlpha() > 0.5 ? INK : Color.White)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(this.barAlpha() > 0.5 ? Color.Transparent : '#66000000')
          .borderRadius(14)
          .onClick((): void => {
            router.back();
          })
        if (this.site !== undefined) {
          Text(this.site.name)
            .fontSize(fs(this.ts, 16))
            .fontColor(INK)
            .fontWeight(FontWeight.Medium)
            .opacity(this.barAlpha())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
      }
      .width('100%')
      .padding({ left: 10, right: 14, top: 12, bottom: 8 })
      .backgroundColor(`rgba(245,239,228,${(this.barAlpha() * 0.96).toFixed(2)})`)
      .position({ x: 0, y: 0 })
      .hitTestBehavior(this.barAlpha() > 0.5 ? HitTestMode.Default : HitTestMode.Transparent)

      if (this.sheetOpen && this.site !== undefined) {
        Column()
          .width('100%').height('100%')
          .backgroundColor('#66000000')
          .onClick((): void => {
            this.sheetOpen = false;
          })
        Column({ space: 10 }) {
          Text('归类到标签').fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Medium)
          ForEach(this.tags, (t: TagRec): void => {
            Row() {
              Text(t.name).fontSize(fs(this.ts, 14)).fontColor(INK).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.sheetPicked.indexOf(t.id) >= 0 })
                .selectedColor(CLAY)
                .onChange((on: boolean): void => {
                  let i = this.sheetPicked.indexOf(t.id);
                  if (on && i < 0) {
                    this.sheetPicked.push(t.id);
                  } else if (!on && i >= 0) {
                    this.sheetPicked.splice(i, 1);
                  }
                })
            }.width('100%')
          }, (t: TagRec): string => t.id + '_' + this.rev)
          Button('保存归类')
            .backgroundColor(LOESS)
            .fontColor(Color.White)
            .onClick(async (): Promise<void> => {
              await MemoryStore.get().setFavTags(this.site!.id, this.sheetPicked);
              this.sheetOpen = false;
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
