// UIAbility-owned playback owner. Pages receive immutable snapshots and issue commands;
// they never own queue, current-track, mode, playback, artwork, or favorite truth.

import { avSession as AVSessionManager } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { resourceManager } from '@kit.LocalizationKit';
import { media } from '@kit.MediaKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'PlayerSession';
const FIXTURE_FILE = 'mock_player.json';
const ARTWORK_RAW_FILE = 'fixture_artwork.png';
const FAVORITE_STORE = 'outune_player';
const FAVORITE_KEY = 'favorite_track_ids';
const AV_QUEUE_ID = 'outertune-playable-queue';
const AV_QUEUE_NAME = 'OuterTune queue';

export class SessionLyricLine {
  timeSec: number;
  text: string;

  constructor(timeSec: number, text: string) {
    this.timeSec = timeSec;
    this.text = text;
  }
}

export class SessionTrack {
  id: string;
  title: string;
  artist: string;
  durationSec: number;
  mediaFile: string;
  lyrics: SessionLyricLine[];

  constructor(id: string, title: string, artist: string, durationSec: number,
    mediaFile: string, lyrics: SessionLyricLine[]) {
    this.id = id;
    this.title = title;
    this.artist = artist;
    this.durationSec = durationSec;
    this.mediaFile = mediaFile;
    this.lyrics = lyrics;
  }
}

interface FixtureLyricLine {
  timeSec: number;
  text: string;
}

interface FixtureTrack {
  id: string;
  title: string;
  artist: string;
  durationSec: number;
  mediaFile: string;
  lyrics: FixtureLyricLine[];
}

interface PlayerFixture {
  tracks: FixtureTrack[];
}

export class SessionSnapshot {
  trackId: string = '';
  currentTrack: SessionTrack | null = null;
  queueTracks: SessionTrack[] = [];
  queuePosition: number = 0;
  positionSec: number = 0;
  durationSec: number = 0;
  isPlaying: boolean = false;
  isCompleted: boolean = false;
  isShuffled: boolean = false;
  repeatMode: number = 0;
  isFavorite: boolean = false;
  canPrevious: boolean = false;
  canNext: boolean = false;
  artwork: image.PixelMap | null = null;
}

export type SessionListener = (snapshot: SessionSnapshot) => void;

class SourceCallbacks {
  private owner: PlayerSession;
  private player: media.AVPlayer;
  private generation: number;

  constructor(owner: PlayerSession, player: media.AVPlayer, generation: number) {
    this.owner = owner;
    this.player = player;
    this.generation = generation;
  }

  readonly stateChange = (state: media.AVPlayerState): void => {
    this.owner.handlePlayerStateChange(this.player, this.generation, state);
  };

  readonly timeUpdate = (timeMs: number): void => {
    this.owner.handleTimeUpdate(this.player, this.generation, timeMs);
  };

  readonly durationUpdate = (durationMs: number): void => {
    this.owner.handleDurationUpdate(this.player, this.generation, durationMs);
  };

  readonly seekDone = (timeMs: number): void => {
    this.owner.handleSeekDone(this.player, this.generation, timeMs);
  };

  readonly error = (error: Error): void => {
    this.owner.handlePlayerError(this.player, this.generation, error);
  };
}

export class PlayerSession {
  private context: common.UIAbilityContext | null = null;
  private session: AVSessionManager.AVSession | null = null;
  private player: media.AVPlayer | null = null;
  private playerCallbacks: SourceCallbacks | null = null;
  private playerFd: resourceManager.RawFileDescriptor | null = null;
  private playerFdName: string = '';
  private sourceTrackId: string = '';
  private generation: number = 0;
  private operationTask: Promise<void> = Promise.resolve();
  private publicationTask: Promise<void> = Promise.resolve();
  private initializationTask: Promise<void> = Promise.resolve();
  private initializationStarted: boolean = false;
  private initialized: boolean = false;
  private isDestroying: boolean = false;
  private artwork: image.PixelMap | null = null;
  private tracks: SessionTrack[] = [];
  private queueTrackIds: string[] = [];
  private naturalTrackIds: string[] = [];
  private queuePosition: number = 0;
  private repeatMode: number = 0;
  private isShuffled: boolean = false;
  private positionSec: number = 0;
  private durationSec: number = 0;
  private isPlaying: boolean = false;
  private isCompleted: boolean = false;
  private favoriteTrackIds: string[] = [];
  private autoPlayRequested: boolean = true;
  private completionHandled: boolean = false;
  private playCommandRegistered: boolean = false;
  private pauseCommandRegistered: boolean = false;
  private nextCommandRegistered: boolean = false;
  private previousCommandRegistered: boolean = false;
  private listeners: SessionListener[] = [];

