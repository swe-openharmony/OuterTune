// ====================================================================
// PlayerSession — wraps the system media session (@kit.AVSessionKit) so the
// player publishes now-playing metadata + playback state to the system media
// controls (场景五: notification-shade media card), and accepts play/pause/
// next/prev commands coming back from those controls.
//
// All calls are defensive: if the emulator lacks AVSession support, createAVSession
// throws, the session stays null, and every method becomes a no-op — the in-app
// player keeps working unchanged. hilog markers ('AVSESSION ...') let tests verify
// the app-side push (the shade itself is system UI, not drivable by hypium).
// ====================================================================

import { avSession as AVSessionManager } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'PlayerSession';

export interface SessionCallbacks {
  onPlay: () => void;
  onPause: () => void;
  onNext: () => void;
  onPrev: () => void;
}

export class PlayerSession {
  private session: AVSessionManager.AVSession | null = null;

  async init(ctx: common.UIAbilityContext, cb: SessionCallbacks): Promise<void> {
    try {
      this.session = await AVSessionManager.createAVSession(ctx, 'outertune', 'audio');
      this.session.on('play', () => { hilog.info(0x0000, TAG, 'AVSESSION cmd play'); cb.onPlay(); });
      this.session.on('pause', () => { hilog.info(0x0000, TAG, 'AVSESSION cmd pause'); cb.onPause(); });
      this.session.on('playNext', () => { hilog.info(0x0000, TAG, 'AVSESSION cmd next'); cb.onNext(); });
      this.session.on('playPrevious', () => { hilog.info(0x0000, TAG, 'AVSESSION cmd prev'); cb.onPrev(); });
      await this.session.activate();
      hilog.info(0x0000, TAG, 'AVSESSION created');
    } catch (e) {
      hilog.error(0x0000, TAG, 'AVSESSION create failed: %{public}s', String(e));
      this.session = null;
    }
  }

  async setMetadata(title: string, artist: string, durationSec: number): Promise<void> {
    if (!this.session) { return; }
    try {
      const md: AVSessionManager.AVMetadata = {
        assetId: title, title: title, artist: artist, duration: durationSec * 1000
      };
      await this.session.setAVMetadata(md);
      hilog.info(0x0000, TAG, 'AVSESSION metadata title=%{public}s', title);
    } catch (e) {
      hilog.error(0x0000, TAG, 'setMetadata failed: %{public}s', String(e));
    }
  }

  async setState(isPlaying: boolean, positionSec: number): Promise<void> {
    if (!this.session) { return; }
    try {
      const st: AVSessionManager.AVPlaybackState = {
        state: isPlaying
          ? AVSessionManager.PlaybackState.PLAYBACK_STATE_PLAY
          : AVSessionManager.PlaybackState.PLAYBACK_STATE_PAUSE,
        position: { elapsedTime: positionSec * 1000, updateTime: Date.now() }
      };
      await this.session.setAVPlaybackState(st);
      hilog.info(0x0000, TAG, 'AVSESSION state play=%{public}s', String(isPlaying));
    } catch (e) {
      hilog.error(0x0000, TAG, 'setState failed: %{public}s', String(e));
    }
  }

  async destroy(): Promise<void> {
    if (this.session) {
      try { await this.session.destroy(); } catch (e) { hilog.error(0x0000, TAG, 'destroy failed'); }
      this.session = null;
    }
  }
}
