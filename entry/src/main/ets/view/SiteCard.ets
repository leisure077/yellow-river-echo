import { SiteInfo } from '../model/Models';
import { fs, coverRes, INK, SUB, CLAY } from '../common/Theme';
import { goDetail } from '../common/Nav';

@Component
export struct SiteCard {
  
  @StorageLink('textScale') ts: number = 1;
  @Require @Prop site: SiteInfo;
  @Prop note: string = '';

  build() {
    Row({ space: 10 }) {
      Image(coverRes(this.site.cover))
        .width(64)
        .height(64)
        .borderRadius(8)
        .objectFit(ImageFit.Cover)
      Column({ space: 4 }) {
        Text(this.site.name)
          .fontSize(fs(this.ts, 16))
          .fontColor(INK)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.site.city} · ${this.site.eras.join('/')} · ${this.site.types.join('/')}`)
          .fontSize(fs(this.ts, 12))
          .fontColor(SUB)
        if (this.note.length > 0) {
          Text(this.note)
            .fontSize(fs(this.ts, 11))
            .fontColor(CLAY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          Text(this.site.summary)
            .fontSize(fs(this.ts, 12))
            .fontColor(SUB)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›')
        .fontSize(fs(this.ts, 20))
        .fontColor(SUB)
    }
    .width('100%')
    .padding(10)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(10)
    .onClick((): void => {
      goDetail(this.site.id);
    })
  }
}
