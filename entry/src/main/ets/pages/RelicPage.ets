import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { params } from '../common/Nav';

class RelicBridge {
  back(): void {
    router.back();
  }
}

const MAX_RELIC_ID: number = 5;

@Entry
@Component
struct RelicPage {
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: RelicBridge = new RelicBridge();
  private origin: string = 'https://huanghe.example/';
  private relicId: number = 0;

  aboutToAppear(): void {
    let p = params();
    let id = (p === undefined || p.relic === undefined) ? 0 : p.relic;
    this.relicId = (id >= 0 && id <= MAX_RELIC_ID) ? id : 0;
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
                    name.endsWith('.glb') ? 'model/gltf-binary' :
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
    Column() {
      Web({ src: this.origin + 'relic/index.html?id=' + this.relicId, controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .backgroundColor('#F5EFE4')
        .onInterceptRequest((event): WebResourceResponse =>
          this.localResource(event.request.getRequestUrl()) as WebResourceResponse)
        .javaScriptProxy({
          object: this.bridge,
          name: 'Native',
          methodList: ['back'],
          controller: this.controller
        })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5EFE4')
  }
}
