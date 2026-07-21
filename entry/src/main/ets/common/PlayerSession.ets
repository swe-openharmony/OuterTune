// UIAbility-owned playback controller. It owns the real AVPlayer and AVSession;
// pages only subscribe to snapshots and issue transport/queue commands.

import { avSession as AVSessionManager } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { resourceManager } from '@kit.LocalizationKit';

const TAG = 'PlayerSession';
const AUDIO_RAW_FILE = 'Hins_fuji_cover.mp3';

export interface SessionTrack {
  id: string;
  title: string;
  artist: string;
  durationSec: number;
}

export interface SessionSnapshot {
  trackId: string;
  positionSec: number;
  durationSec: number;
  isPlaying: boolean;
  isCompleted: boolean;
  artworkAvailable: boolean;
}

export type SessionListener = (snapshot: SessionSnapshot) => void;

export class PlayerSession {
  private context: common.UIAbilityContext | null = null;
  private session: AVSessionManager.AVSession | null = null;
  private player: media.AVPlayer | null = null;
  private playerFd: resourceManager.RawFileDescriptor | null = null;
  private cover: image.PixelMap | null = null;
  private tracks: SessionTrack[] = [];
  private queue: number[] = [];
  private queuePosition: number = 0;
  private repeatMode: number = 0;
  private positionSec: number = 0;
  private durationSec: number = 0;
  private isPlaying: boolean = false;
  private isCompleted: boolean = false;
  private favoriteTrackIds: string[] = [];
  private initialized: boolean = false;
  private autoPlayRequested: boolean = true;
  private endHandled: boolean = false;
  private listeners: SessionListener[] = [];

  private readonly onPlayerStateChange = (state: media.AVPlayerState): void => {
    hilog.info(0x0000, TAG, 'AVPLAYER state=%{public}s', state);
    if (state === 'initialized') {
      this.player?.prepare().catch((e: Error) => {
        hilog.error(0x0000, TAG, 'AVPLAYER prepare failed: %{public}s', String(e));
      });
      return;
    }
    if (state === 'prepared') {
      if (this.player && this.durationSec <= 0 && this.player.duration > 0) {
        this.durationSec = this.player.duration / 1000;
      }
      this.applyLoopMode();
      this.emit();
      if (this.autoPlayRequested) {
        this.autoPlayRequested = false;
        this.play();
      }
      return;
    }
    if (state === 'playing') {
      this.isPlaying = true;
      this.isCompleted = false;
      this.endHandled = false;
      this.emit();
      return;
    }
    if (state === 'paused') {
      this.isPlaying = false;
      this.emit();
      return;
    }
    if (state === 'completed') {
      this.isPlaying = false;
      this.isCompleted = true;
      this.emit();
      this.handleNaturalEnd();
      return;
    }
    if (state === 'error') {
      this.isPlaying = false;
      this.emit();
    }
  };

  private readonly onTimeUpdate = (timeMs: number): void => {
    this.positionSec = Math.max(0, timeMs / 1000);
    this.emit();
  };

  private readonly onDurationUpdate = (durationMs: number): void => {
    this.durationSec = Math.max(0, durationMs / 1000);
    this.emit();
    this.publishMetadata();
  };

  private readonly onSeekDone = (timeMs: number): void => {
    this.positionSec = Math.max(0, timeMs / 1000);
    this.isCompleted = false;
    this.emit();
  };

  private readonly onEndOfStream = (): void => {
    hilog.info(0x0000, TAG, 'AVPLAYER natural end');
    if (this.repeatMode === 2) {
      this.positionSec = 0;
      this.isCompleted = false;
      this.isPlaying = true;
      this.emit();
      return;
    }
    this.handleNaturalEnd();
  };