  private readonly onSessionPlay = (): void => {
    this.play();
  };

  private readonly onSessionPause = (): void => {
    this.pause();
  };

  private readonly onSessionNext = (): void => {
    this.next();
  };

  private readonly onSessionPrevious = (): void => {
    this.previous();
  };

  async init(ctx: common.UIAbilityContext): Promise<void> {
    if (!this.initializationStarted) {
      this.isDestroying = false;
      this.initializationStarted = true;
      this.initializationTask = this.initialize(ctx);
    }
    await this.initializationTask;
  }

  private async initialize(ctx: common.UIAbilityContext): Promise<void> {
    this.context = ctx;
    await this.loadFixture();
    await this.loadFavorites();
    await this.loadArtwork();
    await this.initAVSession();
    this.initialized = true;
    const track = this.currentTrack();
    if (track) {
      this.requestSource(track, true);
    } else {
      this.emit();
    }
  }

  private async loadFixture(): Promise<void> {
    if (!this.context) {
      return;
    }
    const bytes: Uint8Array = await this.context.resourceManager.getRawFileContent(FIXTURE_FILE);
    const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    const fixture = JSON.parse(decoder.decodeToString(bytes)) as PlayerFixture;
    const loaded: SessionTrack[] = [];
    fixture.tracks.forEach((item: FixtureTrack): void => {
      const lyrics: SessionLyricLine[] = [];
      item.lyrics.forEach((line: FixtureLyricLine): void => {
        lyrics.push(new SessionLyricLine(line.timeSec, line.text));
      });
      loaded.push(new SessionTrack(
        item.id, item.title, item.artist, item.durationSec, item.mediaFile, lyrics
      ));
    });
    this.tracks = loaded;
    this.naturalTrackIds = loaded.map((track: SessionTrack): string => track.id);
    this.queueTrackIds = this.naturalTrackIds.slice();
    this.queuePosition = 0;
    const first = this.currentTrack();
    if (first) {
      this.durationSec = first.durationSec;
    }
    this.emit();
  }

  private async loadFavorites(): Promise<void> {
    if (!this.context) {
      return;
    }
    try {
      const store = await preferences.getPreferences(this.context, { name: FAVORITE_STORE });
      const raw = await store.get(FAVORITE_KEY, '') as string;
      this.favoriteTrackIds = raw.length > 0 ? raw.split('\n') : [];
      this.emit();
    } catch (e) {
      this.favoriteTrackIds = [];
      hilog.error(0x0000, TAG, 'favorite load failed: %{public}s', String(e));
    }
  }

