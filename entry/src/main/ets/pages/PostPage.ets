import { promptAction } from '@kit.ArkUI';
import { Post, PostComment, LocalComment } from '../model/Models';
import { ContentRepo } from '../service/ContentRepo';
import { StudioStore } from '../service/StudioStore';
import { SiteRepo } from '../service/SiteRepo';
import { PatternBg } from '../view/PatternBg';
import { INK, SUB, CLAY, LINE, PAPER, RIVER, agoText, likeText, paletteOf, eraPalette, coverRes, fs } from '../common/Theme';
import { goBack, params, goDetail } from '../common/Nav';

@Entry
@Component
struct PostPage {
  @StorageLink('studioRev') @Watch('syncMine') studioRev: number = 0;
  @StorageLink('textScale') ts: number = 1;
  @State post: Post | undefined = undefined;
  @State liked: boolean = false;
  @State followed: boolean = false;
  @State mine: LocalComment[] = [];
  @State draft: string = '';

  aboutToAppear(): void {
    let p = params();
    let id = p !== undefined && p.id !== undefined ? p.id : '';
    this.post = ContentRepo.get().postOf(id);
    if (this.post !== undefined) {
      StudioStore.get().markPostRead(this.post.id);
    }
    this.syncMine();
  }

  syncMine(): void {
    let st = StudioStore.get();
    if (this.post !== undefined) {
      this.liked = st.isLiked('p_' + this.post.id);
      this.followed = st.isFollowed(this.post.author);
      this.mine = st.commentsFor(this.post.id);
    }
  }

  siteName(): string {
    if (this.post === undefined) {
      return '';
    }
    let s = SiteRepo.get().byId(this.post.siteId);
    return s === undefined ? '' : s.name;
  }

  isMine(): boolean {
    return this.post !== undefined && StudioStore.get().isMyPost(this.post.id);
  }

  imgSrc(): string | Resource {
    let img = this.post !== undefined ? this.post.img : '';
    if (img.indexOf('://') >= 0) {
      return img;
    }
    return coverRes(img);
  }

  askDelete(): void {
    if (this.post === undefined) {
      return;
    }
    let id = this.post.id;
    AlertDialog.show({
      title: '删掉这条动态？',
      message: '删了就找不回来了，你在这条下面的回话也一并清掉',
      primaryButton: {
        value: '删',
        fontColor: CLAY,
        action: (): void => {
          StudioStore.get().removeUserPost(id);
          promptAction.showToast({ message: '已删除' });
          goBack();
        }
      },
      secondaryButton: { value: '留着', action: (): void => {} }
    });
  }

  avatarKey(): string {
    if (this.post === undefined) {
      return 'yangshao';
    }
    if (this.isMine()) {
      let keys: string[] = ['yangshao', 'longshan', 'xiashang', 'zhou', 'hantang', 'song'];
      let n = StudioStore.get().profile.avatar;
      return keys[n >= 0 && n < keys.length ? n : 0];
    }
    let s = SiteRepo.get().byId(this.post.siteId);
    if (s === undefined) {
      return 'yangshao';
    }
    return eraPalette(s.eras.length > 0 ? s.eras[0] : '');
  }

  allComments(): PostComment[] {
    let out: PostComment[] = [];
    if (this.post === undefined) {
      return out;
    }
    for (let c of this.post.comments) {
      out.push(c);
    }
    let nick = StudioStore.get().profile.nick;
    for (let c of this.mine) {
      let lc: PostComment = { author: nick.length > 0 ? nick : '我', text: c.text, at: c.at };
      out.push(lc);
    }
    out.sort((a: PostComment, b: PostComment): number => a.at - b.at);
    return out;
  }

  send(): void {
    if (this.post === undefined) {
      return;
    }
    if (!StudioStore.get().addPostComment(this.post.id, this.draft)) {
      promptAction.showToast({ message: '先写两个字再发' });
      return;
    }
    this.draft = '';
    promptAction.showToast({ message: '已回话，只存这台设备' });
  }

  @Builder
  commentRow(c: PostComment, mineOne: boolean) {
    Row({ space: 8 }) {
      Column() {
        Text(c.author.substring(0, 1))
          .fontSize(fs(this.ts, 10)).fontColor(paletteOf(mineOne ? 'hantang' : 'yangshao').ink).fontWeight(FontWeight.Bold)
      }
      .width(20).height(20).borderRadius(10)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(paletteOf(mineOne ? 'hantang' : 'yangshao').deep)

      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(c.author).fontSize(fs(this.ts, 12)).fontColor(INK).fontWeight(FontWeight.Medium)
          Text(agoText(c.at)).fontSize(fs(this.ts, 10)).fontColor(SUB)
        }
        Text(c.text).fontSize(fs(this.ts, 13)).fontColor(INK).lineHeight(fs(this.ts, 19)).width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding(10)
    .backgroundColor(PAPER)
    .borderRadius(10)
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
          Text('动态').fontSize(fs(this.ts, 18)).fontWeight(FontWeight.Bold).fontColor(INK).letterSpacing(3)
          Blank()
          if (this.isMine()) {
            Text('删除')
              .fontSize(fs(this.ts, 12)).fontColor(CLAY)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .border({ width: 1, color: CLAY }).borderRadius(15)
              .onClick((): void => {
                this.askDelete();
              })
          } else {
            Column().width(34).height(34)
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 6 })

