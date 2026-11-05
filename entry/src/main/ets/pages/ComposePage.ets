import { router, promptAction } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { INK, SUB, CLAY, LINE, PAPER, LOESS, fs } from '../common/Theme';
import { goBack, switchTab } from '../common/Nav';
import { PatternBg } from '../view/PatternBg';
import { StudioStore } from '../service/StudioStore';
import { ContentRepo } from '../service/ContentRepo';

interface TopicArg {
  text: string;
  on: boolean;
  act: () => void;
}

const MAX_LEN: number = 200;

@Entry
@Component
struct ComposePage {
  @StorageLink('textScale') ts: number = 1;
  @State draft: string = '';
  @State topic: string = '';
  @State photo: string = '';
  @State picking: boolean = false;

  topics(): string[] {
    return ContentRepo.get().topics();
  }

  async pickPhoto(): Promise<void> {
    if (this.picking) {
      return;
    }
    this.picking = true;
    try {
      let opt = new photoAccessHelper.PhotoSelectOptions();
      opt.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opt.maxSelectNumber = 1;
      let res = await new photoAccessHelper.PhotoViewPicker().select(opt);
      if (res.photoUris.length > 0) {
        this.photo = res.photoUris[0];
      }
    } catch (e) {
      promptAction.showToast({ message: '相册没打开，不配图也能发' });
    }
    this.picking = false;
  }

  readyText(): string {
    let t = this.draft.trim();
    if (t.length < 4) {
      return '';
    }
    return t;
  }

  canSend(): boolean {
    return this.readyText().length > 0;
  }

  publish(): void {
    let t = this.readyText();
    if (t.length === 0) {
      promptAction.showToast({ message: '再多写几个字，至少 4 个' });
      return;
    }
    StudioStore.get().publishPost(t, this.topic, this.photo);
    promptAction.showToast({ message: '已发布，社群最上面就是你的' });
    switchTab(2);
    router.back({ url: 'pages/Index' });
  }

  @Builder
  topicChip(arg: TopicArg) {
    Text(arg.text)
      .fontSize(fs(this.ts, 11))
      .fontColor(arg.on ? PAPER : SUB)
      .padding({ left: 11, right: 11, top: 5, bottom: 5 })
      .borderRadius(13)
      .backgroundColor(arg.on ? CLAY : 'rgba(255,255,255,0.72)')
      .border({ width: 1, color: arg.on ? CLAY : LINE })
      .onClick((): void => {
        arg.act();
      })
  }

