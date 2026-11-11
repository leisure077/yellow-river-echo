import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { params, claimAssistant } from '../common/Nav';
import { FloatingAssistant } from '../view/FloatingAssistant';
import { mapAssetFromCache, putMapAsset } from '../common/MapAssets';
import { INK, SUB, LOESS, PAPER } from '../common/Theme';

class ExperienceBridge {
  ctx: common.UIAbilityContext;
  constructor(ctx: common.UIAbilityContext) { this.ctx = ctx; }
  back(): void { router.back(); }
  // 应用里只有一张行程页 pages/RoutePage（原本指向 pages/JourneyPage，那一页从未存在，点它没反应）。
  journey(): void { router.pushUrl({ url: 'pages/RoutePage' }); }
  private bytes(data: string): Uint8Array {
    if (!data.startsWith('data:image/png;base64,') || data.length > 12000000) { throw new Error('无效的明信片'); }
    return new util.Base64Helper().decodeSync(data.substring(22));
  }
  async saveImage(data: string): Promise<void> {
    try {
      let bytes = this.bytes(data);
      let uris = await new picker.DocumentViewPicker(this.ctx).save({ newFileNames: ['黄河明信片.png'] });
      if (uris.length === 0) { return; }
      let f = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try { fs.writeSync(f.fd, bytes.buffer); } finally { fs.closeSync(f); }
      promptAction.showToast({ message: '明信片已保存' });
    } catch (err) { promptAction.showToast({ message: '保存失败，请重试' }); }
  }
  async shareImage(data: string): Promise<void> {
    try {
      let bytes = this.bytes(data);
      let path = this.ctx.cacheDir + '/postcard_' + Date.now() + '.png';
      let f = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try { fs.writeSync(f.fd, bytes.buffer); } finally { fs.closeSync(f); }
      let share = new systemShare.ShareController(new systemShare.SharedData({ utd: 'general.image', uri: fileUri.getUriFromPath(path) }));
      await share.show(this.ctx, {});
    } catch (err) { promptAction.showToast({ message: '当前设备未能打开分享面板，可先保存图片' }); }
  }
}
@Entry
@Component
struct ExperiencePage {
  // 网页首帧之前 Web 是纯白的，用一层纸色遮罩顶替：既遮住白，也让"卡"看起来像在加载
  @State loaded: boolean = false;
  @State failed: boolean = false;

  aboutToAppear(): void {
    // 进地图页就把悬浮助手交给这一页的实例，压在底下的首页实例不再弹卡片
    claimAssistant('map');
  }

  aboutToDisappear(): void {
    claimAssistant('home');
  }

  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: ExperienceBridge = new ExperienceBridge(getContext(this) as common.UIAbilityContext);
  // 地图页里的悬浮球也要跟着网页滚动收一收
  private fabSignalAt: number = 0;
  private lastScrollY: number = -1;
  // A single intercepted origin keeps ES modules, GLB fetches and storage consistent.
  private origin: string = 'https://huanghe.example/experience/';
  private localResource(url: string): WebResourceResponse | null {
    if (!url.startsWith(this.origin)) { return null; }
    let response = new WebResourceResponse();
    try {
      let name = decodeURIComponent(url.substring(this.origin.length).split('?')[0]);
      if (name.includes('..') || !/^[a-zA-Z0-9_./-]+$/.test(name)) { throw new Error('Invalid resource'); }
      // 命中缓存就不碰磁盘：这个回调是同步的，每读一次 3.9MB 的底图就白一次屏
      let buf = mapAssetFromCache(name);
      if (buf === null) {
        let bytes = (getContext(this) as common.UIAbilityContext).resourceManager.getRawFileContentSync('experience/' + name);
        buf = bytes.buffer as ArrayBuffer;
        putMapAsset(name, buf);
      }
      let mime = name.endsWith('.html') ? 'text/html' : name.endsWith('.js') ? 'text/javascript' : name.endsWith('.css') ? 'text/css' :
        name.endsWith('.png') ? 'image/png' : name.endsWith('.jpg') ? 'image/jpeg' : name.endsWith('.glb') ? 'model/gltf-binary' : 'application/octet-stream';
      response.setResponseData(buf);
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
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
      Web({ src: this.origin + 'index.html', controller: this.controller })
        .javaScriptAccess(true).domStorageAccess(true).fileAccess(true)
        // 关掉 WebView 自带的双指缩放页面，手势才能交给百度地图自己处理
        .zoomAccess(false)
        .onInterceptRequest((event): WebResourceResponse =>
          this.localResource(event.request.getRequestUrl()) as WebResourceResponse)
        .javaScriptProxy({ object: this.bridge, name: 'Native', methodList: ['back', 'journey', 'saveImage', 'shareImage'], controller: this.controller })
        .onScroll((ev: OnScrollEvent): void => {
          // Web 给的是绝对位置，只有真的动了才发信号；80ms 一次足够
          let now = Date.now();
          if (ev.yOffset === this.lastScrollY || now - this.fabSignalAt < 80) {
            this.lastScrollY = ev.yOffset;
            return;
          }
          this.lastScrollY = ev.yOffset;
          this.fabSignalAt = now;
          AppStorage.setOrCreate('fabScrollAt', now);
        })
        // 子资源（某张瓦片）读失败不该把整页判死，只认主帧
        .onErrorReceive((event): void => {
          if (event.request.isMainFrame()) {
            this.failed = true;
          }
        })
        .onPageEnd((): void => {
          this.loaded = true;
          this.failed = false;
          let m = params().type ?? 'map';
          if (!['map', 'travel', 'model', 'footprints'].includes(m)) { m = 'map'; }
          this.controller.runJavaScript('window.startExperience(' + JSON.stringify(m) + ')');
          let routeId = params().id ?? '';
          if (m === 'map' && /^[0-4]$/.test(routeId)) {
            this.controller.runJavaScript('selectRoute(' + routeId + ')');
          }
        }).backgroundColor(PAPER).width('100%').height('100%')
      }.width('100%').height('100%')

      if (!this.loaded) {
        Column({ space: 10 }) {
          if (this.failed) {
            Text('导览图没能打开').fontSize(17).fontColor(INK).fontWeight(FontWeight.Medium)
            Text('可能是这一页的资源没读出来，点一下重新加载').fontSize(12).fontColor(SUB)
              .textAlign(TextAlign.Center)
            Text('重新加载')
              .fontSize(14).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
              .padding({ left: 20, right: 20, top: 9, bottom: 9 })
              .borderRadius(18)
              .backgroundColor(LOESS)
              .margin({ top: 6 })
          } else {
            Text('黄河导览').fontSize(20).fontColor(LOESS).fontWeight(FontWeight.Bold).letterSpacing(2)
            Text('正在展开河岸导览图…').fontSize(12).fontColor(SUB)
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(PAPER)
        .onClick((): void => {
          if (this.failed) {
            this.failed = false;
            this.controller.refresh();
          }
        })
      }

      // 地图页右下角悬浮；地图底部中间有「路线」大按钮，这里留 20vp 靠右不打架
      FloatingAssistant({ bottomGap: 20, tag: 'map' })
    }.width('100%').height('100%')
  }
}
