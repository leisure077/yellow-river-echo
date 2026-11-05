import { router, promptAction } from '@kit.ArkUI';
import { StudioStore } from '../service/StudioStore';
import { WorkRec } from '../model/Models';
import { fs, INK, SUB, CLAY, RIVER, PAPER, LINE, paletteOf } from '../common/Theme';
import { PotteryCanvas } from '../view/PotteryCanvas';
import { PotteryTurntable } from '../view/PotteryTurntable';
import { Pottery3D, PROBE_MS } from '../view/Pottery3D';
import { goCourses } from '../common/Nav';

const SHAPES: string[] = ['罐', '盆', '壶', '瓶', '鼎式'];
const MOTIFS: string[] = ['鱼纹', '鸟纹', '漩涡纹', '网格纹', '锯齿纹', '花瓣纹'];
const GLAZE_KEYS: string[] = ['yangshao', 'longshan', 'xiashang', 'zhou', 'hantang', 'song'];
const GLAZE_NAMES: string[] = ['仰韶红', '龙山黑', '夏商青绿', '周玉色', '汉唐赭黄', '宋天青'];
const BOXES: string[] = ['素台', '木座', '圆几', '无'];

@Entry
@Component
struct PotteryPage {
  
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('studioRev') rev: number = 0;
  @State shape: string = '罐';
  @State motif: string = '鱼纹';
  @State glaze: string = 'yangshao';
  @State box: string = '素台';
  @State seed: number = 1;
  @State name: string = '未命名第 1 件';
  
  @State mode3d: string = 'probe';
  private probeTimer: number = -1;

  aboutToAppear(): void {
    this.name = `未命名第 ${StudioStore.get().works.length + 1} 件`;
    
    this.probeTimer = setTimeout((): void => {
      this.probeTimer = -1;
      if (this.mode3d === 'probe') {
        this.mode3d = 'fallback';
      }
    }, PROBE_MS);
  }

  aboutToDisappear(): void {
    if (this.probeTimer >= 0) {
      clearTimeout(this.probeTimer);
      this.probeTimer = -1;
    }
  }

  onProbe(m: string): void {
    if (this.probeTimer >= 0) {
      clearTimeout(this.probeTimer);
      this.probeTimer = -1;
    }
    if (m === '3d') {
      this.mode3d = '3d';
    } else if (this.mode3d !== '3d') {
      this.mode3d = 'fallback';
    }
  }

  works(): WorkRec[] {
    if (this.rev < 0) {
      return [];
    }
    return StudioStore.get().works;
  }

  glazeName(): string {
    let i = GLAZE_KEYS.indexOf(this.glaze);
    return i < 0 ? GLAZE_NAMES[0] : GLAZE_NAMES[i];
  }

  setDim(which: string, v: string): void {
    if (which === 'shape') {
      this.shape = v;
    } else if (which === 'motif') {
      this.motif = v;
    } else if (which === 'glaze') {
      let i = GLAZE_NAMES.indexOf(v);
      this.glaze = i < 0 ? GLAZE_KEYS[0] : GLAZE_KEYS[i];
    } else if (which === 'box') {
      this.box = v;
    }
  }

  reset(): void {
    this.shape = SHAPES[this.seed % SHAPES.length];
    this.motif = MOTIFS[(this.seed + 1) % MOTIFS.length];
    this.glaze = GLAZE_KEYS[(this.seed + 2) % GLAZE_KEYS.length];
    this.box = BOXES[this.seed % BOXES.length];
    this.seed += 1;
    this.name = `未命名第 ${this.works().length + 1} 件`;
    promptAction.showToast({ message: '已清空，从头再配' });
  }

  save(): void {
    let title = this.name.trim();
    if (title.length === 0) {
      title = `未命名第 ${this.works().length + 1} 件`;
    }
    let w: WorkRec = {
      id: 'w_' + Date.now(),
      name: title,
      shape: this.shape,
      motif: this.motif,
      glaze: this.glaze,
      word: '',
      box: this.box,
      createdAt: Date.now()
    };
    StudioStore.get().addWork(w);
    promptAction.showToast({ message: '已存入「我的 · 作品」' });
    this.name = `未命名第 ${this.works().length + 1} 件`;
  }