  private readonly onPlayerError = (error: Error): void => {
    hilog.error(0x0000, TAG, 'AVPLAYER error: %{public}s', String(error));
    this.isPlaying = false;
    this.emit();
  };

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return;
    }
    this.context = ctx;
    this.initialized = true;
    await this.extractExactAlbumCover();
    await this.initAVSession();
    await this.initAVPlayer();
  }

  private async extractExactAlbumCover(): Promise<void> {
    if (!this.context) {
      return;
    }
    let extractor: media.AVMetadataExtractor | null = null;
    let coverFd: resourceManager.RawFileDescriptor | null = null;
    try {
      // Use a dedicated descriptor and release it before AVPlayer acquires its own.
      coverFd = await this.context.resourceManager.getRawFd(AUDIO_RAW_FILE);
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = { fd: coverFd.fd, offset: coverFd.offset, length: coverFd.length };
      this.cover = await extractor.fetchAlbumCover();
      hilog.info(0x0000, TAG, 'ALBUM_COVER exact_mp3 extracted=true');
    } catch (e) {
      this.cover = null;
      hilog.warn(0x0000, TAG, 'ALBUM_COVER exact_mp3 extracted=false reason=%{public}s', String(e));
    } finally {
      if (extractor) {
        try {
          await extractor.release();
        } catch (e) {
          hilog.warn(0x0000, TAG, 'metadata extractor release failed: %{public}s', String(e));
        }
      }
      if (coverFd && this.context) {
        try {
          await this.context.resourceManager.closeRawFd(AUDIO_RAW_FILE);
        } catch (e) {
          hilog.warn(0x0000, TAG, 'cover fd close failed: %{public}s', String(e));
        }
      }
    }
  }

  private async initAVSession(): Promise<void> {
    if (!this.context) {
      return;
    }
    try {
      this.session = await AVSessionManager.createAVSession(this.context, 'outertune', 'audio');
      this.session.on('play', () => {
        hilog.info(0x0000, TAG, 'AVSESSION cmd play');
        this.play();
      });
      this.session.on('pause', () => {
        hilog.info(0x0000, TAG, 'AVSESSION cmd pause');
        this.pause();
      });
      this.session.on('playNext', () => {
        hilog.info(0x0000, TAG, 'AVSESSION cmd next');
        this.next();
      });
      this.session.on('playPrevious', () => {
        hilog.info(0x0000, TAG, 'AVSESSION cmd prev');
        // System previous is an explicit queue navigation command. Unlike the
        // in-app button, it must not degrade to restart-current after 3 seconds.
        this.previous(false);
      });
      await this.session.activate();
      hilog.info(0x0000, TAG, 'AVSESSION created');
    } catch (e) {
      hilog.error(0x0000, TAG, 'AVSESSION create failed: %{public}s', String(e));
      this.session = null;
    }
  }

  private async initAVPlayer(): Promise<void> {
    if (!this.context) {
      return;
    }
    try {
      this.player = await media.createAVPlayer();
      this.player.on('stateChange', this.onPlayerStateChange);
      this.player.on('timeUpdate', this.onTimeUpdate);
      this.player.on('durationUpdate', this.onDurationUpdate);
      this.player.on('seekDone', this.onSeekDone);
      this.player.on('endOfStream', this.onEndOfStream);
      this.player.on('error', this.onPlayerError);
      this.playerFd = await this.context.resourceManager.getRawFd(AUDIO_RAW_FILE);
      this.player.fdSrc = {
        fd: this.playerFd.fd,
        offset: this.playerFd.offset,
        length: this.playerFd.length
      };
      hilog.info(0x0000, TAG, 'AVPLAYER fdSrc exact_mp3 assigned');
    } catch (e) {
      hilog.error(0x0000, TAG, 'AVPLAYER init failed: %{public}s', String(e));
    }
  }

  configureTracks(tracks: SessionTrack[], queue?: number[]): void {
    this.tracks = tracks.slice();
    this.queue = queue ? queue.slice() : tracks.map((_track: SessionTrack, index: number) => index);
    if (this.queue.length === 0) {
      this.queuePosition = 0;
    } else if (this.queuePosition >= this.queue.length) {
      this.queuePosition = 0;
    }
    this.publishMetadata();
    this.emit();
  }

  updateQueue(queue: number[], currentTrackId: string): void {
    this.queue = queue.slice();
    const trackIndex = this.tracks.findIndex((track: SessionTrack) => track.id === currentTrackId);
    const position = this.queue.indexOf(trackIndex);
    this.queuePosition = position >= 0 ? position : 0;
    this.emit();
  }

  selectQueuePosition(position: number, autoPlay: boolean = true): void {
    if (position < 0 || position >= this.queue.length) {
      return;
    }
    this.queuePosition = position;
    this.positionSec = 0;
    this.isCompleted = false;
    this.endHandled = false;
    this.publishMetadata();
    this.seek(0);
    if (autoPlay) {
      this.play();
    }
    this.emit();
  }

  setRepeatMode(mode: number): void {
    this.repeatMode = mode;
    this.applyLoopMode();
  }

  private applyLoopMode(): void {
    if (!this.player) {
      return;
    }
    const state = this.player.state;
    if (state === 'prepared' || state === 'playing' || state === 'paused' || state === 'completed') {
      this.player.loop = this.repeatMode === 2;
    }
  }

  play(): void {
    if (!this.player) {
      this.autoPlayRequested = true;
      return;
    }
    const state = this.player.state;
    if (state === 'prepared' || state === 'paused' || state === 'completed') {
      this.player.play().catch((e: Error) => {
        hilog.error(0x0000, TAG, 'AVPLAYER play failed: %{public}s', String(e));
      });
    } else if (state === 'initialized' || state === 'idle') {
      this.autoPlayRequested = true;
    }
  }

  pause(): void {
    if (this.player?.state === 'playing') {
      this.player.pause().catch((e: Error) => {
        hilog.error(0x0000, TAG, 'AVPLAYER pause failed: %{public}s', String(e));
      });
    }
  }

  seek(positionSec: number): void {
    if (!this.player) {
      return;
    }
    const state = this.player.state;
    if (state === 'prepared' || state === 'playing' || state === 'paused' || state === 'completed') {
      const maxSec = this.durationSec > 0 ? this.durationSec : positionSec;
      const bounded = Math.max(0, Math.min(positionSec, maxSec));
      this.player.seek(Math.round(bounded * 1000));
    }
  }

  previous(restartCurrent: boolean = false): void {
    if (restartCurrent && this.positionSec > 3) {
      this.seek(0);
      return;
    }
    if (this.queue.length === 0) {
      return;
    }
    const previousPosition = this.queuePosition > 0 ? this.queuePosition - 1 : this.queue.length - 1;
    this.selectQueuePosition(previousPosition, true);
  }

  next(): void {
    if (this.queue.length === 0) {
      return;
    }
    if (this.queuePosition < this.queue.length - 1) {
      this.selectQueuePosition(this.queuePosition + 1, true);
    } else if (this.repeatMode === 1) {
      this.selectQueuePosition(0, true);
    } else {
      this.positionSec = this.durationSec;
      this.isPlaying = false;
      this.isCompleted = true;
      this.emit();
    }
  }

  private handleNaturalEnd(): void {
    if (this.endHandled || this.repeatMode === 2) {
      return;
    }
    this.endHandled = true;
    if (this.queuePosition < this.queue.length - 1 || this.repeatMode === 1) {
      this.next();
    } else {
      this.positionSec = this.durationSec;
      this.isPlaying = false;
      this.isCompleted = true;
      this.emit();
    }
  }

  subscribe(listener: SessionListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
    listener(this.snapshot());
  }

  unsubscribe(listener: SessionListener): void {
    this.listeners = this.listeners.filter((item: SessionListener) => item !== listener);
  }

  getQueuePosition(): number {
    return this.queuePosition;
  }

  setFavorite(trackId: string, active: boolean): void {
    if (active && !this.favoriteTrackIds.includes(trackId)) {
      this.favoriteTrackIds.push(trackId);
    } else if (!active) {
      this.favoriteTrackIds = this.favoriteTrackIds.filter((id: string) => id !== trackId);
    }
  }

  isFavorite(trackId: string): boolean {
    return this.favoriteTrackIds.includes(trackId);
  }

  getSnapshot(): SessionSnapshot {
    return this.snapshot();
  }

  private currentTrack(): SessionTrack | null {
    if (this.queue.length === 0 || this.tracks.length === 0) {
      return null;
    }
    return this.tracks[this.queue[this.queuePosition]];
  }

  private snapshot(): SessionSnapshot {
    const track = this.currentTrack();
    return {
      trackId: track ? track.id : '',
      positionSec: this.positionSec,
      durationSec: this.durationSec,
      isPlaying: this.isPlaying,
      isCompleted: this.isCompleted,
      artworkAvailable: this.cover !== null
    };
  }

  private emit(): void {
    const value = this.snapshot();
    this.listeners.forEach((listener: SessionListener) => listener(value));
    this.publishState();
  }

  private async publishMetadata(): Promise<void> {
    const track = this.currentTrack();
    if (!this.session || !track) {
      return;
    }
    try {
      const metadata: AVSessionManager.AVMetadata = {
        assetId: track.id,
        title: track.title,
        artist: track.artist,
        duration: this.durationSec > 0 ? this.durationSec * 1000 : track.durationSec * 1000
      };
      if (this.cover) {
        metadata.mediaImage = this.cover;
      }
      await this.session.setAVMetadata(metadata);
      hilog.info(0x0000, TAG, 'AVSESSION metadata title=%{public}s artwork=%{public}s',
        track.title, String(this.cover !== null));
    } catch (e) {
      hilog.error(0x0000, TAG, 'setMetadata failed: %{public}s', String(e));
    }
  }

  private async publishState(): Promise<void> {
    if (!this.session) {
      return;
    }
    try {
      const state: AVSessionManager.AVPlaybackState = {
        state: this.isPlaying
          ? AVSessionManager.PlaybackState.PLAYBACK_STATE_PLAY
          : AVSessionManager.PlaybackState.PLAYBACK_STATE_PAUSE,
        position: { elapsedTime: this.positionSec * 1000, updateTime: Date.now() }
      };
      await this.session.setAVPlaybackState(state);
    } catch (e) {
      hilog.error(0x0000, TAG, 'setState failed: %{public}s', String(e));
    }
  }

  async destroy(): Promise<void> {
    this.listeners = [];
    if (this.player) {
      try {
        await this.player.release();
      } catch (e) {
        hilog.error(0x0000, TAG, 'AVPLAYER release failed: %{public}s', String(e));
      }
      this.player = null;
    }
    if (this.playerFd && this.context) {
      try {
        await this.context.resourceManager.closeRawFd(AUDIO_RAW_FILE);
      } catch (e) {
        hilog.warn(0x0000, TAG, 'player fd close failed: %{public}s', String(e));
      }
      this.playerFd = null;
    }
    if (this.session) {
      try {
        await this.session.destroy();
      } catch (e) {
        hilog.error(0x0000, TAG, 'AVSESSION destroy failed: %{public}s', String(e));
      }
      this.session = null;
    }
    this.context = null;
    this.initialized = false;
  }
}

// The module exposes one stable controller reference. EntryAbility is the only
// lifecycle owner: it initializes onCreate and releases onDestroy.
export const playerSession: PlayerSession = new PlayerSession();
