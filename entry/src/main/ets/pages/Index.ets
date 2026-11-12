import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { Boot } from '../service/Boot';
import { MemoryStore } from '../service/MemoryStore';
import { StudioStore } from '../service/StudioStore';
import { SyncService } from '../service/SyncService';
import { HomeView } from '../view/HomeView';
import { ShopView } from '../view/ShopView';
import { SocialView } from '../view/SocialView';
import { MineView } from '../view/MineView';
import { FloatingAssistant } from '../view/FloatingAssistant';
import { INK, SUB, LOESS, CLAY, PAPER, paletteOf, SCALE_LABELS, fs } from '../common/Theme';
import { goArchive, goPottery, goTopic, goSync, goCourses, goQuiz, goGuide, goEngineer, closeDrawer, goCompose, goLogin, closeSignOutAsk } from '../common/Nav';
import { warmMapAssets } from '../common/MapAssets';
import { wideH, cellWidthPct, isLastInRow } from '../common/Breakpoint';

// 退出登录是危险操作，面板里这一行单独标红
const DANGER: string = '#C0392B';

// 底栏图标：和首页宫格一套画法，全部用基础形叠出来，不引图片资源也不引 SymbolGlyph。
// 尺寸 24×24vp（屋顶 28 宽）—— 图标摆在文字上方，再大就要把整栏顶到 70vp 以外。
// 选中态只压外层透明度、不给每个形件重算颜色：Builder 的普通参数是快照，
// 把颜色当参数传进去，切完档图标还是上一个 tab 的颜色。
@Component
struct TabGlyph {
  @StorageLink('mainTab') tab: number = 0;
  @Prop idx: number = 0;
  @Prop kind: string = '';

  build() {
    Column() {
      if (this.kind === 'house') {
        Column() {
          Polygon().width(28).height(9).points([[14, 0], [28, 9], [0, 9]]).fill(CLAY)
          Row({ space: 3 }) {
            Column().width(3).height(10).backgroundColor(CLAY)
            Column().width(9).height(10).border({ width: 1.2, color: CLAY })
            Column().width(3).height(10).backgroundColor(CLAY)
          }
          .height(10)
          .margin({ top: 2 })
          Column().width(28).height(3).backgroundColor(CLAY)
        }
        .width(28)
        .height(24)
      } else if (this.kind === 'coin') {
        Stack() {
          Circle().width(24).height(24).fill(CLAY)
          Column().width(7).height(7).backgroundColor(PAPER)
        }
        .width(24)
        .height(24)
      } else if (this.kind === 'ding') {
        Column({ space: 1.5 }) {
          Row({ space: 12 }) {
            Column().width(3).height(4).backgroundColor(CLAY)
            Column().width(3).height(4).backgroundColor(CLAY)
          }
          .width(24)
          .justifyContent(FlexAlign.Center)
          Column().width(24).height(11)
            .borderRadius({ topLeft: 3, topRight: 3, bottomLeft: 12, bottomRight: 12 })
            .backgroundColor(CLAY)
          Row({ space: 5 }) {
            Column().width(3).height(6).backgroundColor(CLAY)
            Column().width(3).height(6).backgroundColor(CLAY)
            Column().width(3).height(6).backgroundColor(CLAY)
          }
          .width(24)
          .justifyContent(FlexAlign.Center)
        }
        .width(24)
        .height(24)
      } else {
        Stack() {
          Column().width(24).height(24).borderRadius(5).backgroundColor(CLAY)
          Column({ space: 3 }) {
            Row({ space: 3 }) {
              Column().width(6).height(6).borderRadius(1.5).backgroundColor(PAPER)
              Column().width(6).height(6).borderRadius(1.5).backgroundColor(PAPER)
            }
            Row({ space: 3 }) {
              Column().width(6).height(6).borderRadius(1.5).backgroundColor(PAPER)
              Column().width(6).height(6).borderRadius(1.5).backgroundColor(PAPER)
            }
          }
        }
        .width(24)
        .height(24)
      }
    }
    .opacity(this.tab === this.idx ? 1 : 0.42)
  }
}

