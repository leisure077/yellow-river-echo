import { Course } from '../model/Models';
import { fs, INK, SUB, CLAY } from '../common/Theme';
import { goPlayer } from '../common/Nav';
import { ArtCover } from './ArtCover';

export function coverShape(c: Course): string {
  let hay = c.title + c.brief;
  if (hay.indexOf('拓') >= 0 || hay.indexOf('碑') >= 0 || hay.indexOf('刻') >= 0) {
    return 'scroll';
  }
  if (hay.indexOf('窑') >= 0 || hay.indexOf('塔') >= 0 || hay.indexOf('寺') >= 0) {
    return 'kiln';
  }
  if (hay.indexOf('爵') >= 0 || hay.indexOf('铜') >= 0 || hay.indexOf('范铸') >= 0) {
    return 'coin';
  }
  if (hay.indexOf('黑陶') >= 0 || hay.indexOf('拉坯') >= 0 || hay.indexOf('施釉') >= 0) {
    return 'jar';
  }
  if (hay.indexOf('彩陶') >= 0 || hay.indexOf('鱼纹') >= 0 || hay.indexOf('捏') >= 0) {
    return 'pot';
  }
  return 'tile';
}

@Component
export struct CourseRow {
  @StorageLink('textScale') ts: number = 1;
  @Require @Prop course: Course;
  @Prop seed: number = 1;

  build() {
    Row({ space: 10 }) {
      Stack() {
        ArtCover({ palette: this.course.palette, shape: coverShape(this.course), seed: this.seed })
      }
      .width(72)
      .height(92)
      .borderRadius(10)
      .clip(true)

      Column({ space: 5 }) {
        Text(this.course.title)
          .fontSize(fs(this.ts, 15))
          .fontColor(INK)
          .fontWeight(FontWeight.Medium)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.course.brief)
          .fontSize(fs(this.ts, 12))
          .fontColor(SUB)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.course.cat} · ${this.course.level} · ${this.course.minutes} 分钟 · ${this.course.steps.length} 个分镜`)
          .fontSize(fs(this.ts, 10))
          .fontColor(CLAY)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(10)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .alignItems(VerticalAlign.Top)
    .onClick((): void => {
      goPlayer(this.course.id);
    })
  }
}
