import { router, promptAction } from '@kit.ArkUI';
import { StudioStore } from '../service/StudioStore';
import { VerifyGate } from '../service/VerifyGate';
import { ArtCover } from '../view/ArtCover';
import { fs, INK, SUB, LOESS, CLAY, RIVER, LINE, PAPER } from '../common/Theme';

interface AvatarSeed {
  key: string;
  glyph: string;
}

const AVATARS: AvatarSeed[] = [
  { key: 'yangshao', glyph: '陶' },
  { key: 'longshan', glyph: '墨' },
  { key: 'xiashang', glyph: '鼎' },
  { key: 'zhou', glyph: '磬' },
  { key: 'hantang', glyph: '彩' },
  { key: 'song', glyph: '桥' }
];

interface FieldArg {
  label: string;
  holder: string;
  value: string;
  kind: string;
  max: number;
  set: (v: string) => void;
}

interface QuickArg {
  glyph: string;
  label: string;
  act: () => void;
}

@Entry
@Component
struct LoginPage {
  @StorageLink('textScale') ts: number = 1;
  @State mode: string = 'login';
  @State nick: string = '续响者';
  @State pwd: string = '';
  @State pwd2: string = '';
  @State phone: string = '';
  @State code: string = '';
  @State cdLeft: number = 0;
  @State demoCode: string = '';
  @State avatar: number = 0;
  @State agree: boolean = false;
  private cdTimer: number = -1;

  aboutToAppear(): void {
    let last = StudioStore.get().lastAccount();
    if (last !== undefined) {
      this.nick = last.nick;
      this.avatar = last.avatar;
    }
    this.tick();
  }

  aboutToDisappear(): void {
    if (this.cdTimer >= 0) {
      clearInterval(this.cdTimer);
      this.cdTimer = -1;
    }
  }

  isRegister(): boolean {
    return this.mode === 'register';
  }

  avatarSeed(i: number): AvatarSeed {
    return AVATARS[i % AVATARS.length];
  }

  cycleAvatar(): void {
    this.avatar = (this.avatar + 1) % AVATARS.length;
  }

  submit(): void {
    if (!this.agree) {
      promptAction.showToast({ message: '先勾一下用户协议与隐私政策' });
      return;
    }
    let s = StudioStore.get();
    let err = this.isRegister()
      ? s.register(this.nick, this.pwd, this.pwd2, this.avatar, this.phone, this.code)
      : s.login(this.nick, this.pwd);
    if (err.length > 0) {
      promptAction.showToast({ message: err });
      return;
    }
    this.enter(this.isRegister() ? '注册好了，已经替你登进来' : '回来了，接着记');
  }

  sendCode(): void {
    let bad = VerifyGate.phoneErr(this.phone);
    if (bad.length > 0) {
      promptAction.showToast({ message: bad });
      return;
    }
    let gate = VerifyGate.get();
    if (gate.secondsLeft() > 0) {
      promptAction.showToast({ message: '刚发过一条，等倒计时走完' });
      return;
    }
    let issued = gate.issue(this.phone);
    this.code = '';
    this.tick();
    promptAction.showToast({ message: `验证码 ${issued}，5 分钟内有效` });
  }

  tick(): void {
    let gate = VerifyGate.get();
    this.cdLeft = gate.secondsLeft();
    this.demoCode = gate.peek();
    if (this.cdTimer >= 0) {
      clearInterval(this.cdTimer);
      this.cdTimer = -1;
    }
    if (this.cdLeft <= 0 && this.demoCode.length === 0) {
      return;
    }
    this.cdTimer = setInterval((): void => {
      let g = VerifyGate.get();
      this.cdLeft = g.secondsLeft();
      this.demoCode = g.peek();
      if (this.cdLeft <= 0 && this.demoCode.length === 0 && this.cdTimer >= 0) {
        clearInterval(this.cdTimer);
        this.cdTimer = -1;
      }
    }, 1000);
  }

  enter(msg: string): void {
    promptAction.showToast({ message: msg });
    this.pwd = '';
    this.pwd2 = '';
    router.replaceUrl({ url: 'pages/Index' });
  }