        if (this.post === undefined) {
          Column({ space: 8 }) {
            Text('这条动态不在本机').fontSize(fs(this.ts, 15)).fontColor(INK)
            Text('社区数据没随包提供，回去看看别的').fontSize(fs(this.ts, 12)).fontColor(SUB)
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 12 }) {
              Stack({ alignContent: Alignment.BottomStart }) {
                if (this.post!.img.length > 0) {
                  Image(this.imgSrc())
                    .width('100%').height(252).objectFit(ImageFit.Cover)
                } else {
                  Column() {
                    Text('「 」')
                      .fontSize(fs(this.ts, 34)).fontColor(paletteOf(this.avatarKey()).deep).letterSpacing(3)
                    Text('本机发布的文字动态')
                      .fontSize(fs(this.ts, 10)).fontColor(SUB).margin({ top: 8 })
                  }
                  .width('100%').height(252)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor(paletteOf(this.avatarKey()).paper)
                  .border({ width: 1, color: LINE })
                }
                if (this.siteName().length > 0) {
                  Row({ space: 3 }) {
                    Text('⌖').fontSize(fs(this.ts, 9)).fontColor('#F3E7D4')
                    Text(this.siteName()).fontSize(fs(this.ts, 11)).fontColor(Color.White)
                    Text('›').fontSize(fs(this.ts, 11)).fontColor('#F3E7D4')
                  }
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .margin({ left: 10, bottom: 10 })
                  .backgroundColor('rgba(43,38,34,0.46)').borderRadius(9)
                  .onClick((): void => {
                    goDetail(this.post!.siteId);
                  })
                }
              }
              .width('100%').borderRadius(14).clip(true)

              Row({ space: 10 }) {
                Column() {
                  Text(this.post!.author.substring(0, 1))
                    .fontSize(fs(this.ts, 14)).fontColor(paletteOf(this.avatarKey()).ink).fontWeight(FontWeight.Bold)
                }
                .width(36).height(36).borderRadius(18)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(paletteOf(this.avatarKey()).deep)

                Column({ space: 2 }) {
                  Text(this.post!.author).fontSize(fs(this.ts, 14)).fontColor(INK).fontWeight(FontWeight.Medium)
                  Text(this.post!.role + ' · ' + agoText(this.post!.at)).fontSize(fs(this.ts, 10)).fontColor(SUB)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (this.isMine()) {
                  Text('本机发布')
                    .fontSize(fs(this.ts, 11)).fontColor(SUB)
                    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                    .backgroundColor('rgba(255,255,255,0.72)')
                    .border({ width: 1, color: LINE })
                    .borderRadius(14)
                } else {
                  Text(this.followed ? '已关注' : '+ 关注')
                    .fontSize(fs(this.ts, 11))
                    .fontColor(this.followed ? SUB : '#FFFFFF')
                    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                    .backgroundColor(this.followed ? 'rgba(255,255,255,0.72)' : CLAY)
                    .border({ width: 1, color: this.followed ? LINE : CLAY })
                    .borderRadius(14)
                    .onClick((): void => {
                      StudioStore.get().toggleFollow(this.post!.author);
                    })
                }
              }
              .width('100%')
              .padding(12)
              .backgroundColor('rgba(255,255,255,0.72)')
              .borderRadius(12)
              .border({ width: 1, color: LINE })

              Text(this.post!.text)
                .fontSize(fs(this.ts, 15)).fontColor(INK).lineHeight(fs(this.ts, 24)).width('100%')
                .padding({ left: 4, right: 4 })

              Row({ space: 10 }) {
                Text(this.liked ? `♥ ${likeText(this.post!.likes + 1)}` : `♡ ${likeText(this.post!.likes)}`)
                  .fontSize(fs(this.ts, 12))
                  .fontColor(this.liked ? '#FFFFFF' : CLAY)
                  .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                  .backgroundColor(this.liked ? CLAY : 'rgba(255,255,255,0.72)')
                  .border({ width: 1, color: CLAY })
                  .borderRadius(16)
                  .onClick((): void => {
                    StudioStore.get().toggleLike('p_' + this.post!.id);
                  })
                Text(`评论 ${this.allComments().length}`)
                  .fontSize(fs(this.ts, 12)).fontColor(SUB)
                Blank()
                if (this.post!.kind !== '图文') {
                  Text(this.post!.kind)
                    .fontSize(fs(this.ts, 10)).fontColor(RIVER)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .border({ width: 1, color: RIVER }).borderRadius(9)
                }
              }
              .width('100%')

              Column({ space: 8 }) {
                Text('回话').fontSize(fs(this.ts, 13)).fontColor(INK).fontWeight(FontWeight.Medium)
                if (this.allComments().length === 0) {
                  Text('还没有人回话，抢个一楼').fontSize(fs(this.ts, 11)).fontColor(SUB)
                }
                ForEach(this.allComments(), (c: PostComment, i: number): void => {
                  this.commentRow(c, i >= this.post!.comments.length)
                }, (c: PostComment, i: number): string => `c_${i}_${c.at}`)

                Row({ space: 8 }) {
                  TextInput({ placeholder: '说两句', text: this.draft })
                    .fontSize(fs(this.ts, 13)).fontColor(INK)
                    .placeholderColor('#B7A995')
                    .backgroundColor('rgba(255,255,255,0.86)')
                    .borderRadius(17).height(36).layoutWeight(1)
                    .maxLength(60)
                    .onChange((v: string): void => {
                      this.draft = v;
                    })
                  Text('发送')
                    .fontSize(fs(this.ts, 12)).fontColor('#FFFFFF')
                    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                    .backgroundColor(CLAY).borderRadius(16)
                    .onClick((): void => {
                      this.send();
                    })
                }
                .width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(12)
              .backgroundColor('rgba(255,255,255,0.72)')
              .borderRadius(12)
              .border({ width: 1, color: LINE })
            }
            .width('100%')
            .padding({ left: 14, right: 14, bottom: 24 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
        }
      }
      .width('100%').height('100%')
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
