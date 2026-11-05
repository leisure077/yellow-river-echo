import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs, fileUri, picker } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { params, claimAssistant } from '../common/Nav';
import { FloatingAssistant } from '../view/FloatingAssistant';

class ExperienceBridge {
  ctx: common.UIAbilityContext;
  constructor(ctx: common.UIAbilityContext) { this.ctx = ctx; }
  back(): void { router.back(); }
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
  aboutToAppear(): void {
    claimAssistant('map');
  }

  aboutToDisappear(): void {
    claimAssistant('home');
  }

  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: ExperienceBridge = new ExperienceBridge(getContext(this) as common.UIAbilityContext);
  private fabSignalAt: number = 0;
  private lastScrollY: number = -1;
  private origin: string = 'https://huanghe.example/experience/';
  private localResource(url: string): WebResourceResponse | null {
    if (!url.startsWith(this.origin)) { return null; }
    let response = new WebResourceResponse();
    try {
      let name = decodeURIComponent(url.substring(this.origin.length).split('?')[0]);
      if (name.includes('..') || !/^[a-zA-Z0-9_./-]+$/.test(name)) { throw new Error('Invalid resource'); }
      let bytes = (getContext(this) as common.UIAbilityContext).resourceManager.getRawFileContentSync('experience/' + name);
      let mime = name.endsWith('.html') ? 'text/html' : name.endsWith('.js') ? 'text/javascript' : name.endsWith('.css') ? 'text/css' :
        name.endsWith('.png') ? 'image/png' : name.endsWith('.jpg') ? 'image/jpeg' : name.endsWith('.glb') ? 'model/gltf-binary' : 'application/octet-stream';
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
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
      Web({ src: this.origin + 'index.html', controller: this.controller })
        .javaScriptAccess(true).domStorageAccess(true).fileAccess(true)
        .zoomAccess(false)
        .onInterceptRequest((event): WebResourceResponse =>
          this.localResource(event.request.getRequestUrl()) as WebResourceResponse)
        .javaScriptProxy({ object: this.bridge, name: 'Native', methodList: ['back', 'journey', 'saveImage', 'shareImage'], controller: this.controller })
        .onScroll((ev: OnScrollEvent): void => {
          let now = Date.now();
          if (ev.yOffset === this.lastScrollY || now - this.fabSignalAt < 80) {
            this.lastScrollY = ev.yOffset;
            return;
          }
          this.lastScrollY = ev.yOffset;
          this.fabSignalAt = now;
          AppStorage.setOrCreate('fabScrollAt', now);
        })
        .onPageEnd((): void => {
          let m = params().type ?? 'map';
          if (!['map', 'travel', 'model', 'footprints'].includes(m)) { m = 'map'; }
          this.controller.runJavaScript('window.startExperience(' + JSON.stringify(m) + ')');
          let routeId = params().id ?? '';
          if (m === 'map' && /^[0-4]$/.test(routeId)) {
            this.controller.runJavaScript('selectRoute(' + routeId + ')');
          }
        }).width('100%').height('100%')
      }.width('100%').height('100%')

      FloatingAssistant({ bottomGap: 20, tag: 'map' })
    }.width('100%').height('100%')
  }
}
