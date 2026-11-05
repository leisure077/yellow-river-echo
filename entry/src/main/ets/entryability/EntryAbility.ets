import { AbilityConstant, UIAbility, Want, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { MemoryStore } from '../service/MemoryStore';
import { StudioStore } from '../service/StudioStore';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
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
    });
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
  }

  onBackground(): void {
    MemoryStore.get().flushNow();
    StudioStore.get().flushNow();
  }
}