  load(w: WorkRec): void {
    this.shape = w.shape;
    this.motif = w.motif;
    this.glaze = w.glaze;
    this.box = w.box;
    this.name = w.name;
    promptAction.showToast({ message: `已载入「${w.name}」的参数` });
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text('‹').fontSize(fs(this.ts, 26)).fontColor(CLAY).width(22)
          .onClick((): void => {
            router.back();
          })
        Column({ space: 2 }) {
          Text('彩陶工坊').fontSize(fs(this.ts, 20)).fontColor(INK).fontWeight(FontWeight.Bold)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('课程 ›').fontSize(fs(this.ts, 15)).fontColor(RIVER)
          .onClick((): void => {
            goCourses();
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10 })

      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 8 }) {
            
            Column() {
              Stack() {
                Pottery3D({
                  shape: this.shape,
                  motif: this.motif,
                  glaze: this.glaze,
                  pedestal: this.box,
                  seed: this.seed,
                  onMode: (m: string): void => {
                    this.onProbe(m);
                  }
                })
                  
                  .visibility(this.mode3d === 'fallback' ? Visibility.Hidden : Visibility.Visible)
                if (this.mode3d !== '3d') {
                  PotteryTurntable({
                    shape: this.shape,
                    motif: this.motif,
                    glaze: this.glaze,
                    pedestal: this.box,
                    seed: this.seed
                  })
                }
              }
              .width('100%')
              .height('100%')
            }
            .width('100%')
            .height(300)
            .borderRadius(12)
            .clip(true)

            Row({ space: 8 }) {
              Text('作品名').fontSize(fs(this.ts, 14)).fontColor(SUB)
              TextInput({ text: this.name, placeholder: '给这件起个名' })
                .height(40).fontSize(fs(this.ts, 15)).layoutWeight(1)
                .backgroundColor(PAPER)
                .onChange((v: string): void => {
                  this.name = v;
                })
            }
            .width('100%')

            Text(`${this.shape} · ${this.motif} · ${this.glazeName()} · ${this.box}`)
              .fontSize(fs(this.ts, 13)).fontColor(SUB).width('100%')
          }
          .width('100%')
          .padding(10)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(14)

          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('器型').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
              Text('口沿、鼓腹、底足各不相同').fontSize(fs(this.ts, 12)).fontColor(SUB).layoutWeight(1)
            }
            .width('100%')

            Scroll() {
              Row({ space: 7 }) {
                ForEach(SHAPES, (o: string): void => {
                  Text(o)
                    .fontSize(fs(this.ts, 14))
                    .fontColor(o === this.shape ? Color.White : INK)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(14)
                    .backgroundColor(o === this.shape ? CLAY : $r('app.color.card_bg'))
                    .border({ width: 1, color: o === this.shape ? CLAY : LINE })
                    .onClick((): void => {
                      this.setDim('shape', o);
                    })
                }, (o: string): string => 'shape_' + o)
              }
              .padding({ right: 10 })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('纹样').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
              Text('画在腹部纹样带上').fontSize(fs(this.ts, 12)).fontColor(SUB).layoutWeight(1)
            }
            .width('100%')

            Scroll() {
              Row({ space: 7 }) {
                ForEach(MOTIFS, (o: string): void => {
                  Text(o)
                    .fontSize(fs(this.ts, 14))
                    .fontColor(o === this.motif ? Color.White : INK)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(14)
                    .backgroundColor(o === this.motif ? CLAY : $r('app.color.card_bg'))
                    .border({ width: 1, color: o === this.motif ? CLAY : LINE })
                    .onClick((): void => {
                      this.setDim('motif', o);
                    })
                }, (o: string): string => 'motif_' + o)
              }
              .padding({ right: 10 })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('配色').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
              Text('按时代的釉色调子').fontSize(fs(this.ts, 12)).fontColor(SUB).layoutWeight(1)
            }
            .width('100%')

            Scroll() {
              Row({ space: 7 }) {
                ForEach(GLAZE_NAMES, (o: string): void => {
                  Text(o)
                    .fontSize(fs(this.ts, 14))
                    .fontColor(o === this.glazeName() ? Color.White : INK)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(14)
                    .backgroundColor(o === this.glazeName() ? CLAY : $r('app.color.card_bg'))
                    .border({ width: 1, color: o === this.glazeName() ? CLAY : LINE })
                    .onClick((): void => {
                      this.setDim('glaze', o);
                    })
                }, (o: string): string => 'glaze_' + o)
              }
              .padding({ right: 10 })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('展示座').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
              Text('器物下面垫什么').fontSize(fs(this.ts, 12)).fontColor(SUB).layoutWeight(1)
            }
            .width('100%')

            Scroll() {
              Row({ space: 7 }) {
                ForEach(BOXES, (o: string): void => {
                  Text(o)
                    .fontSize(fs(this.ts, 14))
                    .fontColor(o === this.box ? Color.White : INK)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .borderRadius(14)
                    .backgroundColor(o === this.box ? CLAY : $r('app.color.card_bg'))
                    .border({ width: 1, color: o === this.box ? CLAY : LINE })
                    .onClick((): void => {
                      this.setDim('box', o);
                    })
                }, (o: string): string => 'box_' + o)
              }
              .padding({ right: 10 })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('已存作品').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
              Text(`${this.works().length} 件 · 点开可重新编辑`).fontSize(fs(this.ts, 12)).fontColor(SUB)
                .layoutWeight(1)
            }
            .width('100%')

            if (this.works().length === 0) {
              Text('还没有存过作品，配好了点下面的「保存这件」')
                .fontSize(fs(this.ts, 13)).fontColor(SUB).width('100%').padding({ top: 8, bottom: 8 })
            } else {
              List({ space: 8 }) {
                ForEach(this.works(), (w: WorkRec): void => {
                  ListItem() {
                    Column({ space: 2 }) {
                      Stack({ alignContent: Alignment.TopEnd }) {
                        Column() {
                          PotteryCanvas({
                            shape: w.shape,
                            motif: w.motif,
                            glaze: w.glaze,
                            pedestal: w.box,
                            word: w.word,
                            seed: w.name.length + w.motif.length
                          })
                        }
                        .width(88).height(88).borderRadius(8).clip(true)
                        Text('✕')
                          .fontSize(fs(this.ts, 14)).fontColor(INK)
                          .width(20).height(20).borderRadius(10)
                          .backgroundColor('rgba(255,255,255,0.88)')
                          .textAlign(TextAlign.Center)
                          .onClick((): void => {
                            StudioStore.get().dropWork(w.id);
                          })
                      }
                      .width(88)

                      Text(w.name).fontSize(fs(this.ts, 12)).fontColor(SUB).width(88).maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .padding(4)
                    .backgroundColor($r('app.color.card_bg'))
                    .borderRadius(10)
                    .onClick((): void => {
                      this.load(w);
                    })
                  }
                }, (w: WorkRec): string => w.id + '_' + w.name.length)
              }
              .listDirection(Axis.Horizontal)
              .height(120)
              .scrollBar(BarState.Off)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 12 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      Row({ space: 10 }) {
        Button('再来一件')
          .layoutWeight(1).height(42).fontSize(fs(this.ts, 16))
          .backgroundColor($r('app.color.line')).fontColor(INK)
          .onClick((): void => {
            this.reset();
          })
        Button('保存这件')
          .layoutWeight(1).height(42).fontSize(fs(this.ts, 16))
          .backgroundColor(paletteOf(this.glaze).deep).fontColor(Color.White)
          .onClick((): void => {
            this.save();
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, bottom: 12, top: 2 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .alignItems(HorizontalAlign.Start)
  }
}
