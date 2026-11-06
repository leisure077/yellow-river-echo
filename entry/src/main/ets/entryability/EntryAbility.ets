import { AbilityConstant, UIAbility, Want, abilityAccessCtrl, Permissions, PermissionRequestResult, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { MemoryStore } from '../service/MemoryStore';
import { StudioStore } from '../service/StudioStore';
import { SyncService } from '../service/SyncService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    let ctx = this.context;
    this.askSyncPermission(ctx);

    windowStage.loadContent('pages/SplashPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'load content failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', '%{public}s', 'content loaded');
    });
  }

  private askSyncPermission(ctx: common.UIAbilityContext): void {
    let perms: Array<Permissions> = ['ohos.permission.DISTRIBUTED_DATASYNC'];
    let atManager = abilityAccessCtrl.createAtManager();
    atManager.requestPermissionsFromUser(ctx, perms).then((res: PermissionRequestResult): void => {
      let states: string[] = [];
      let granted = res.authResults.length > 0;
      for (let i = 0; i < res.authResults.length; i++) {
        let code = res.authResults[i];
        if (code !== 0) {
          granted = false;
        }
        states.push(perms[i] + '=' + code);
      }
      hilog.info(DOMAIN, 'HH_SYNC', 'perm result: %{public}s', states.join(' / '));
      SyncService.get().setPerm(granted, states.join(' / '));
    }).catch((err: Error): void => {
      hilog.warn(DOMAIN, 'HH_SYNC', 'perm request failed: %{public}s', err.message);
      SyncService.get().setPerm(false, 'requestPermissionsFromUser 抛异常：' + err.message);
    });
  }

  onWindowStageDestroy(): void {
  }

  onForeground(): void {
  }

  onBackground(): void {
    MemoryStore.get().flushNow();
    StudioStore.get().flushNow();
    SyncService.get().flushNow();
  }
}