  build() {
    Stack() {
      PatternBg()
      Column() {
        Row() {
          Text('‹')
            .fontSize(fs(this.ts, 20)).fontColor(INK)
            .width(34).height(34).textAlign(TextAlign.Center)
            .backgroundColor('rgba(255,255,255,0.72)').borderRadius(17)
            .onClick(goBack)
          Blank()
          Text('发动态')
            .fontSize(fs(this.ts, 18)).fontWeight(FontWeight.Bold).fontColor(INK).letterSpacing(3)
          Blank()
          Text('发布')
            .fontSize(fs(this.ts, 13)).fontColor('#FFFFFF')
            .padding({ left: 16, right: 16, top: 7, bottom: 7 })
            .backgroundColor(this.canSend() ? CLAY : '#C9BCA6')
            .borderRadius(16)
            .onClick((): void => {
              this.publish();
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 8 })

        Scroll() {
          Column({ space: 12 }) {
            Column({ space: 6 }) {
              Text('怎么发').fontSize(fs(this.ts, 12)).fontColor(INK).fontWeight(FontWeight.Medium)
              Text('① 写下你在河边看到的、想到的，一到两行最容易被回话；')
                .fontSize(fs(this.ts, 11)).fontColor(SUB).lineHeight(fs(this.ts, 18)).width('100%')
              Text('② 想配图就点「添加照片」，只写文字发出去也一样；')
                .fontSize(fs(this.ts, 11)).fontColor(SUB).lineHeight(fs(this.ts, 18)).width('100%')
              Text('③ 挂话题、发布都在这一页，发出去就在社群最顶上。')
                .fontSize(fs(this.ts, 11)).fontColor(SUB).lineHeight(fs(this.ts, 18)).width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .backgroundColor('rgba(255,255,255,0.72)')
            .borderRadius(12)
            .border({ width: 1, color: LINE })

            Column({ space: 6 }) {
              Row() {
                Text('正文').fontSize(fs(this.ts, 12)).fontColor(INK).fontWeight(FontWeight.Medium)
                Blank()
                Text(`${this.draft.trim().length}/${MAX_LEN}`)
                  .fontSize(fs(this.ts, 10))
                  .fontColor(this.canSend() ? CLAY : SUB)
              }
              .width('100%')

              TextArea({ placeholder: '比如：今天在西水坡看那条蚌塑的龙，两千年前的河岸边有人把它摆得很端正。', text: this.draft })
                .fontSize(fs(this.ts, 14)).fontColor(INK).placeholderColor('#B7A995')
                .backgroundColor('rgba(255,255,255,0.86)')
                .border({ width: 1, color: LINE }).borderRadius(12)
                .height(140).maxLength(MAX_LEN)
                .onChange((v: string): void => {
                  this.draft = v;
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Column({ space: 6 }) {
              Text('添加照片（可不加）').fontSize(fs(this.ts, 12)).fontColor(INK).fontWeight(FontWeight.Medium)
              if (this.photo.length === 0) {
                Row({ space: 8 }) {
                  Text('＋').fontSize(fs(this.ts, 20)).fontColor(LOESS)
                  Text(this.picking ? '正在打开相册…' : '从相册里挑一张').fontSize(fs(this.ts, 12)).fontColor(SUB)
                }
                .width('100%')
                .height(74)
                .justifyContent(FlexAlign.Center)
                .backgroundColor('rgba(255,255,255,0.60)')
                .borderRadius(12)
                .border({ width: 1, color: LINE, style: BorderStyle.Dashed })
                .onClick((): void => {
                  this.pickPhoto();
                })
              } else {
                Stack({ alignContent: Alignment.TopEnd }) {
                  Image(this.photo)
                    .width('100%').height(168).objectFit(ImageFit.Cover).borderRadius(12)
                  Text('✕')
                    .fontSize(fs(this.ts, 13)).fontColor('#FFFFFF')
                    .width(26).height(26).textAlign(TextAlign.Center)
                    .backgroundColor('rgba(43,38,34,0.62)').borderRadius(13)
                    .margin(8)
                    .onClick((): void => {
                      this.photo = '';
                    })
                }
                .width('100%')
                .onClick((): void => {
                  this.pickPhoto();
                })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .backgroundColor('rgba(255,255,255,0.72)')
            .borderRadius(12)
            .border({ width: 1, color: LINE })

            Column({ space: 8 }) {
              Text('挂个话题（可不选）').fontSize(fs(this.ts, 12)).fontColor(INK).fontWeight(FontWeight.Medium)
              if (this.topics().length === 0) {
                Text('随包还没带话题，直接发就行').fontSize(fs(this.ts, 11)).fontColor(SUB)
              } else {
                Flex({ wrap: FlexWrap.Wrap }) {
                  Column() {
                    this.topicChip({
                      text: this.topic.length === 0 ? '# 不挂话题' : '不挂话题',
                      on: this.topic.length === 0,
                      act: (): void => {
                        this.topic = '';
                      }
                    })
                  }.margin({ right: 6, bottom: 6 })
                  ForEach(this.topics(), (t: string): void => {
                    Column() {
                      this.topicChip({
                        text: this.topic === t ? `# ${t}` : t,
                        on: this.topic === t,
                        act: (): void => {
                          this.topic = t;
                        }
                      })
                    }.margin({ right: 6, bottom: 6 })
                  }, (t: string): string => 'tp_' + t)
                }
                .width('100%')
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .backgroundColor('rgba(255,255,255,0.72)')
            .borderRadius(12)
            .border({ width: 1, color: LINE })

            Text('发布')
              .fontSize(fs(this.ts, 14)).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
              .width('100%').textAlign(TextAlign.Center)
              .padding({ top: 11, bottom: 11 })
              .backgroundColor(this.canSend() ? CLAY : '#C9BCA6')
              .borderRadius(20)
              .margin({ top: 6 })
              .onClick((): void => {
                this.publish();
              })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 4, bottom: 28 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%').height('100%')
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