  guest(): void {
    if (!this.agree) {
      promptAction.showToast({ message: '先勾一下用户协议与隐私政策' });
      return;
    }
    StudioStore.get().signIn('续响者', this.avatar).then((): void => {
      this.enter('以「续响者」身份进入，数据同样只存本机');
    });
  }

  fillLast(): void {
    let last = StudioStore.get().lastAccount();
    if (last === undefined) {
      promptAction.showToast({ message: '这台设备还没有注册过账号' });
      return;
    }
    this.nick = last.nick;
    this.avatar = last.avatar;
    this.mode = 'login';
    promptAction.showToast({ message: `已填入「${last.nick}」，输口令就能进` });
  }

  inputType(kind: string): InputType {
    if (kind === 'pwd') {
      return InputType.Password;
    }
    if (kind === 'phone') {
      return InputType.PhoneNumber;
    }
    if (kind === 'num') {
      return InputType.Number;
    }
    return InputType.Normal;
  }

  @Builder
  field(arg: FieldArg) {
    Column({ space: 2 }) {
      Text(arg.label).fontSize(fs(this.ts, 11)).fontColor(SUB)
      Row({ space: 4 }) {
        TextInput({ placeholder: arg.holder, text: arg.value })
          .fontSize(fs(this.ts, 15))
          .fontColor(INK)
          .placeholderColor('#B7A995')
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .padding({ left: 0, right: 0 })
          .height(38)
          .layoutWeight(1)
          .maxLength(arg.max)
          .type(this.inputType(arg.kind))
          .onChange(arg.set)
      }
      .width('100%')
      Column().width('100%').height(1).backgroundColor(LINE)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  codeField() {
    Column({ space: 2 }) {
      Text('验证码').fontSize(fs(this.ts, 11)).fontColor(SUB)
      Row({ space: 8 }) {
        TextInput({ placeholder: '6 位数字', text: this.code })
          .fontSize(fs(this.ts, 15))
          .fontColor(INK)
          .placeholderColor('#B7A995')
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .padding({ left: 0, right: 0 })
          .height(38)
          .layoutWeight(1)
          .maxLength(6)
          .type(InputType.Number)
          .onChange((v: string): void => {
            this.code = v;
          })
        Button(this.cdLeft > 0 ? `${this.cdLeft}s 后重发` : '获取验证码')
          .fontSize(fs(this.ts, 12))
          .fontColor(this.cdLeft > 0 ? SUB : '#FFFFFF')
          .backgroundColor(this.cdLeft > 0 ? '#EFE6D8' : RIVER)
          .height(30)
          .borderRadius(15)
          .padding({ left: 12, right: 12 })
          .onClick((): void => {
            this.sendCode();
          })
      }
      .width('100%')
      Column().width('100%').height(1).backgroundColor(LINE)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  quickBtn(arg: QuickArg) {
    Column({ space: 6 }) {
      Text(arg.glyph)
        .fontSize(fs(this.ts, 17)).fontColor(CLAY).fontWeight(FontWeight.Medium)
        .width(46).height(46).textAlign(TextAlign.Center)
        .borderRadius(23)
        .backgroundColor(PAPER)
        .border({ width: 1, color: LINE })
      Text(arg.label).fontSize(fs(this.ts, 10)).fontColor(SUB)
    }
    .onClick((): void => {
      arg.act();
    })
  }

  build() {
    Scroll() {
      Column({ space: 0 }) {
        Row() {
          Text('‹ 返回引导').fontSize(fs(this.ts, 13)).fontColor(SUB)
            .padding({ top: 10, bottom: 10, right: 12 })
            .onClick((): void => {
              router.replaceUrl({ url: 'pages/GuidePage' });
            })
          Blank()
          Text('本机档案').fontSize(fs(this.ts, 11)).fontColor(SUB)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(12)
            .border({ width: 1, color: LINE })
        }
        .width('100%')

        Column({ space: 12 }) {
          Image($r('app.media.river_emblem')).width(108).height(108)

          Column({ space: 4 }) {
            Text(this.isRegister() ? '欢迎注册' : '欢迎续响者')
              .fontSize(fs(this.ts, 25)).fontColor(CLAY).fontWeight(FontWeight.Bold).letterSpacing(4)
            Text('一河千年 · 与你续响')
              .fontSize(fs(this.ts, 11)).fontColor(SUB).letterSpacing(1)
          }
          .margin({ top: 4 })
        }
        .width('100%')
        .padding({ top: 20, bottom: 18 })

        Column({ space: 12 }) {
          this.field({ label: '昵称', holder: '请输入昵称，2-12 个字', value: this.nick, kind: 'text',
            max: 12, set: (v: string): void => {
              this.nick = v;
            } })
          if (this.isRegister()) {
            this.field({ label: '手机号', holder: '11 位手机号，只用于本次校验', value: this.phone,
              kind: 'phone', max: 13, set: (v: string): void => {
                this.phone = v;
              } })
            this.codeField()
            if (this.demoCode.length > 0) {
              Text(`本次验证码 ${this.demoCode}，5 分钟内有效`)
                .fontSize(fs(this.ts, 11)).fontColor(RIVER).fontWeight(FontWeight.Medium)
            }
          }
          this.field({ label: '口令', holder: '请输入 6-16 位口令', value: this.pwd, kind: 'pwd',
            max: 16, set: (v: string): void => {
              this.pwd = v;
            } })
          if (this.isRegister()) {
            this.field({ label: '确认口令', holder: '再输一遍口令', value: this.pwd2, kind: 'pwd',
              max: 16, set: (v: string): void => {
                this.pwd2 = v;
              } })
          }

          Button(this.isRegister() ? '注册并进入' : '登录')
            .fontSize(fs(this.ts, 16)).fontColor('#FFFFFF')
            .backgroundColor(CLAY)
            .width('100%').height(46).borderRadius(8)
            .margin({ top: 4 })
            .onClick((): void => {
              this.submit();
            })

          Button(this.isRegister() ? '已有账号，去登录' : '注册')
            .fontSize(fs(this.ts, 15)).fontColor(CLAY)
            .backgroundColor('#F3E3D3')
            .width('100%').height(46).borderRadius(8)
            .onClick((): void => {
              this.mode = this.isRegister() ? 'login' : 'register';
            })
        }
        .width('100%')
        .padding(18)
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(18)

        Column({ space: 14 }) {
          Row({ space: 10 }) {
            Column().height(1).layoutWeight(1).backgroundColor(LINE)
            Text('快捷登录').fontSize(fs(this.ts, 11)).fontColor(SUB)
            Column().height(1).layoutWeight(1).backgroundColor(LINE)
          }
          .width('100%')

          Row({ space: 34 }) {
            this.quickBtn({ glyph: '响', label: '续响者进入', act: (): void => {
              this.guest();
            } })
            this.quickBtn({ glyph: '本', label: '本机账号', act: (): void => {
              this.fillLast();
            } })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .padding({ top: 22 })

        Row({ space: 6 }) {
          Checkbox()
            .select(this.agree)
            .selectedColor(CLAY)
            .width(16).height(16)
            .onChange((on: boolean): void => {
              this.agree = on;
            })
          Text('我已阅读并同意').fontSize(fs(this.ts, 10)).fontColor(SUB)
          Text('《用户协议》').fontSize(fs(this.ts, 10)).fontColor(RIVER)
            .onClick((): void => {
              promptAction.showToast({ message: '数据只写本机 preferences，不上传服务器；退出登录不会删除收藏与笔记' });
            })
          Text('与').fontSize(fs(this.ts, 10)).fontColor(SUB)
          Text('《隐私政策》').fontSize(fs(this.ts, 10)).fontColor(RIVER)
            .onClick((): void => {
              promptAction.showToast({ message: '口令只存校验摘要，手机号只存掩码，明文不落盘、不出设备' });
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 24, bottom: 30 })
      }
      .width('100%')
      .padding({ left: 18, right: 18 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .backgroundColor('#F1E4C9')
  }
}
