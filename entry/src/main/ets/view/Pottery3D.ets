import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';

/*
 * 彩陶工坊的真 3D 预览容器：一个 ArkWeb，页内跑 rawfile/pottery 那套 three.js。
 *
 * 探针就是这一页本身。以前想过「先在 ArkTS 里探一下 WebGL 再决定挂不挂 Web」，
 * 但 ArkWeb 的上下文能不能建，只有它自己启动一次才知道——在 ArkTS 侧另开一个
 * canvas 去试，试的是二维画布，跟 Web 里的 WebGL 不是一回事。所以做法是：
 *   PotteryPage 一上来就把这个组件挂在预览位（先被转台盖住，看不见），
 *   页里 renderer 建得起来 → Native.setMode('3d')，建不起来 → setMode('fallback') + onErr，
 *   两边都没吭声（rawfile 读不到、模块 import 失败、ArkWeb 起不来）→ 宿主观景的超时兜底。
 * 只有明确收到 '3d' 才把上面那层转台撤掉，其余任何情况都留在转台上。
 *
 * 尺寸从挂载起就是最终尺寸，不做「1vp 探针再放大」：
 * 页里的 fit() 按 window.innerWidth 算 letterbox，改尺寸会整页重排、
 * 器物会闪一下。让转台盖在一个已经铺好的 Web 上面，撤掉盖子时下面就是成品。
 *
 * 五维联动走 runJavaScript：URL 只负责首屏，参数变化一律调 window.__pot.set(json)，
 * 由页内 rebuild() 重画贴图。这样「拖动旋转」的手感留在页内（rAF + pointer），
 * ArkTS 侧只在用户改了器型/纹样/釉色/题字/展示座时推一次，两边不打架。
 */

// 探针等多久算「这台设备不行」。真 3D 页要下载并 import three.js（约 600KB，本地读）、
// 建上下文、烘第一张贴图，实测 SwiftShader 软光栅下 1.2s 内就绪；留一倍余量。
export const PROBE_MS: number = 2500;

// 值都是工坊里的固定选项（中文、无引号），但题字是用户可改的字符串，还是转义一下
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
  // 探针结论回调给宿主：'3d' 才撤转台，'fallback' 和超时都留着
  onMode: (m: string) => void = (): void => {};
  onErr: (msg: string) => void = (): void => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: Pottery3DBridge = new Pottery3DBridge();
  private origin: string = 'https://huanghe.example/';
  private src: string = '';
  // 页面没 load 完之前 __pot 还不存在，参数先攒着，onPageEnd 再推
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

  // 把当前五维推给页内。只在页面已加载、且探针确认走得通真 3D 时才推：
  // fallback 那条链路页里根本没有 __pot，推了只是白抛一次异常。
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
      // 控制器还没接上：下一次参数变化或 onPageEnd 会再推一遍
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
          // 主文档都拿不到，页里的探针永远不会回话，直接判 fallback，
          // 不等宿主那 2.5s 超时
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
