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
import { INK, SUB, LOESS, CLAY, paletteOf, SCALE_LABELS, fs } from '../common/Theme';
import { goArchive, goPottery, goTopic, goSync, goCourses, goQuiz, goGuide, goEngineer, closeDrawer, goCompose, goLogin, closeSignOutAsk } from '../common/Nav';

const DANGER: string = '#C0392B';

@Component
struct DrawerPicker {
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
  @State ready: boolean = false;
  @State createOpen: boolean = false;
  @State taps: number = 0;
  @State engineerUnlocked: boolean = false;
  private lastTap: number = 0;

  aboutToAppear(): void {
    let ctx = getContext(this) as common.UIAbilityContext;
    Boot.run(ctx).catch((e: Error): void => {
      console.error('boot: ' + e.message);
    }).finally((): void => {
      this.ready = true;
    });
  }

  @Builder
  footLabel(idx: number, title: string) {
    Column({ space: 3 }) {
      Text(title)
        .fontSize(fs(this.ts, 13))
        .fontColor(this.tab === idx ? INK : SUB)
        .fontWeight(this.tab === idx ? FontWeight.Bold : FontWeight.Normal)
      Circle().width(4).height(4)
        .fill(this.tab === idx ? CLAY : Color.Transparent)
    }
    .padding({ top: 8, bottom: 6 })
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
        .padding({ bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width(272)
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
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        Column() {
          this.createTile('✎', '写笔记', '挑一处遗址记两行', (): void => {
            this.createOpen = false;
            goArchive(2);
          })
        }
        .width('47.5%').margin({ right: '5%', bottom: 12 })
        Column() {
          this.createTile('⌣', '彩陶工坊', '拼一件自己的器物', (): void => {
            this.createOpen = false;
            goPottery();
          })
        }
        .width('47.5%').margin({ bottom: 12 })
        Column() {
          this.createTile('⊚', '知识网络', '把关联摊开看', (): void => {
            this.createOpen = false;
            goTopic();
          })
        }
        .width('47.5%').margin({ right: '5%', bottom: 12 })
        Column() {
          this.createTile('✦', '发动态', '说给河边的人听', (): void => {
            this.createOpen = false;
            goCompose();
          })
        }
        .width('47.5%').margin({ bottom: 12 })
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

          Row() {
            this.footLabel(0, '首页')
            this.footLabel(1, '文创')
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
            .margin({ top: 4 })
            .shadow({ radius: 8, color: 'rgba(43,38,34,0.22)', offsetY: 3 })
            .onClick((): void => {
              this.createOpen = true;
            })
            this.footLabel(2, '社群')
            this.footLabel(3, '我的')
          }
          .width('100%')
          .height(58)
          .justifyContent(FlexAlign.SpaceAround)
          .alignItems(VerticalAlign.Top)
          .backgroundColor($r('app.color.card_bg'))
          .border({ width: { top: 1 }, color: $r('app.color.line') })
        }
      }
      .width('100%')
      .height('100%')

      if (this.ready && this.tab === 0) {
        FloatingAssistant({ bottomGap: 74, tag: 'home' })
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
