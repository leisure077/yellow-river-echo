
export class VerifyGate {
  private static readonly inst: VerifyGate = new VerifyGate();

  static get(): VerifyGate {
    return VerifyGate.inst;
  }

  static readonly TTL_MS: number = 5 * 60 * 1000;
  static readonly RESEND_MS: number = 60 * 1000;
  static readonly MAX_TRIES: number = 3;

  private phone: string = '';
  private code: string = '';
  private sentAt: number = 0;
  private tries: number = 0;

  static digits(raw: string): string {
    let out = '';
    for (let i = 0; i < raw.length; i++) {
      let c = raw.charCodeAt(i);
      if (c >= 48 && c <= 57) {
        out += raw.charAt(i);
      }
    }
    return out;
  }

  static phoneErr(raw: string): string {
    let p = VerifyGate.digits(raw);
    if (p.length === 0) {
      return '填一下手机号';
    }
    if (p.length !== 11) {
      return '手机号得是 11 位';
    }
    if (p.charAt(0) !== '1' || p.charAt(1) < '3' || p.charAt(1) > '9') {
      return '这个号段不像手机号';
    }
    return '';
  }

  static mask(p: string): string {
    return p.substring(0, 3) + '****' + p.substring(7);
  }

  peek(): string {
    if (this.code.length === 0) {
      return '';
    }
    if (Date.now() - this.sentAt > VerifyGate.TTL_MS) {
      return '';
    }
    if (this.tries >= VerifyGate.MAX_TRIES) {
      return '';
    }
    return this.code;
  }

  secondsLeft(): number {
    if (this.code.length === 0) {
      return 0;
    }
    let gap = Date.now() - this.sentAt;
    if (gap >= VerifyGate.RESEND_MS) {
      return 0;
    }
    return Math.ceil((VerifyGate.RESEND_MS - gap) / 1000);
  }

  issue(raw: string): string {
    this.phone = VerifyGate.digits(raw);
    this.code = String(Math.floor(100000 + Math.random() * 900000));
    this.sentAt = Date.now();
    this.tries = 0;
    return this.code;
  }

  private dead(): void {
    this.phone = '';
    this.code = '';
    this.sentAt = 0;
    this.tries = 0;
  }

  verify(raw: string, input: string): string {
    if (this.code.length === 0) {
      return '先点一下获取验证码';
    }
    if (this.phone !== VerifyGate.digits(raw)) {
      this.dead();
      return '手机号跟收码的对不上，重新获取一条';
    }
    if (Date.now() - this.sentAt > VerifyGate.TTL_MS) {
      this.dead();
      return '验证码过期了，重新发一条';
    }
    if (this.tries >= VerifyGate.MAX_TRIES) {
      this.dead();
      return '这条验证码作废了，重新获取';
    }
    if (input.trim() !== this.code) {
      this.tries += 1;
      if (this.tries >= VerifyGate.MAX_TRIES) {
        this.dead();
        return '连错三次，这条验证码作废，重新获取';
      }
      return `验证码不对，还能再试 ${VerifyGate.MAX_TRIES - this.tries} 次`;
    }
    this.dead();
    return '';
  }
}
