import { AbilityConstant, UIAbility, Want, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { MemoryStore } from '../service/MemoryStore';
import { StudioStore } from '../service/StudioStore';
import { pushBp } from '../common/Breakpoint';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 地图、文物、沙盘、陶艺四处都要建 Web 组件。第一次建节点得现起内核，
    // 那几百毫秒全算在用户点进地图的等待里，所以在这里先把引擎唤起来。
    webview.WebviewController.initializeWebEngine();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    let ctx = this.context;
    let atManager = abilityAccessCtrl.createAtManager();
    let perms: Array<Permissions> = ['ohos.permission.DISTRIBUTED_DATASYNC'];
    atManager.requestPermissionsFromUser(ctx, perms).catch((err: Error): void => {
      hilog.warn(DOMAIN, 'testTag', 'perm denied: %{public}s', err.message);
    });

    windowStage.loadContent('pages/SplashPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'load content failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', '%{public}s', 'content loaded');
      this.trackWidth(windowStage);
    });
  }

  // 平板的列数、留白全靠这个宽度。取的是窗口而不是屏幕，分屏和自由窗口下
  // 也跟着变；旋转、拖窗口都重新算一次写进 AppStorage。
  private trackWidth(stage: window.WindowStage): void {
    try {
      let win = stage.getMainWindowSync();
      let ui = win.getUIContext();
      let apply = (wPx: number): void => {
        pushBp(ui.px2vp(wPx));
      };
      apply(win.getWindowProperties().windowRect.width);
      win.on('windowSizeChange', (size: window.Size): void => {
        apply(size.width);
      });
    } catch (e) {
      // 拿不到宽度就留在默认档 sm，也就是手机布局
      hilog.warn(DOMAIN, 'testTag', 'window width unavailable: %{public}s', (e as Error).message);
    }
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
  }

  onBackground(): void {
    // 退后台前把攒着的写盘请求落地，防杀进程丢数据
    MemoryStore.get().flushNow();
    StudioStore.get().flushNow();
  }
}
