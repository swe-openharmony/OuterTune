import UIAbility from '@ohos.app.ability.UIAbility';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import { AbilityConstant, Want } from '@kit.AbilityKit';

export default class EntryAbility extends UIAbility {
  // Active page; can be overridden via `aa start ... --ps targetPage <PageName>`.
  // CRITICAL for Phase 5 sanity: onNewWant MUST trigger windowStage.loadContent
  // again so hot-relaunches actually switch pages. Without this, `aa start --ps
  // targetPage pages/X` only works on cold launch (first process start). Since
  // `aa force-stop` requires elevated permissions on HMOS 6.0.2 emulator and
  // `kill -9 <pid>` returns "Operation not permitted" from the shell user,
  // hot-relaunch is the only reliable way to switch pages — hence we must
  // make it actually work.
  private targetPage: string = 'pages/Index';
  private windowStage: window.WindowStage | null = null;

  private resolveTargetPage(requested: string): string {
    if (!requested || requested.length === 0) {
      return 'pages/Index';
    }
    return requested.startsWith('pages/') ? requested : 'pages/' + requested;
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onCreate');
    this.applyTargetFromWant(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onNewWant');
    const changed = this.applyTargetFromWant(want);
    if (changed && this.windowStage) {
      hilog.info(0x0000, 'testTag', 'onNewWant reloading content -> %{public}s', this.targetPage);
      this.windowStage.loadContent(this.targetPage, (err) => {
        if (err.code) {
          hilog.error(0x0000, 'testTag', 'reload failed: %{public}s', JSON.stringify(err));
        }
      });
    }
  }

  private applyTargetFromWant(want: Want): boolean {
    const params = want.parameters;
    if (params && typeof params['targetPage'] === 'string') {
      const requested = params['targetPage'] as string;
      if (requested.length > 0) {
        const resolved = this.resolveTargetPage(requested);
        const changed = resolved !== this.targetPage;
        this.targetPage = resolved;
        AppStorage.SetOrCreate<string>('targetPage', this.targetPage);
        return changed;
      }
    }
    return false;
  }

  onDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    this.windowStage = windowStage;

    windowStage.loadContent(this.targetPage, (err, data) => {
      if (err.code) {
        hilog.error(0x0000, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(0x0000, 'testTag', 'Succeeded in loading the content. Data: %{public}s', JSON.stringify(data));
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(0x0000, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
