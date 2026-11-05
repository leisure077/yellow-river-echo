import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';


export const PROBE_MS: number = 2500;

function qstr(s: string): string {
  return '"' + s.split('\\').join('\\\\').split('"').join('\\"') + '"';
}

class Pottery3DBridge {
  modeCb: (m: string) => void = (): void => {};
  errCb: (msg: string) => void = (): void => {};

  setMode(m: string): void {
    this.modeCb(m);
  }

  onErr(msg: string): void {
    this.errCb(msg);
  }
}

@Component
export struct Pottery3D {
  @Prop @Watch('onParam') shape: string = '罐';
  @Prop @Watch('onParam') motif: string = '鱼纹';
  @Prop @Watch('onParam') glaze: string = 'yangshao';
  @Prop @Watch('onParam') pedestal: string = '素台';
  @Prop @Watch('onParam') word: string = '';
  @Prop @Watch('onParam') seed: number = 0;
  onMode: (m: string) => void = (): void => {};
  onErr: (msg: string) => void = (): void => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: Pottery3DBridge = new Pottery3DBridge();
  private origin: string = 'https://huanghe.example/';
  private src: string = '';
  private pageEnd: boolean = false;
  private mode: string = '';

  aboutToAppear(): void {
    this.bridge.modeCb = (m: string): void => {
      this.mode = m;
      this.onMode(m);
    };
    this.bridge.errCb = (msg: string): void => {
      this.onErr(msg);
    };
    this.src = this.origin + 'pottery/index.html?shape=' + encodeURIComponent(this.shape)
      + '&motif=' + encodeURIComponent(this.motif)
      + '&glaze=' + encodeURIComponent(this.glaze)
      + '&box=' + encodeURIComponent(this.pedestal)
      + '&word=' + encodeURIComponent(this.word)
      + '&seed=' + String(Math.floor(this.seed));
  }

  onParam(): void {
    this.sync();
  }

  sync(): void {
    if (!this.pageEnd || this.mode !== '3d') {
      return;
    }
    let js = 'window.__pot && window.__pot.set({shape:' + qstr(this.shape)
      + ',motif:' + qstr(this.motif) + ',glaze:' + qstr(this.glaze)
      + ',box:' + qstr(this.pedestal) + ',word:' + qstr(this.word)
      + ',seed:' + String(Math.floor(this.seed)) + '})';
    try {
      this.controller.runJavaScript(js);
    } catch (e) {
    }
  }

  private localResource(url: string): WebResourceResponse | null {
    if (!url.startsWith(this.origin)) {
      return null;
    }
    let response = new WebResourceResponse();
    try {
      let name = decodeURIComponent(url.substring(this.origin.length).split('?')[0]);
      if (name.length === 0 || name.includes('..') || !/^[a-zA-Z0-9_./-]+$/.test(name)) {
        throw new Error('Invalid resource');
      }
      let bytes = (getContext(this) as common.UIAbilityContext)
        .resourceManager.getRawFileContentSync(name);
      let mime = name.endsWith('.html') ? 'text/html' :
        name.endsWith('.js') ? 'text/javascript' :
          name.endsWith('.css') ? 'text/css' :
            name.endsWith('.json') ? 'application/json' :
              name.endsWith('.png') ? 'image/png' :
                name.endsWith('.jpg') || name.endsWith('.jpeg') ? 'image/jpeg' :
                  name.endsWith('.webp') ? 'image/webp' :
                    name.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream';
      response.setResponseData(bytes.buffer as ArrayBuffer);
      response.setResponseMimeType(mime);
      response.setResponseEncoding('UTF-8');
      response.setResponseCode(200);
      response.setReasonMessage('OK');
    } catch (err) {
      response.setResponseData('Resource unavailable');
      response.setResponseCode(404);
      response.setReasonMessage('Not Found');
    }
    return response;
  }

  build() {
    Stack() {
      Web({ src: this.src, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .backgroundColor('#00000000')
        .onInterceptRequest((event): WebResourceResponse =>
          this.localResource(event.request.getRequestUrl()) as WebResourceResponse)
        .javaScriptProxy({
          object: this.bridge,
          name: 'Native',
          methodList: ['setMode', 'onErr'],
          controller: this.controller
        })
        .onPageEnd((): void => {
          this.pageEnd = true;
          this.sync();
        })
        .onErrorReceive((event): void => {
          if (event.request.isMainFrame()) {
            this.onMode('fallback');
          }
        })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
