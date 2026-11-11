import { promptAction } from '@kit.ArkUI';
import { ContentRepo } from '../service/ContentRepo';
import { StudioStore } from '../service/StudioStore';
import { SyncService } from '../service/SyncService';
import { SiteRepo } from '../service/SiteRepo';
import { Post, PostComment } from '../model/Models';
import { fs, INK, SUB, CLAY, agoText, likeText, paletteOf, eraPalette, coverRes } from '../common/Theme';
import { openDrawer, goDetail, goSync, goPost } from '../common/Nav';
import { padX, wideH, frTemplate } from '../common/Breakpoint';

// 社区页：推荐流 + 本机提醒。流里既有随包带的动态，也有这台设备自己发出去的动态。
@Component
export struct SocialView {
  // 字号档位变了要整页重画：不持有这行，切档后这一页还是老字号
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('studioRev') @Watch('syncMine') studioRev: number = 0;
  @StorageLink('dataRev') dataRev: number = 0;
  @StorageLink('syncRev') syncRev: number = 0;
  @StorageLink('bp') bp: string = 'sm';
  @State sub: number = 0;
  @State topic: string = '';
  @State openIds: string[] = [];
  @State cmtIds: string[] = [];
  @State myLikes: string[] = [];
  @State myFollows: string[] = [];

  aboutToAppear(): void {
    this.syncMine();
  }

  // 点赞和关注点了要当场变，绑到状态上才吃得到刷新
  syncMine(): void {
    let st = StudioStore.get();
    this.myLikes = st.likes.slice();
    this.myFollows = st.followed.slice();
  }

  flip(arr: string[], id: string): string[] {
    let out = arr.slice();
    let i = out.indexOf(id);
    if (i >= 0) {
      out.splice(i, 1);
    } else {
      out.push(id);
    }
    return out;
  }

  isOpen(id: string): boolean {
    return this.openIds.indexOf(id) >= 0;
  }

  showCmt(id: string): boolean {
    return this.cmtIds.indexOf(id) >= 0;
  }

  shown(): Post[] {
    return ContentRepo.get().postsOfTopic(this.topic);
  }

  avatarKey(siteId: string): string {
    let s = SiteRepo.get().byId(siteId);
    if (s === undefined) {
      return 'yangshao';
    }
    return eraPalette(s.eras.length > 0 ? s.eras[0] : '');
  }

  // 本机发的动态没有遗址可挂，头像按「我的」里选的那个走，一眼认得出是自己；
  // 配了图也一样，图是相册里的，不挂在遗址上
  avatarKeyOf(p: Post): string {
    if (this.isMine(p)) {
      let keys: string[] = ['yangshao', 'longshan', 'xiashang', 'zhou', 'hantang', 'song'];
      let n = StudioStore.get().profile.avatar;
      return keys[n >= 0 && n < keys.length ? n : 0];
    }
    return this.avatarKey(p.siteId);
  }

  siteName(siteId: string): string {
    let s = SiteRepo.get().byId(siteId);
    return s === undefined ? '' : s.name;
  }

  rowKey(p: Post): string {
    return `${p.id}_${this.isOpen(p.id)}_${this.showCmt(p.id)}` +
      `_${this.myLikes.indexOf('p_' + p.id) >= 0}_${this.myFollows.indexOf(p.author) >= 0}`;
  }

  syncLine(): string {
    let s = SyncService.get();
    if (s.localOnly) {
      return '本机模式：数据只存这台设备';
    }
    return `同步：${s.hint}，待同步 ${s.pendingCount()} 条`;
  }

  @Builder
  subTab(title: string, idx: number) {
    Text(title)
      .fontSize(fs(this.ts, 14))
      .fontColor(this.sub === idx ? INK : SUB)
      .fontWeight(this.sub === idx ? FontWeight.Bold : FontWeight.Normal)
      .padding({ left: 6, right: 6, top: 4, bottom: 4 })
      .borderWidth({ bottom: this.sub === idx ? 2 : 0 })
      .borderColor(CLAY)
      .onClick((): void => {
        this.sub = idx;
      })
  }