  private async loadArtwork(): Promise<void> {
    if (!this.context) {
      return;
    }
    let source: image.ImageSource | null = null;
    try {
      const bytes: Uint8Array = await this.context.resourceManager.getRawFileContent(ARTWORK_RAW_FILE);
      source = image.createImageSource(bytes.buffer as ArrayBuffer);
      this.artwork = await source.createPixelMap({
        desiredSize: { width: 1024, height: 1024 },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      this.emit();
    } catch (e) {
      this.artwork = null;
      hilog.error(0x0000, TAG, 'fixture artwork decode failed: %{public}s', String(e));
    } finally {
      if (source) {
        try {
          await source.release();
        } catch (e) {
          hilog.warn(0x0000, TAG, 'artwork source release failed: %{public}s', String(e));
        }
      }
    }
  }

  private async initAVSession(): Promise<void> {
    if (!this.context) {
      return;
    }
    let provisionalSession: AVSessionManager.AVSession | null = null;
    let playRegistered = false;
    let pauseRegistered = false;
    let nextRegistered = false;
    let previousRegistered = false;
    let sessionTransferred = false;
    try {
      provisionalSession = await AVSessionManager.createAVSession(this.context, 'outertune', 'audio');
      provisionalSession.on('play', this.onSessionPlay);
      playRegistered = true;
      provisionalSession.on('pause', this.onSessionPause);
      pauseRegistered = true;
      const initialSnapshot = this.snapshot();
      if (initialSnapshot.canPrevious) {
        provisionalSession.on('playPrevious', this.onSessionPrevious);
        previousRegistered = true;
      }
      if (initialSnapshot.canNext) {
        provisionalSession.on('playNext', this.onSessionNext);
        nextRegistered = true;
      }
      await this.publishSnapshotToSession(provisionalSession, initialSnapshot);
      await provisionalSession.activate();
      if (this.isDestroying) {
        throw new Error('AVSession initialization interrupted by shutdown');
      }
      this.session = provisionalSession;
      this.playCommandRegistered = playRegistered;
      this.pauseCommandRegistered = pauseRegistered;
      this.nextCommandRegistered = nextRegistered;
      this.previousCommandRegistered = previousRegistered;
      sessionTransferred = true;
    } catch (e) {
      hilog.error(0x0000, TAG, 'AVSESSION create failed: %{public}s', String(e));
    } finally {
      if (!sessionTransferred && provisionalSession) {
        if (playRegistered) {
          try {
            provisionalSession.off('play', this.onSessionPlay);
          } catch (e) {
            hilog.warn(0x0000, TAG, 'provisional AVSESSION play off failed: %{public}s', String(e));
          }
        }
        if (pauseRegistered) {
          try {
            provisionalSession.off('pause', this.onSessionPause);
          } catch (e) {
            hilog.warn(0x0000, TAG, 'provisional AVSESSION pause off failed: %{public}s', String(e));
          }
        }
        if (nextRegistered) {
          try {
            provisionalSession.off('playNext', this.onSessionNext);
          } catch (e) {
            hilog.warn(0x0000, TAG, 'provisional AVSESSION next off failed: %{public}s', String(e));
          }
        }
        if (previousRegistered) {
          try {
            provisionalSession.off('playPrevious', this.onSessionPrevious);
          } catch (e) {
            hilog.warn(0x0000, TAG, 'provisional AVSESSION previous off failed: %{public}s', String(e));
          }
        }
        try {
          await provisionalSession.destroy();
        } catch (e) {
          hilog.warn(0x0000, TAG, 'provisional AVSESSION destroy failed: %{public}s', String(e));
        }
      }
    }
  }

  private enqueueOperation(operation: () => Promise<void>, name: string): void {
    if (this.isDestroying) {
      return;
    }
    this.operationTask = this.operationTask.then(operation).catch((e: Error): void => {
      hilog.error(0x0000, TAG, 'AVPLAYER %{public}s failed: %{public}s', name, String(e));
      this.isPlaying = false;
      this.emit();
    });
  }

  private requestSource(track: SessionTrack, autoPlay: boolean): void {
    if (this.isDestroying) {
      return;
    }
    this.generation += 1;
    const requestGeneration = this.generation;
    this.autoPlayRequested = autoPlay;
    this.enqueueOperation(async (): Promise<void> => {
      await this.switchSource(track, requestGeneration);
    }, 'source switch');
  }

  private async switchSource(track: SessionTrack, requestGeneration: number): Promise<void> {
    if (!this.context || requestGeneration !== this.generation || this.isDestroying) {
      return;
    }
    await this.releasePlayer();
    const sourceContext = this.context;
    if (!sourceContext || requestGeneration !== this.generation || this.isDestroying) {
      return;
    }
    let provisionalPlayer: media.AVPlayer | null = null;
    let provisionalFd: resourceManager.RawFileDescriptor | null = null;
    let playerTransferred = false;
    let fdTransferred = false;
    try {
      provisionalPlayer = await media.createAVPlayer();
      if (requestGeneration !== this.generation || this.isDestroying) {
        return;
      }
      const callbacks = new SourceCallbacks(this, provisionalPlayer, requestGeneration);
      provisionalPlayer.on('stateChange', callbacks.stateChange);
      provisionalPlayer.on('timeUpdate', callbacks.timeUpdate);
      provisionalPlayer.on('durationUpdate', callbacks.durationUpdate);
      provisionalPlayer.on('seekDone', callbacks.seekDone);
      provisionalPlayer.on('error', callbacks.error);
      provisionalFd = await sourceContext.resourceManager.getRawFd(track.mediaFile);
      if (requestGeneration !== this.generation || this.isDestroying) {
        return;
      }
      provisionalPlayer.fdSrc = {
        fd: provisionalFd.fd,
        offset: provisionalFd.offset,
        length: provisionalFd.length
      };
      if (requestGeneration !== this.generation || this.isDestroying) {
        return;
      }
      this.player = provisionalPlayer;
      this.playerCallbacks = callbacks;
      this.playerFd = provisionalFd;
      this.playerFdName = track.mediaFile;
      this.sourceTrackId = track.id;
      playerTransferred = true;
      fdTransferred = true;
    } finally {
      if (!playerTransferred && provisionalPlayer && provisionalPlayer.state !== 'released') {
        try {
          await provisionalPlayer.release();
        } catch (e) {
          hilog.warn(0x0000, TAG, 'provisional player release failed: %{public}s', String(e));
        }
      }
      if (!fdTransferred && provisionalFd) {
        try {
          await sourceContext.resourceManager.closeRawFd(track.mediaFile);
        } catch (e) {
          hilog.warn(0x0000, TAG, 'provisional player fd close failed: %{public}s', String(e));
        }
      }
    }
  }

  private async releasePlayer(): Promise<void> {
    const releasing = this.player;
    this.player = null;
    this.playerCallbacks = null;
    this.sourceTrackId = '';
    if (releasing && releasing.state !== 'released') {
      try {
        await releasing.release();
      } catch (e) {
        hilog.error(0x0000, TAG, 'AVPLAYER release failed: %{public}s', String(e));
      }
    }
    await this.closePlayerFd();
  }

  private async closePlayerFd(): Promise<void> {
    if (!this.playerFd || !this.context || this.playerFdName.length === 0) {
      return;
    }
    const name = this.playerFdName;
    this.playerFd = null;
    this.playerFdName = '';
    try {
      await this.context.resourceManager.closeRawFd(name);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'player fd close failed: %{public}s', String(e));
    }
  }

  private isCurrentSource(player: media.AVPlayer, generation: number): boolean {
    return !this.isDestroying && this.player === player && generation === this.generation;
  }

  handlePlayerStateChange(player: media.AVPlayer, generation: number, state: media.AVPlayerState): void {
    hilog.info(0x0000, TAG, 'AVPLAYER state=%{public}s generation=%{public}d', state, generation);
    if (!this.isCurrentSource(player, generation)) {
      return;
    }
    if (state === 'initialized') {
      this.enqueueOperation(async (): Promise<void> => {
        if (this.isCurrentSource(player, generation) && player.state === 'initialized') {
          await player.prepare();
        }
      }, 'prepare');
      return;
    }
    if (state === 'prepared') {
      this.enqueueOperation(async (): Promise<void> => {
        if (!this.isCurrentSource(player, generation) || player.state !== 'prepared') {
          return;
        }
        const track = this.currentTrack();
        if (track && track.id === this.sourceTrackId) {
          // API 22 can over-report an MP3 raw-file duration from its VBR header.
          // The fixture duration is derived from the bundled frame stream and
          // keeps public seeks inside the exact descriptor's playable range.
          this.durationSec = track.durationSec;
        } else if (player.duration > 0) {
          this.durationSec = player.duration / 1000;
        }
        player.loop = this.repeatMode === 2;
        this.emit();
        if (this.autoPlayRequested) {
          this.autoPlayRequested = false;
          await player.play();
        }
      }, 'prepared transition');
      return;
    }
    if (state === 'playing') {
      this.isPlaying = true;
      this.isCompleted = false;
      this.completionHandled = false;
      this.emit();
      return;
    }
    if (state === 'paused') {
      this.isPlaying = false;
      this.emit();
      return;
    }
    if (state === 'completed') {
      this.handleNaturalCompletion();
      return;
    }
    if (state === 'stopped' || state === 'error') {
      this.isPlaying = false;
      this.emit();
    }
  }

  handleTimeUpdate(player: media.AVPlayer, generation: number, timeMs: number): void {
    if (!this.isCurrentSource(player, generation)) {
      return;
    }
    this.positionSec = Math.max(0, timeMs / 1000);
    this.emit();
  }

  handleDurationUpdate(player: media.AVPlayer, generation: number, durationMs: number): void {
    if (!this.isCurrentSource(player, generation)) {
      return;
    }
    const track = this.currentTrack();
    if (track && track.id === this.sourceTrackId) {
      this.durationSec = track.durationSec;
    } else {
      this.durationSec = Math.max(0, durationMs / 1000);
    }
    this.emit();
  }

  handleSeekDone(player: media.AVPlayer, generation: number, timeMs: number): void {
    if (!this.isCurrentSource(player, generation)) {
      return;
    }
    this.positionSec = Math.max(0, timeMs / 1000);
    this.isCompleted = false;
    this.emit();
  }

  handlePlayerError(player: media.AVPlayer, generation: number, error: Error): void {
    hilog.error(0x0000, TAG, 'AVPLAYER error: %{public}s', String(error));
    if (!this.isCurrentSource(player, generation)) {
      return;
    }
    this.isPlaying = false;
    this.emit();
  }

  play(): void {
    const track = this.currentTrack();
    if (!track || this.isDestroying) {
      return;
    }
    if (this.isCompleted) {
      this.replay();
      return;
    }
    const activePlayer = this.player;
    const requestGeneration = this.generation;
    if (!activePlayer) {
      this.requestSource(track, true);
      return;
    }
    const state = activePlayer.state;
    if (state === 'prepared' || state === 'paused' || state === 'completed') {
      this.enqueueOperation(async (): Promise<void> => {
        if (!this.isCurrentSource(activePlayer, requestGeneration)) {
          return;
        }
        const current = activePlayer.state;
        if (current === 'prepared' || current === 'paused') {
          await activePlayer.play();
        }
      }, 'play');
    } else if (state === 'idle' || state === 'stopped' || state === 'error') {
      this.positionSec = 0;
      this.isCompleted = false;
      this.requestSource(track, true);
    } else if (state === 'initialized') {
      this.autoPlayRequested = true;
    }
  }

  pause(): void {
    const activePlayer = this.player;
    const requestGeneration = this.generation;
    this.enqueueOperation(async (): Promise<void> => {
      if (activePlayer && this.isCurrentSource(activePlayer, requestGeneration) && activePlayer.state === 'playing') {
        await activePlayer.pause();
      }
    }, 'pause');
  }

  seek(positionSec: number): void {
    const activePlayer = this.player;
    const requestGeneration = this.generation;
    const upper = this.durationSec > 0 ? this.durationSec : positionSec;
    const bounded = Math.max(0, Math.min(positionSec, upper));
    this.enqueueOperation(async (): Promise<void> => {
      if (!activePlayer || !this.isCurrentSource(activePlayer, requestGeneration)) {
        return;
      }
      const state = activePlayer.state;
      if (state === 'prepared' || state === 'playing' || state === 'paused' || state === 'completed') {
        activePlayer.seek(Math.round(bounded * 1000), media.SeekMode.SEEK_PREV_SYNC);
      }
    }, 'seek');
  }

  replay(): void {
    const track = this.currentTrack();
    if (!track) {
      return;
    }
    this.positionSec = 0;
    this.isCompleted = false;
    this.completionHandled = false;
    const activePlayer = this.player;
    if (!activePlayer || activePlayer.state === 'idle' || activePlayer.state === 'stopped' ||
      activePlayer.state === 'error' || activePlayer.state === 'released' ||
      activePlayer.state === 'completed') {
      // Recreate a completed API 22 player instead of racing seekDone with
      // play; completed -> seek is asynchronous and cannot be awaited.
      this.requestSource(track, true);
      return;
    }
    this.seek(0);
    this.play();
  }

  previous(): void {
    if (this.queueTrackIds.length === 0) {
      return;
    }
    if (this.positionSec > 3) {
      if (this.isCompleted) {
        this.replay();
      } else {
        this.seek(0);
      }
      return;
    }
    if (this.queuePosition > 0) {
      this.selectQueuePosition(this.queuePosition - 1, true);
    } else if (this.repeatMode === 1) {
      this.selectQueuePosition(this.queueTrackIds.length - 1, true);
    } else if (this.isCompleted) {
      this.replay();
    } else {
      this.seek(0);
    }
  }

  next(): void {
    if (!this.canNext()) {
      return;
    }
    if (this.queuePosition < this.queueTrackIds.length - 1) {
      this.selectQueuePosition(this.queuePosition + 1, true);
    } else {
      this.selectQueuePosition(0, true);
    }
  }

  private handleNaturalCompletion(): void {
    if (this.completionHandled) {
      return;
    }
    this.completionHandled = true;
    this.isPlaying = false;
    if (this.repeatMode === 2) {
      this.replay();
      return;
    }
    if (this.queuePosition < this.queueTrackIds.length - 1) {
      this.selectQueuePosition(this.queuePosition + 1, true);
      return;
    }
    if (this.repeatMode === 1) {
      if (this.queueTrackIds.length === 1) {
        // API 22 cannot reliably replay one completed source through an
        // asynchronous seek. Recreate the sole source just like Replay and
        // repeat-one; multi-item wrap still selects the first queue item.
        this.replay();
      } else {
        this.selectQueuePosition(0, true);
      }
      return;
    }
    this.positionSec = this.durationSec;
    this.isCompleted = true;
    this.emit();
  }

  toggleShuffle(): void {
    const currentId = this.currentTrackId();
    if (this.isShuffled) {
      this.queueTrackIds = this.naturalTrackIds.slice();
      this.isShuffled = false;
    } else {
      const shuffled = this.queueTrackIds.slice();
      if (shuffled.length > 2) {
        const moved = shuffled.splice(1, 1)[0];
        shuffled.push(moved);
      } else {
        shuffled.reverse();
      }
      this.queueTrackIds = shuffled;
      this.isShuffled = true;
    }
    const currentPosition = this.queueTrackIds.indexOf(currentId);
    this.queuePosition = currentPosition >= 0 ? currentPosition : 0;
    this.emit();
  }

  setRepeatMode(mode: number): void {
    this.repeatMode = Math.max(0, Math.min(2, mode));
    const activePlayer = this.player;
    const requestGeneration = this.generation;
    this.enqueueOperation(async (): Promise<void> => {
      if (!activePlayer || !this.isCurrentSource(activePlayer, requestGeneration)) {
        return;
      }
      const state = activePlayer.state;
      if (state === 'prepared' || state === 'playing' || state === 'paused' || state === 'completed') {
        activePlayer.loop = this.repeatMode === 2;
      }
    }, 'natural completion mode');
    this.emit();
  }

  selectQueuePosition(position: number, autoPlay: boolean = true): void {
    if (position < 0 || position >= this.queueTrackIds.length) {
      return;
    }
    this.queuePosition = position;
    const track = this.currentTrack();
    if (!track) {
      return;
    }
    this.positionSec = 0;
    this.durationSec = track.durationSec;
    this.isPlaying = false;
    this.isCompleted = false;
    this.completionHandled = false;
    this.autoPlayRequested = autoPlay;
    this.emit();

    const activePlayer = this.player;
    if (this.sourceTrackId === track.id && activePlayer) {
      const state = activePlayer.state;
      if (state === 'prepared' || state === 'playing' || state === 'paused' || state === 'completed') {
        this.seek(0);
        if (autoPlay) {
          this.play();
        }
        return;
      }
    }
    this.requestSource(track, autoPlay);
  }

  reorderQueue(from: number, to: number): void {
    if (from < 0 || from >= this.queueTrackIds.length || to < 0 || to >= this.queueTrackIds.length) {
      return;
    }
    const currentId = this.currentTrackId();
    const queue = this.queueTrackIds.slice();
    const moved = queue.splice(from, 1)[0];
    queue.splice(to, 0, moved);
    this.queueTrackIds = queue;
    this.naturalTrackIds = queue.slice();
    this.isShuffled = false;
    const currentPosition = this.queueTrackIds.indexOf(currentId);
    this.queuePosition = currentPosition >= 0 ? currentPosition : 0;
    this.emit();
  }

  removeQueuePosition(position: number): void {
    if (position < 0 || position >= this.queueTrackIds.length || this.queueTrackIds.length === 1) {
      return;
    }
    const currentId = this.currentTrackId();
    const removedId = this.queueTrackIds[position];
    const remaining = this.queueTrackIds.slice();
    remaining.splice(position, 1);
    this.queueTrackIds = remaining;
    this.naturalTrackIds = this.naturalTrackIds.filter((id: string): boolean => id !== removedId);
    if (removedId === currentId) {
      const replacementPosition = Math.min(position, this.queueTrackIds.length - 1);
      this.selectQueuePosition(replacementPosition, true);
      return;
    }
    const currentPosition = this.queueTrackIds.indexOf(currentId);
    this.queuePosition = currentPosition >= 0 ? currentPosition : 0;
    this.emit();
  }

  toggleFavorite(): void {
    const requestedTrackId = this.currentTrackId();
    if (!this.context || requestedTrackId.length === 0 || this.isDestroying) {
      return;
    }
    this.enqueueOperation(async (): Promise<void> => {
      if (!this.context || this.isDestroying) {
        return;
      }
      let nextIds: string[];
      if (this.favoriteTrackIds.includes(requestedTrackId)) {
        nextIds = this.favoriteTrackIds.filter((id: string): boolean => id !== requestedTrackId);
      } else {
        nextIds = this.favoriteTrackIds.concat([requestedTrackId]);
      }
      const store = await preferences.getPreferences(this.context, { name: FAVORITE_STORE });
      await store.put(FAVORITE_KEY, nextIds.join('\n'));
      await store.flush();
      if (this.isDestroying) {
        return;
      }
      this.favoriteTrackIds = nextIds;
      this.emit();
    }, 'favorite persistence');
  }

  subscribe(listener: SessionListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
    listener(this.snapshot());
  }

  unsubscribe(listener: SessionListener): void {
    this.listeners = this.listeners.filter((item: SessionListener): boolean => item !== listener);
  }

  getSnapshot(): SessionSnapshot {
    return this.snapshot();
  }

  private currentTrackId(): string {
    if (this.queuePosition < 0 || this.queuePosition >= this.queueTrackIds.length) {
      return '';
    }
    return this.queueTrackIds[this.queuePosition];
  }

  private trackById(trackId: string): SessionTrack | null {
    return this.tracks.find((track: SessionTrack): boolean => track.id === trackId) || null;
  }

  private currentTrack(): SessionTrack | null {
    return this.trackById(this.currentTrackId());
  }

  private cloneTrack(track: SessionTrack): SessionTrack {
    const lyrics: SessionLyricLine[] = track.lyrics.map((line: SessionLyricLine): SessionLyricLine => {
      return new SessionLyricLine(line.timeSec, line.text);
    });
    return new SessionTrack(track.id, track.title, track.artist, track.durationSec, track.mediaFile, lyrics);
  }

  private canPrevious(): boolean {
    return this.queueTrackIds.length > 0;
  }

  private canNext(): boolean {
    return this.queueTrackIds.length > 0 &&
      (this.queuePosition < this.queueTrackIds.length - 1 || this.repeatMode === 1);
  }

  private snapshot(): SessionSnapshot {
    const snapshot = new SessionSnapshot();
    const current = this.currentTrack();
    snapshot.trackId = current ? current.id : '';
    snapshot.currentTrack = current ? this.cloneTrack(current) : null;
    snapshot.queueTracks = [];
    this.queueTrackIds.forEach((trackId: string): void => {
      const track = this.trackById(trackId);
      if (track) {
        snapshot.queueTracks.push(this.cloneTrack(track));
      }
    });
    snapshot.queuePosition = this.queuePosition;
    snapshot.positionSec = this.positionSec;
    snapshot.durationSec = this.durationSec;
    snapshot.isPlaying = this.isPlaying;
    snapshot.isCompleted = this.isCompleted;
    snapshot.isShuffled = this.isShuffled;
    snapshot.repeatMode = this.repeatMode;
    snapshot.isFavorite = snapshot.trackId.length > 0 && this.favoriteTrackIds.includes(snapshot.trackId);
    snapshot.canPrevious = this.canPrevious();
    snapshot.canNext = this.canNext();
    snapshot.artwork = this.artwork;
    return snapshot;
  }

  private emit(): void {
    const snapshot = this.snapshot();
    this.listeners.forEach((listener: SessionListener): void => listener(snapshot));
    if (!this.isDestroying) {
      this.schedulePublication(snapshot);
    }
  }

  private schedulePublication(snapshot: SessionSnapshot): void {
    this.publicationTask = this.publicationTask.then(async (): Promise<void> => {
      await this.publishSnapshot(snapshot);
    }).catch((e: Error): void => {
      hilog.error(0x0000, TAG, 'AVSESSION publication failed: %{public}s', String(e));
    });
  }

  private updateTransportAvailability(snapshot: SessionSnapshot): void {
    if (!this.session) {
      return;
    }
    try {
      if (snapshot.canPrevious && !this.previousCommandRegistered) {
        this.session.on('playPrevious', this.onSessionPrevious);
        this.previousCommandRegistered = true;
      } else if (!snapshot.canPrevious && this.previousCommandRegistered) {
        this.session.off('playPrevious', this.onSessionPrevious);
        this.previousCommandRegistered = false;
      }
      if (snapshot.canNext && !this.nextCommandRegistered) {
        this.session.on('playNext', this.onSessionNext);
        this.nextCommandRegistered = true;
      } else if (!snapshot.canNext && this.nextCommandRegistered) {
        this.session.off('playNext', this.onSessionNext);
        this.nextCommandRegistered = false;
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'AVSESSION transport availability failed: %{public}s', String(e));
    }
  }

  private loopMode(snapshot: SessionSnapshot): AVSessionManager.LoopMode {
    if (snapshot.repeatMode === 2) {
      return AVSessionManager.LoopMode.LOOP_MODE_SINGLE;
    }
    if (snapshot.repeatMode === 1) {
      return AVSessionManager.LoopMode.LOOP_MODE_LIST;
    }
    if (snapshot.isShuffled) {
      return AVSessionManager.LoopMode.LOOP_MODE_SHUFFLE;
    }
    return AVSessionManager.LoopMode.LOOP_MODE_SEQUENCE;
  }

  private async publishSnapshot(snapshot: SessionSnapshot): Promise<void> {
    const activeSession = this.session;
    if (this.isDestroying || !activeSession || !snapshot.currentTrack) {
      return;
    }
    this.updateTransportAvailability(snapshot);
    await this.publishSnapshotToSession(activeSession, snapshot);
  }

  private async publishSnapshotToSession(
    targetSession: AVSessionManager.AVSession,
    snapshot: SessionSnapshot
  ): Promise<void> {
    if (!snapshot.currentTrack) {
      return;
    }
    const items: AVSessionManager.AVQueueItem[] = [];
    snapshot.queueTracks.forEach((track: SessionTrack, index: number): void => {
      const description: AVSessionManager.AVMediaDescription = {
        assetId: track.id,
        title: track.title,
        artist: track.artist,
        mediaType: 'audio'
      };
      const item: AVSessionManager.AVQueueItem = { itemId: index, description: description };
      items.push(item);
    });
    await targetSession.setAVQueueTitle(AV_QUEUE_NAME);
    await targetSession.setAVQueueItems(items);
    const track = snapshot.currentTrack;
    const metadata: AVSessionManager.AVMetadata = {
      assetId: track.id,
      title: track.title,
      artist: track.artist,
      duration: snapshot.durationSec > 0 ? snapshot.durationSec * 1000 : track.durationSec * 1000,
      avQueueId: AV_QUEUE_ID,
      avQueueName: AV_QUEUE_NAME
    };
    if (snapshot.artwork) {
      metadata.mediaImage = snapshot.artwork;
      metadata.avQueueImage = snapshot.artwork;
    }
    await targetSession.setAVMetadata(metadata);
    let playbackState = AVSessionManager.PlaybackState.PLAYBACK_STATE_PAUSE;
    if (snapshot.isPlaying) {
      playbackState = AVSessionManager.PlaybackState.PLAYBACK_STATE_PLAY;
    } else if (snapshot.isCompleted) {
      playbackState = AVSessionManager.PlaybackState.PLAYBACK_STATE_COMPLETED;
    }
    const state: AVSessionManager.AVPlaybackState = {
      state: playbackState,
      position: { elapsedTime: snapshot.positionSec * 1000, updateTime: Date.now() },
      activeItemId: snapshot.queuePosition,
      duration: snapshot.durationSec * 1000,
      loopMode: this.loopMode(snapshot),
      isFavorite: snapshot.isFavorite
    };
    await targetSession.setAVPlaybackState(state);
  }

  async destroy(): Promise<void> {
    if (!this.initializationStarted) {
      return;
    }
    this.isDestroying = true;
    this.listeners = [];
    this.generation += 1;
    try {
      await this.initializationTask;
    } catch (e) {
      hilog.error(0x0000, TAG, 'initialization drain failed: %{public}s', String(e));
    }
    await this.operationTask;
    await this.publicationTask;
    await this.releasePlayer();
    const releasingSession = this.session;
    const releasePlay = this.playCommandRegistered;
    const releasePause = this.pauseCommandRegistered;
    const releaseNext = this.nextCommandRegistered;
    const releasePrevious = this.previousCommandRegistered;
    this.session = null;
    this.playCommandRegistered = false;
    this.pauseCommandRegistered = false;
    this.nextCommandRegistered = false;
    this.previousCommandRegistered = false;
    if (releasingSession) {
      if (releasePlay) {
        try {
          releasingSession.off('play', this.onSessionPlay);
        } catch (e) {
          hilog.warn(0x0000, TAG, 'AVSESSION play off failed: %{public}s', String(e));
        }
      }
      if (releasePause) {
        try {
          releasingSession.off('pause', this.onSessionPause);
        } catch (e) {
          hilog.warn(0x0000, TAG, 'AVSESSION pause off failed: %{public}s', String(e));
        }
      }
      if (releaseNext) {
        try {
          releasingSession.off('playNext', this.onSessionNext);
        } catch (e) {
          hilog.warn(0x0000, TAG, 'AVSESSION next off failed: %{public}s', String(e));
        }
      }
      if (releasePrevious) {
        try {
          releasingSession.off('playPrevious', this.onSessionPrevious);
        } catch (e) {
          hilog.warn(0x0000, TAG, 'AVSESSION previous off failed: %{public}s', String(e));
        }
      }
      try {
        await releasingSession.destroy();
      } catch (e) {
        hilog.error(0x0000, TAG, 'AVSESSION destroy failed: %{public}s', String(e));
      }
    }
    if (this.artwork) {
      try {
        await this.artwork.release();
      } catch (e) {
        hilog.warn(0x0000, TAG, 'track artwork release failed: %{public}s', String(e));
      }
      this.artwork = null;
    }
    this.context = null;
    this.initialized = false;
    this.initializationStarted = false;
    this.initializationTask = Promise.resolve();
  }
}

export const playerSession: PlayerSession = new PlayerSession();