// 字号档位胶囊组。做成组件而不是 @Builder：Builder 的普通参数是快照，
// 点了「大」之后高亮不会跟着变（真机上实测到的高亮卡死）。
@Component
struct DrawerPicker {
  // 字号档位变了要整页重画：不持有这行，切档后这一页还是老字号
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('studioRev') @Watch('refresh') rev: number = 0;
  @State cur: number = 0;

  aboutToAppear(): void {
    this.refresh();
  }

  refresh(): void {
    this.cur = StudioStore.get().scaleStep;
  }

  pick(i: number): void {
    StudioStore.get().setScaleStep(i);
  }

  build() {
    Column({ space: 7 }) {
      Row({ space: 8 }) {
        Text('A').fontSize(fs(this.ts, 15)).fontColor(LOESS).width(20)
        Text('字号').fontSize(fs(this.ts, 15)).fontColor(INK)
      }
      .width('100%')

      Row({ space: 8 }) {
        ForEach(SCALE_LABELS, (lb: string, i: number): void => {
          Text(lb)
            .fontSize(fs(this.ts, 12))
            .textAlign(TextAlign.Center)
            .fontColor(this.cur === i ? '#FFFFFF' : SUB)
            .backgroundColor(this.cur === i ? LOESS : $r('app.color.page_bg'))
            .padding({ top: 6, bottom: 6 })
            .borderRadius(14)
            .layoutWeight(1)
            .onClick((): void => {
              this.pick(i);
            })
        }, (lb: string): string => lb)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }
}

@Entry
@Component
struct Index {
  @StorageLink('mainTab') tab: number = 0;
  @StorageLink('drawerOpen') drawer: boolean = false;
  @StorageLink('signOutAsk') signOutAsk: boolean = false;
  @StorageLink('studioRev') studioRev: number = 0;
  @StorageLink('textScale') ts: number = 1;
  @StorageLink('bp') bp: string = 'sm';
  @State ready: boolean = false;
  @State createOpen: boolean = false;
  // 彩蛋：连点头像 5 次才露出「河工面板」入口
  @State taps: number = 0;
  @State engineerUnlocked: boolean = false;
  private lastTap: number = 0;

  aboutToAppear(): void {
    let ctx = getContext(this) as common.UIAbilityContext;
    Boot.run(ctx).catch((e: Error): void => {
      console.error('boot: ' + e.message);
    }).finally((): void => {
      this.ready = true;
      // 首页站稳之后再异步预热地图那 4MB 核心资源，等用户真点进去时缓存已经满了。
      // 延后一点是为了不和首屏自己的渲染抢主线程。
      setTimeout((): void => {
        warmMapAssets(ctx);
      }, 1200);
    });
  }

  @Builder
  footLabel(idx: number, title: string, art: string) {
    Column({ space: 3 }) {
      TabGlyph({ idx: idx, kind: art })
      Text(title)
        .fontSize(fs(this.ts, 14))
        .fontColor(this.tab === idx ? INK : SUB)
        .fontWeight(this.tab === idx ? FontWeight.Bold : FontWeight.Normal)
    }
    .padding({ top: 6, bottom: 5 })
    .onClick((): void => {
      this.tab = idx;
    })
  }

  @Builder
  drawerRow(icon: string, title: string, note: string, act: () => void) {
    Row({ space: 12 }) {
      Text(icon).fontSize(fs(this.ts, 15)).fontColor(LOESS).width(20)
      Text(title).fontSize(fs(this.ts, 15)).fontColor(INK).layoutWeight(1)
      if (note.length > 0) {
        Text(note).fontSize(fs(this.ts, 12)).fontColor(SUB)
      }
    }
    .width('100%')
    .height(46)
    .padding({ left: 16, right: 16 })
    .onClick((): void => {
      closeDrawer();
      act();
    })
  }

  tapAvatar(): void {
    let now = Date.now();
    // 隔太久就当重新开始数，别让人误触发；但也别要求 1 秒内点完 5 下
    if (now - this.lastTap > 1500) {
      this.taps = 0;
    }
    this.lastTap = now;
    this.taps += 1;
    if (this.taps >= 5) {
      this.taps = 0;
      if (!this.engineerUnlocked) {
        this.engineerUnlocked = true;
        promptAction.showToast({ message: '河工面板已解锁', duration: 1600 });
      }
    }
  }

  @Builder
  drawerPanel() {
    Column() {
      Row({ space: 12 }) {
        Column() {
          Text(StudioStore.get().profile.nick.substring(0, 1))
            .fontSize(fs(this.ts, 19)).fontColor(paletteOf(this.avatarKey()).ink).fontWeight(FontWeight.Bold)
        }
        .width(48).height(48).borderRadius(24)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(paletteOf(this.avatarKey()).deep)
        .onClick((): void => {
          this.tapAvatar();
        })

        Column({ space: 3 }) {
          Text(StudioStore.get().profile.nick).fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Medium)
          Text(this.engineerUnlocked ? '河工面板已解锁' : StudioStore.get().profile.bio)
            .fontSize(fs(this.ts, 11)).fontColor(this.engineerUnlocked ? CLAY : SUB)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 34, bottom: 14 })

      Row({ space: 14 }) {
        this.drawerStat('作品', `${StudioStore.get().works.length}`)
        this.drawerStat('收藏', `${MemoryStore.get().favsActive().length}`)
        this.drawerStat('笔记', `${MemoryStore.get().notesActive().length}`)
        this.drawerStat('连签', `${StudioStore.get().streak()}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 14 })

      Divider().strokeWidth(1).color($r('app.color.line')).margin({ left: 16, right: 16 })

      Scroll() {
        Column() {
          this.drawerRow('◫', '档案库', '20 处遗址', (): void => {
            goArchive(0);
          })
          this.drawerRow('◇', '我的收藏', '', (): void => {
            goArchive(1);
          })
          this.drawerRow('✎', '我的笔记', '', (): void => {
            goArchive(2);
          })
          this.drawerRow('⌣', '彩陶工坊', 'DIY', (): void => {
            goPottery();
          })
          this.drawerRow('☼', '课程影像', '', (): void => {
            goCourses();
          })
          this.drawerRow('⊚', '主题知识网络', '', (): void => {
            goTopic();
          })
          this.drawerRow('？', '趣味自测', '测测你是哪一段', (): void => {
            goQuiz('drawer');
          })
          this.drawerRow('⇄', '同步面板', '', (): void => {
            goSync();
          })
          if (this.engineerUnlocked) {
            this.drawerRow('⚙', '河工面板', '同步状态与行数', (): void => {
              goEngineer();
            })
          }

          Divider().strokeWidth(1).color($r('app.color.line')).margin({ left: 16, right: 16, top: 6, bottom: 6 })

          // 标题一行、胶囊一行：272vp 的边侧栏塞不下"标题 + 三个胶囊"同行，实测会切掉最后一档
          DrawerPicker()

          Row({ space: 12 }) {
            Text('◎').fontSize(fs(this.ts, 15)).fontColor(LOESS).width(20)
            Text('离线模式').fontSize(fs(this.ts, 15)).fontColor(INK).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: SyncService.get().localOnly })
              .selectedColor(LOESS)
              .onChange((on: boolean): void => {
                SyncService.get().setLocalOnly(on);
              })
          }
          .width('100%')
          .height(46)
          .padding({ left: 16, right: 16 })

          Divider().strokeWidth(1).color($r('app.color.line')).margin({ left: 16, right: 16, top: 6, bottom: 6 })

          this.drawerRow('↻', '重看引河', '', (): void => {
            StudioStore.get().redoGuide();
            goGuide();
          })
          this.drawerRow('↧', '备份与恢复', '在「我的」里', (): void => {
            this.tab = 3;
          })
        }
        .width('100%')
        // 原来底下那行版本小字删了，留点呼吸空间，别让最后一行贴着面板底
        .padding({ bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width(wideH(this.bp, 272, 300, 320))
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.card_bg'))
  }

  @Builder
  drawerStat(title: string, value: string) {
    Column({ space: 2 }) {
      Text(value).fontSize(fs(this.ts, 16)).fontColor(INK).fontWeight(FontWeight.Bold)
      Text(title).fontSize(fs(this.ts, 10)).fontColor(SUB)
    }
  }

  avatarKey(): string {
    let n = StudioStore.get().profile.avatar;
    let keys: string[] = ['yangshao', 'longshan', 'xiashang', 'zhou', 'hantang', 'song'];
    return keys[n >= 0 && n < keys.length ? n : 0];
  }

  @Builder
  createSheet() {
    Column() {
      Column().width(38).height(4).borderRadius(2).backgroundColor('#D9CDB6')
        .margin({ top: 10, bottom: 14 })
      Text('记点什么')
        .fontSize(fs(this.ts, 13)).fontColor(SUB)
      // 四个入口两行排，宽度按 (100% - gap)/2 算，别用 layoutWeight，
      // 否则换行后最后一格会被挤成半宽
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        Column() {
          this.createTile('✎', '写笔记', '挑一处遗址记两行', (): void => {
            this.createOpen = false;
            goArchive(2);
          })
        }
        .width(cellWidthPct(this.bp, 2, 5)).margin({ right: isLastInRow(this.bp, 2, 0) ? 0 : '5%', bottom: 12 })
        Column() {
          this.createTile('⌣', '彩陶工坊', '拼一件自己的器物', (): void => {
            this.createOpen = false;
            goPottery();
          })
        }
        .width(cellWidthPct(this.bp, 2, 5)).margin({ right: isLastInRow(this.bp, 2, 1) ? 0 : '5%', bottom: 12 })
        Column() {
          this.createTile('⊚', '知识网络', '把关联摊开看', (): void => {
            this.createOpen = false;
            goTopic();
          })
        }
        .width(cellWidthPct(this.bp, 2, 5)).margin({ right: isLastInRow(this.bp, 2, 2) ? 0 : '5%', bottom: 12 })
        Column() {
          this.createTile('✦', '发动态', '说给河边的人听', (): void => {
            this.createOpen = false;
            goCompose();
          })
        }
        .width(cellWidthPct(this.bp, 2, 5)).margin({ right: isLastInRow(this.bp, 2, 3) ? 0 : '5%', bottom: 12 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    }
    .width('100%')
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius({ topLeft: 18, topRight: 18 })
  }

  @Builder
  createTile(icon: string, title: string, note: string, act: () => void) {
    Column({ space: 5 }) {
      Text(icon).fontSize(fs(this.ts, 20)).fontColor(LOESS)
      Text(title).fontSize(fs(this.ts, 13)).fontColor(INK).fontWeight(FontWeight.Medium)
      Text(note).fontSize(fs(this.ts, 9)).fontColor(SUB).maxLines(2).textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(96)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.page_bg'))
    .borderRadius(12)
    .onClick((): void => {
      act();
    })
  }

  sessionNick(): string {
    return StudioStore.get().profile.nick;
  }

  sessionAccN(): number {
    return StudioStore.get().accounts.length;
  }

  // 退出登录：底部动作面板。切换账号 / 退出登录两条动作，危险的那条标红，
  // 取消单独一张卡，点遮罩也能收回去。
  // 面板挂在 Index 而不是 MineView：底栏是这一页的兄弟节点，写在「我的」里盖不住它
  @Builder
  signOutSheet() {
    Column() {
      Column() {
        Column({ space: 6 }) {
          Row({ space: 10 }) {
            Column() {
              Text(this.sessionNick().substring(0, 1))
                .fontSize(fs(this.ts, 16)).fontColor(paletteOf(this.avatarKey()).ink).fontWeight(FontWeight.Bold)
            }
            .width(40).height(40).borderRadius(20)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(paletteOf(this.avatarKey()).deep)

            Column({ space: 2 }) {
              Text(this.sessionNick().length > 0 ? `当前会话「${this.sessionNick()}」` : '当前没有会话')
                .fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`本机已注册 ${this.sessionAccN()} 个账号 · 数据不上传服务器`)
                .fontSize(fs(this.ts, 11)).fontColor(SUB)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')

          Text('退出只关掉这次会话：收藏、笔记、作品都原样留在这台设备上，重新登录接着用。')
            .fontSize(fs(this.ts, 11)).fontColor(SUB).lineHeight(fs(this.ts, 17))
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 14, right: 14, top: 14, bottom: 12 })

        Divider().color($r('app.color.line'))

        Row({ space: 10 }) {
          Text('⇄').fontSize(fs(this.ts, 15)).fontColor(LOESS).width(20).textAlign(TextAlign.Center)
          Text('切换账号').fontSize(fs(this.ts, 15)).fontColor(INK).layoutWeight(1)
          Text('换个本机账号登录').fontSize(fs(this.ts, 11)).fontColor(SUB)
        }
        .width('100%').height(52).padding({ left: 14, right: 14 })
        .onClick((): void => {
          closeSignOutAsk();
          StudioStore.get().signOut();
          promptAction.showToast({ message: '换个账号：填昵称输口令，或注册新的' });
          goLogin();
        })

        Divider().color($r('app.color.line'))

        Row({ space: 10 }) {
          Text('⏻').fontSize(fs(this.ts, 15)).fontColor(DANGER).width(20).textAlign(TextAlign.Center)
          Text('退出登录').fontSize(fs(this.ts, 15)).fontColor(DANGER).fontWeight(FontWeight.Medium).layoutWeight(1)
          Text('危险操作').fontSize(fs(this.ts, 11)).fontColor(DANGER)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor('#F7E3E0').borderRadius(9)
        }
        .width('100%').height(52).padding({ left: 14, right: 14 })
        .onClick((): void => {
          closeSignOutAsk();
          StudioStore.get().signOut();
          promptAction.showToast({ message: '已退出登录，本机数据原样留着' });
          goLogin();
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(14)

      Row() {
        Text('取消').fontSize(fs(this.ts, 15)).fontColor(INK).fontWeight(FontWeight.Medium)
          .width('100%').height(52).textAlign(TextAlign.Center)
      }
      .width('100%')
      .margin({ top: 8 })
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(14)
      .onClick((): void => {
        closeSignOutAsk();
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 14 })
    .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
      .animation({ duration: 200, curve: Curve.EaseOut }))
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (!this.ready) {
          Column({ space: 12 }) {
            Text('黄河续响平台').fontSize(fs(this.ts, 24)).fontColor(LOESS).fontWeight(FontWeight.Bold)
            Text('正在整理河岸的旧时光…').fontSize(fs(this.ts, 12)).fontColor(SUB)
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Column() {
            if (this.tab === 0) {
              HomeView()
            } else if (this.tab === 1) {
              ShopView()
            } else if (this.tab === 2) {
              SocialView()
            } else {
              MineView()
            }
          }
          .layoutWeight(1)

          // 外层满宽画背景和分隔线，五个 tab 交给内层 SpaceAround 均匀铺满整条底栏。
          // 早先是整条 Row 按断点收到 62%/46%，平板上两头露出页面底色，看着像没画完。
          Row() {
            Row() {
              this.footLabel(0, '首页', 'house')
              this.footLabel(1, '文创', 'coin')
              Column() {
                Text('+')
                  .fontSize(fs(this.ts, 24))
                  .fontColor('#FFFFFF')
                  .fontWeight(FontWeight.Bold)
              }
              .width(44)
              .height(44)
              .borderRadius(22)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(CLAY)
              .margin({ top: 6 })
              .shadow({ radius: 8, color: 'rgba(43,38,34,0.22)', offsetY: 3 })
              .onClick((): void => {
                this.createOpen = true;
              })
              this.footLabel(2, '社群', 'ding')
              this.footLabel(3, '我的', 'seal')
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.SpaceAround)
            .alignItems(VerticalAlign.Top)
          }
          .width('100%')
          .height(wideH(this.bp, 68, 74, 80))
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: { top: 1 }, color: $r('app.color.line') })
        }
      }
      .width('100%')
      .height('100%')

      // 只在首页露出；底栏 68vp，再留 16vp 呼吸空间
      if (this.ready && this.tab === 0) {
        FloatingAssistant({ bottomGap: wideH(this.bp, 84, 90, 96), tag: 'home' })
      }

      if (this.createOpen) {
        Column() {
          Column().layoutWeight(1)
            .width('100%')
            .onClick((): void => {
              this.createOpen = false;
            })
          this.createSheet()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(43,38,34,0.38)')
      }

      if (this.drawer) {
        Stack({ alignContent: Alignment.Start }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(43,38,34,0.40)')
            .onClick((): void => {
              closeDrawer();
            })
          this.drawerPanel()
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: 180 }))
      }

      if (this.signOutAsk) {
        Column() {
          // 遮罩：点空白处也能收回去
          Column().layoutWeight(1)
            .width('100%')
            .onClick((): void => {
              closeSignOutAsk();
            })
          this.signOutSheet()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(43,38,34,0.45)')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }
}
