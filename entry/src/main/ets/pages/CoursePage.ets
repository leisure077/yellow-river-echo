import { router } from '@kit.ArkUI';
import { ContentRepo } from '../service/ContentRepo';
import { Course } from '../model/Models';
import { fs, INK, SUB, CLAY } from '../common/Theme';
import { CourseRow } from '../view/CourseRow';

const CATS: string[] = ['全部', '手作', '讲读', '影像'];

@Entry
@Component
struct CoursePage {
  
  @StorageLink('textScale') ts: number = 1;
  @State cat: string = '全部';

  list(): Course[] {
    return ContentRepo.get().coursesOf(this.cat);
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text('‹').fontSize(fs(this.ts, 24)).fontColor(CLAY).width(22)
          .onClick((): void => {
            router.back();
          })
        Column({ space: 2 }) {
          Text('课程影像').fontSize(fs(this.ts, 18)).fontColor(INK).fontWeight(FontWeight.Bold)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10 })

      Scroll() {
        Row({ space: 8 }) {
          ForEach(CATS, (o: string): void => {
            Text(o)
              .fontSize(fs(this.ts, 12))
              .fontColor(o === this.cat ? Color.White : INK)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .borderRadius(14)
              .backgroundColor(o === this.cat ? CLAY : $r('app.color.card_bg'))
              .onClick((): void => {
                this.cat = o;
              })
          }, (o: string): string => 'cat_' + o)
        }
        .padding({ left: 14, right: 14 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      if (ContentRepo.get().courses.length === 0) {
        Column({ space: 6 }) {
          Text('课程数据包未随包提供').fontSize(fs(this.ts, 14)).fontColor(INK)
          Text('遗址档案与彩陶工坊不受影响').fontSize(fs(this.ts, 11)).fontColor(SUB)
        }
        .width('100%')
        .margin({ top: 60 })
      } else if (this.list().length === 0) {
        Text('这一类暂时没有课程').fontSize(fs(this.ts, 13)).fontColor(SUB)
          .width('100%').margin({ top: 40 })
      } else {
        List({ space: 8 }) {
          ForEach(this.list(), (c: Course, i: number): void => {
            ListItem() {
              CourseRow({ course: c, seed: i + 1 })
            }
          }, (c: Course): string => c.id + '_' + c.title.length)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ left: 14, right: 14 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .alignItems(HorizontalAlign.Start)
  }
}