  @Builder
  topicChip(title: string, val: string) {
    Text(title)
      .fontSize(fs(this.ts, 12))
      .fontColor(this.topic === val ? Color.White : SUB)
      .padding({ left: 11, right: 11, top: 5, bottom: 5 })
      .borderRadius(13)
      .backgroundColor(this.topic === val ? CLAY : $r('app.color.card_bg'))
      .onClick((): void => {
        this.topic = val;
      })
  }

  @Builder
  commentRow(c: PostComment) {
    Column({ space: 2 }) {
      Row({ space: 6 }) {
        Text(c.author).fontSize(fs(this.ts, 11)).fontColor(INK)
        Text(agoText(c.at)).fontSize(fs(this.ts, 10)).fontColor(SUB)
      }
      Text(c.text).fontSize(fs(this.ts, 12)).fontColor(SUB).lineHeight(fs(this.ts, 18))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .backgroundColor('#F7F2E8')
    .borderRadius(8)
  }

  // 双列瀑布流：图高按 id 散开，两列才会错落成阶梯而不是一排排等高格子
  coverH(id: string): number {
    let n = 0;
    for (let i = 0; i < id.length; i++) {
      n += id.charCodeAt(i);
    }
    let hs: number[] = [216, 158, 196, 174, 208, 146];
    let h = hs[n % hs.length];
    // 宽屏一列能到三百多 vp 宽，图还按手机那套高度就会摊成一条横幅，按比例抬一档
    return wideH(this.bp, h, Math.round(h * 1.25), Math.round(h * 1.4));
  }

  // 瀑布流卡片：图在上、文字压在下，作者和点赞收在最后一行
  // 本机动态的 img 存的是相册 URI，直接给 Image 用；随包动态存的是资源名，要过 coverRes
  imgSrc(p: Post): string | Resource {
    if (p.img.indexOf('://') >= 0) {
      return p.img;
    }
    return coverRes(p.img);
  }

  isMine(p: Post): boolean {
    return StudioStore.get().isMyPost(p.id);
  }

  askDelete(p: Post): void {
    AlertDialog.show({
      title: '删掉这条动态？',
      message: '删了就找不回来了，你在这条下面的回话也一并清掉',
      primaryButton: {
        value: '删',
        fontColor: CLAY,
        action: (): void => {
          StudioStore.get().removeUserPost(p.id);
          promptAction.showToast({ message: '已删除' });
        }
      },
      secondaryButton: { value: '留着', action: (): void => {} }
    });
  }

  @Builder
  postCard(p: Post) {
    Column() {
      Stack({ alignContent: Alignment.BottomStart }) {
        if (p.img.length > 0) {
          Image(this.imgSrc(p))
            .width('100%')
            .height(this.coverH(p.id))
            .objectFit(ImageFit.Cover)
        } else {
          // 本机发的纯文字动态：给一块纸色底，压一个「」符号，别去套随包的实景图
          Column() {
            Text('「 」')
              .fontSize(fs(this.ts, 26))
              .fontColor(paletteOf(this.avatarKeyOf(p)).deep)
              .letterSpacing(2)
          }
          .width('100%')
          .height(this.coverH(p.id))
          .justifyContent(FlexAlign.Center)
          .backgroundColor(paletteOf(this.avatarKeyOf(p)).paper)
          .border({ width: 1, color: '#E5DAC6' })
        }

        if (this.siteName(p.siteId).length > 0) {
          Row({ space: 3 }) {
            Text('⌖').fontSize(fs(this.ts, 9)).fontColor('#F3E7D4')
            Text(this.siteName(p.siteId))
              .fontSize(fs(this.ts, 10))
              .fontColor(Color.White)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .padding({ left: 6, right: 8, top: 2, bottom: 2 })
          .margin({ left: 7, bottom: 7 })
          .backgroundColor('rgba(43,38,34,0.46)')
          .borderRadius(8)
          .onClick((): void => {
            goDetail(p.siteId);
          })
        }

        if (p.kind !== '图文') {
          Row() {
            Text(p.kind)
              .fontSize(fs(this.ts, 9))
              .fontColor(Color.White)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor(p.kind === '问答' ? 'rgba(176,94,67,0.9)' : 'rgba(74,123,140,0.9)')
              .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: 8, bottomRight: 0 })
          }
          .width('100%')
          .height(this.coverH(p.id))
          .padding({ top: 7 })
          .justifyContent(FlexAlign.End)
          .alignItems(VerticalAlign.Top)
          .hitTestBehavior(HitTestMode.Transparent)
        }

        if (this.isMine(p)) {
          Row() {
            Text('本机发布')
              .fontSize(fs(this.ts, 9))
              .fontColor('#FFFFFF')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('rgba(166,85,61,0.9)')
              .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: 8, bottomRight: 0 })
          }
          .width('100%')
          .height(this.coverH(p.id))
          .padding({ top: 7 })
          .justifyContent(FlexAlign.End)
          .alignItems(VerticalAlign.Top)
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
      .width('100%')

      Column({ space: 6 }) {
        Text(p.text)
          .fontSize(fs(this.ts, 12))
          .fontColor(INK)
          .lineHeight(fs(this.ts, 18))
          .width('100%')
          .maxLines(this.isOpen(p.id) ? 10 : 2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (!this.isOpen(p.id) && p.text.length > 34) {
          Text('全文')
            .fontSize(fs(this.ts, 11))
            .fontColor(CLAY)
            .onClick((): void => {
              this.openIds = this.flip(this.openIds, p.id);
              StudioStore.get().markPostRead(p.id);
            })
        }

        if (this.showCmt(p.id)) {
          Column({ space: 5 }) {
            ForEach(p.comments, (c: PostComment): void => {
              this.commentRow(c)
            }, (c: PostComment, idx: number): string => `${p.id}_c${idx}`)
            if (p.comments.length === 0) {
              Text('还没有人回话').fontSize(fs(this.ts, 10)).fontColor(SUB)
            }
          }
          .width('100%')
        }

        Row({ space: 5 }) {
          Column() {
            Text(p.author.substring(0, 1))
              .fontSize(fs(this.ts, 10))
              .fontColor(paletteOf(this.avatarKeyOf(p)).ink)
              .fontWeight(FontWeight.Bold)
          }
          .width(18)
          .height(18)
          .borderRadius(9)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(paletteOf(this.avatarKeyOf(p)).deep)

          Text(p.author)
            .fontSize(fs(this.ts, 11))
            .fontColor(SUB)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text(this.myLikes.indexOf('p_' + p.id) >= 0 ?
            `♥ ${likeText(p.likes + 1)}` : `♡ ${likeText(p.likes)}`)
            .fontSize(fs(this.ts, 11))
            .fontColor(this.myLikes.indexOf('p_' + p.id) >= 0 ? CLAY : SUB)
            .onClick((): void => {
              StudioStore.get().toggleLike('p_' + p.id);
            })
        }
        .width('100%')

        Row({ space: 8 }) {
          Text(agoText(p.at))
            .fontSize(fs(this.ts, 10))
            .fontColor(SUB)
          Text(`评论 ${p.comments.length}`)
            .fontSize(fs(this.ts, 10))
            .fontColor(this.showCmt(p.id) ? INK : SUB)
            .onClick((): void => {
              this.cmtIds = this.flip(this.cmtIds, p.id);
              StudioStore.get().markPostRead(p.id);
            })
          Blank()
          if (this.isMine(p)) {
            // 自己这条只留一个「删除」：半屏卡片再挤一个关注，大字号下就顶出格子了
            Text('删除')
              .fontSize(fs(this.ts, 10))
              .fontColor(SUB)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .border({ width: 1, color: '#D9CDB6' })
              .borderRadius(9)
              .onClick((): void => {
                this.askDelete(p);
              })
          } else {
            Text(this.myFollows.indexOf(p.author) >= 0 ? '已关注' : '+ 关注')
              .fontSize(fs(this.ts, 10))
              .fontColor(this.myFollows.indexOf(p.author) >= 0 ? SUB : CLAY)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .border({ width: 1, color: this.myFollows.indexOf(p.author) >= 0 ? '#D9CDB6' : CLAY })
              .borderRadius(9)
              .onClick((): void => {
                StudioStore.get().toggleFollow(p.author);
              })
          }
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 8, right: 8, top: 8, bottom: 9 })
    }
    .width('100%')
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .clip(true)
    .onClick((): void => {
      // 整卡点开进详情页：全文 + 点赞关注 + 评论回话
      goPost(p.id);
    })
  }

  @Builder
  noteRow(title: string, desc: string, act: string, onTap: () => void) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(title).fontSize(fs(this.ts, 14)).fontColor(INK).fontWeight(FontWeight.Medium)
        Text(desc).fontSize(fs(this.ts, 12)).fontColor(SUB).lineHeight(fs(this.ts, 18))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (act.length > 0) {
        Text(act)
          .fontSize(fs(this.ts, 12))
          .fontColor(CLAY)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .border({ width: 1, color: '#D9CDB6' })
          .borderRadius(11)
          .onClick((): void => {
            onTap();
          })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 11, bottom: 11 })
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(10)
  }

  @Builder
  msgPane() {
    Column({ space: 10 }) {
      Text('本机提醒，非聊天')
        .fontSize(fs(this.ts, 12))
        .fontColor(SUB)
        .width('100%')

      this.noteRow('社区动态',
        `未读 ${StudioStore.get().unread(ContentRepo.get().feed().length)} 条 · ` +
        `已读 ${ContentRepo.get().feed().length - StudioStore.get().unread(ContentRepo.get().feed().length)} 条`,
        '去看动态', (): void => {
          this.sub = 0;
        })

      this.noteRow('同步状态', this.syncLine(), '同步面板', (): void => {
        goSync();
      })

      this.noteRow('每日签到',
        StudioStore.get().checkedToday() ?
          `今天已签到，连续 ${StudioStore.get().streak()} 天，签一次能领一个字` :
          '今天还没签到，签到会拿到一个还没集到的字',
        '去签到', (): void => {
          promptAction.showToast({ message: '在「活动」页签到' });
        })

      this.noteRow('集字进度',
        `已集 ${StudioStore.get().chars.length}/4 字`, '', (): void => {
        })

      if (SyncService.get().conflicts.length > 0) {
        this.noteRow('冲突提醒',
          `${SyncService.get().conflicts.length} 条记录两端都改过，已按最新时间保留，旧版存了副本`,
          '去处理', (): void => {
            goSync();
          })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14 })
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Text('☰')
          .fontSize(fs(this.ts, 18))
          .fontColor(INK)
          .padding({ right: 2 })
          .onClick((): void => {
            openDrawer();
          })
        Text('社群')
          .fontSize(fs(this.ts, 20))
          .fontColor(INK)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        this.subTab('推荐', 0)
        this.subTab('消息', 1)
      }
      .width('100%')
      .padding({ left: padX(this.bp, 14), right: padX(this.bp, 14), top: 12, bottom: 8 })

      if (this.sub === 0) {
        if (ContentRepo.get().feed().length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              this.topicChip('全部', '')
              ForEach(ContentRepo.get().topics(), (t: string): void => {
                this.topicChip(t, t)
              }, (t: string): string => t)
            }
            .padding({ left: padX(this.bp, 14), right: padX(this.bp, 14), top: 2, bottom: 8 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }

        if (this.shown().length === 0) {
          Column({ space: 8 }) {
            Text('社区数据未随包提供').fontSize(fs(this.ts, 15)).fontColor(INK)
            Text('先去档案库看看沿河的遗存').fontSize(fs(this.ts, 12)).fontColor(SUB)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          // 小红书式双列瀑布流：图先占住卡片上半，文字和作者在下半，两列各自错落往下排
          WaterFlow() {
            ForEach(this.shown(), (p: Post): void => {
              FlowItem() {
                this.postCard(p)
              }
            }, (p: Post): string => this.rowKey(p))
          }
          .columnsTemplate(frTemplate(this.bp, 2))
          .columnsGap(9)
          .rowsGap(9)
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .padding({ left: padX(this.bp, 12), right: padX(this.bp, 12), top: 2, bottom: 10 })
        }
      } else {
        Scroll() {
          this.msgPane()
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .alignItems(HorizontalAlign.Start)
  }
}
