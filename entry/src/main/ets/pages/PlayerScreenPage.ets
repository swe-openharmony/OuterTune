// Page: PlayerScreenPage — full-screen player (5 scenarios)

import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { MockDataSource } from '../common/MockDataSource';
import { playerSession, SessionSnapshot, SessionTrack } from '../common/PlayerSession';

const TAG = 'PlayerScreenPage';
const STORE = 'outune_player';

interface LyricLine {
  timeSec: number;
  text: string;
}

interface Track {
  id: string;
  title: string;
  artist: string;
  durationSec: number;
  lyrics: LyricLine[];
}

interface PlayerFile {
  tracks: Track[];
}

@Entry
@Component
struct PlayerScreenPage {
  @State private tracks: Track[] = [];
  @State private queue: number[] = [];        // track indices in play order
  @State private trackIndex: number = 0;
  @State private trackTitle: string = '(loading...)';
  @State private artistName: string = '';
  @State private durationSec: number = 1;
  @State private progressSec: number = 0;
  @State private isPlaying: boolean = true;
  @State private isFavorited: boolean = false;
  @State private isShuffled: boolean = false;
  @State private repeatMode: number = 0;      // 0 off, 1 all, 2 one
  @State private lyricsOpen: boolean = false;
  @State private queueOpen: boolean = false;
  @State private favTitles: string[] = [];
  private favoritesLoaded: boolean = false;
  private dragFrom: number = -1;
  private naturalOrder: number[] = [];
  private readonly sessionListener = (snapshot: SessionSnapshot): void => {
    this.applySnapshot(snapshot);
  };

  aboutToAppear(): void {
    playerSession.subscribe(this.sessionListener);
    this.load();
  }

  aboutToDisappear(): void {
    // Collapse only detaches this view. EntryAbility retains AVPlayer/AVSession.
    playerSession.unsubscribe(this.sessionListener);
  }

  private applySnapshot(snapshot: SessionSnapshot): void {
    this.progressSec = snapshot.positionSec;
    if (snapshot.durationSec > 0) {
      this.durationSec = snapshot.durationSec;
    }
    this.isPlaying = snapshot.isPlaying;
    const trackPosition = this.tracks.findIndex((track: Track) => track.id === snapshot.trackId);
    if (trackPosition >= 0) {
      const queuePosition = this.queue.indexOf(trackPosition);
      if (queuePosition >= 0) {
        this.trackIndex = queuePosition;
      }
      const track = this.tracks[trackPosition];
      this.trackTitle = track.title;
      this.artistName = track.artist;
      if (this.favoritesLoaded) {
        this.isFavorited = this.favTitles.includes(track.title) || playerSession.isFavorite(track.id);
      }
    }
  }

  private async store(): Promise<preferences.Preferences> {
    return await preferences.getPreferences(getContext(this) as common.UIAbilityContext, { name: STORE });
  }

  private async load(): Promise<void> {
    try {
      this.tracks = (await MockDataSource.loadJson<PlayerFile>(this, 'mock_player.json')).tracks;
      this.queue = this.tracks.map((_t: Track, i: number) => i);
      this.naturalOrder = this.queue.slice();
      const s = await this.store();
      const fav = await s.get('fav_titles', '') as string;
      this.favTitles = fav.length > 0 ? fav.split('\n') : [];
      this.tracks.forEach((track: Track) => {
        if (this.favTitles.includes(track.title)) {
          playerSession.setFavorite(track.id, true);
        }
      });
      this.favoritesLoaded = true;
      hilog.info(0x0000, TAG, 'FAVORITE store=outune_player key=fav_titles read=%{public}s',
        String(this.favTitles.length > 0));
      const sessionTracks: SessionTrack[] = this.tracks.map((track: Track): SessionTrack => {
        const sessionTrack: SessionTrack = {
          id: track.id,
          title: track.title,
          artist: track.artist,
          durationSec: track.durationSec
        };
        return sessionTrack;
      });
      playerSession.configureTracks(sessionTracks, this.queue);
      const snapshot = playerSession.getSnapshot();
      if (snapshot.trackId.length === 0) {
        playerSession.selectQueuePosition(0, true);
      } else {
        this.applySnapshot(snapshot);
      }
      const loadedTrack = this.curTrack();
      this.isFavorited = this.favTitles.includes(this.trackTitle) || playerSession.isFavorite(loadedTrack.id);
    } catch (e) {
      hilog.error(0x0000, TAG, 'load failed: %{public}s', String(e));
    }
  }

  private applyTrack(qpos: number): void {
    if (qpos < 0 || qpos >= this.queue.length) { return; }
    playerSession.selectQueuePosition(qpos, true);
  }

  private curTrack(): Track {
    return this.tracks[this.queue[this.trackIndex]];
  }

  private formatTime(sec: number): string {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  }

  private atEnd(): boolean {
    return this.durationSec > 1 && this.progressSec >= this.durationSec;
  }

  private isActiveLyric(index: number): boolean {
    const lyrics = this.curTrack().lyrics;
    return this.progressSec >= lyrics[index].timeSec &&
      (index === lyrics.length - 1 || this.progressSec < lyrics[index + 1].timeSec);
  }

  private onPlayPause(): void {
    if (this.atEnd()) {
      playerSession.seek(0);
      playerSession.play();
      return;
    }
    if (this.isPlaying) {
      playerSession.pause();
    } else {
      playerSession.play();
    }
  }

  private onPrev(): void {
    playerSession.previous();
  }

  private onNext(): void {
    playerSession.next();
  }

  private toggleShuffle(): void {
    const currentTrack = this.queue[this.trackIndex];
    if (this.isShuffled) {
      this.queue = this.naturalOrder.slice();
      this.isShuffled = false;
    } else {
      const shuffled = this.queue.slice();
      if (shuffled.length > 2) {
        const moved = shuffled.splice(1, 1)[0];
        shuffled.push(moved);
      } else {
        shuffled.reverse();
      }
      this.queue = shuffled;
      this.isShuffled = true;
    }
    this.trackIndex = this.queue.indexOf(currentTrack);
    playerSession.updateQueue(this.queue, this.curTrack().id);
  }

  private async onFavorite(): Promise<void> {
    const title = this.trackTitle;
    hilog.info(0x0000, TAG, 'FAVORITE callback invoked');
    if (this.favTitles.includes(title)) {
      this.favTitles = this.favTitles.filter((x: string) => x !== title);
    } else {
      this.favTitles = this.favTitles.concat([title]);
    }
    this.isFavorited = this.favTitles.includes(title);
    const current = this.curTrack();
    playerSession.setFavorite(current.id, this.isFavorited);
    const s = await this.store();
    await s.put('fav_titles', this.favTitles.join('\n'));
    await s.flush();
    hilog.info(0x0000, TAG, 'FAVORITE store=outune_player key=fav_titles write=true active=%{public}s',
      String(this.isFavorited));
  }

  private playFromQueue(qpos: number): void {
    this.applyTrack(qpos);
    this.queueOpen = false;
  }

  private removeFromQueue(qpos: number): void {
    if (qpos < 0 || qpos >= this.queue.length || this.queue.length === 1) { return; }
    const currentTrack = this.queue[this.trackIndex];
    const removedTrack = this.queue[qpos];
    const arr = this.queue.slice();
    arr.splice(qpos, 1);
    this.queue = arr;
    if (removedTrack === currentTrack) {
      const nextPosition = qpos < this.queue.length ? qpos : this.queue.length - 1;
      this.applyTrack(nextPosition);
    } else {
      this.trackIndex = this.queue.indexOf(currentTrack);
      playerSession.updateQueue(this.queue, this.curTrack().id);
    }
  }

  private reorderQueue(from: number, to: number): void {
    if (from < 0 || from >= this.queue.length) { return; }
    const currentTrack = this.queue[this.trackIndex];
    const arr = this.queue.slice();
    const moved = arr.splice(from, 1)[0];
    let dest = to;
    if (dest < 0) { dest = 0; }
    if (dest > arr.length) { dest = arr.length; }
    arr.splice(dest, 0, moved);
    this.queue = arr;
    this.trackIndex = this.queue.indexOf(currentTrack);
    playerSession.updateQueue(this.queue, this.curTrack().id);
  }

  @Builder
  private TopBar() {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        Text('⌄').fontSize(22).fontColor('#1F1F1F');
      }.width(40).height(40).backgroundColor(Color.Transparent).accessibilityText('Collapse player')
        .onClick(() => router.back());
      Blank().layoutWeight(1);
    }.width('100%').height(56).padding({ left: 8, right: 8 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  private CoverOrLyrics() {
    if (this.lyricsOpen) {
      Column() {
        if (this.curTrack().lyrics.length === 0) {
          Text('歌词未找到').fontSize(16).fontColor('#888888');
        } else {
          ForEach(this.curTrack().lyrics, (line: LyricLine, i: number) => {
            Text(line.text).fontSize(16).fontColor(this.isActiveLyric(i) ? '#1976D2' : '#888888')
              .fontWeight(this.isActiveLyric(i) ? FontWeight.Bold : FontWeight.Regular).margin({ top: 8 })
              .accessibilityText(`${line.text} · ${this.formatTime(line.timeSec)}`)
              .onClick(() => { playerSession.seek(line.timeSec); });
          }, (line: LyricLine) => `${line.timeSec}_${line.text}`);
        }
      }.width(280).height(280).borderRadius(16).backgroundColor('#F4F4F4')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).margin({ top: 16 });
    } else {
      Column().width(280).height(280).borderRadius(16).backgroundColor('#1976D2').margin({ top: 16 });
    }
  }

  @Builder
  private ControlRow() {
    Row() {
      Text('\u{1F500}').fontSize(20).fontColor(this.isShuffled ? '#1976D2' : '#666666').padding(10)
        .onClick(() => this.toggleShuffle());
      Text('⏮').fontSize(28).fontColor('#1F1F1F').padding(10).onClick(() => this.onPrev());
      Column() {
        Text(this.atEnd() ? '↺' : (this.isPlaying ? '⏸' : '▶')).fontSize(36).fontColor('#FFFFFF').fontWeight(FontWeight.Bold);
      }.width(72).height(72).borderRadius(36).backgroundColor('#1976D2')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).margin({ left: 16, right: 16 })
        .onClick(() => this.onPlayPause());
      Text('⏭').fontSize(28).fontColor('#1F1F1F').padding(10).onClick(() => this.onNext());
      Text(this.repeatMode === 2 ? '\u{1F501}' : '\u{1F501}').fontSize(20)
        .fontColor(this.repeatMode === 0 ? '#666666' : '#1976D2').padding(10)
        .onClick(() => {
          this.repeatMode = (this.repeatMode + 1) % 3;
          playerSession.setRepeatMode(this.repeatMode);
        });
    }.width('100%').margin({ top: 24 }).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.TopBar();
        Column() {
          this.CoverOrLyrics();
          Text(this.trackTitle).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#1F1F1F').margin({ top: 20 });
          Text(this.artistName).fontSize(15).fontColor('#666666').margin({ top: 6 });

          Column() {
            Slider({ value: this.progressSec, min: 0, max: this.durationSec, step: 1, style: SliderStyle.OutSet })
              .width('100%').blockColor('#1976D2').selectedColor('#1976D2').trackColor('#E0E0E0')
              .onChange((value: number) => { playerSession.seek(value); });
            Row() {
              Text(this.formatTime(this.progressSec)).fontSize(12).fontColor('#666666').layoutWeight(1);
              Text(this.formatTime(this.durationSec)).fontSize(12).fontColor('#666666');
            }.width('100%').margin({ top: 4 });
          }.width('100%').padding({ left: 24, right: 24 }).margin({ top: 24 });

          this.ControlRow();

          // Mode status line — text mirror of the shuffle/repeat highlight (testable).
          Text(`Shuffle: ${this.isShuffled ? 'on' : 'off'} · Repeat: ${this.repeatMode === 0 ? 'off' : (this.repeatMode === 1 ? 'all' : 'one')}`)
            .fontSize(11).fontColor('#888888').margin({ top: 6 });

          Row() {
            Column() {
              Text('☰').fontSize(20).fontColor('#1F1F1F'); Text('Queue').fontSize(11).fontColor('#666666').margin({ top: 4 });
            }.layoutWeight(1).onClick(() => { this.queueOpen = true; });
            Column() {
              Text('♫').fontSize(20).fontColor(this.lyricsOpen ? '#1976D2' : '#1F1F1F');
              Text('Lyrics').fontSize(11).fontColor('#666666').margin({ top: 4 });
            }.layoutWeight(1).onClick(() => { this.lyricsOpen = !this.lyricsOpen; });
            Column() {
              Text(this.isFavorited ? '♥' : '♡').fontSize(20).fontColor(this.isFavorited ? '#E53935' : '#1F1F1F');
              Text('Favorite').fontSize(11).fontColor('#666666').margin({ top: 4 });
            }.layoutWeight(1).id('favorite_control').accessibilityText(this.isFavorited ? 'Favorite selected' : 'Favorite unselected')
              .onClick(() => this.onFavorite());
          }.width('100%').padding({ top: 16, bottom: 24 }).alignItems(VerticalAlign.Center);
        }.layoutWeight(1).width('100%').alignItems(HorizontalAlign.Center).padding({ left: 16, right: 16 });
      }.width('100%').height('100%').backgroundColor('#FFFFFF');

      // Queue panel (场景四)
      if (this.queueOpen) {
        Column() {
          Row() {
            Text('Queue').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1F1F1F').layoutWeight(1).padding(16);
            Text('⌄').fontSize(22).fontColor('#1F1F1F').padding(16).onClick(() => { this.queueOpen = false; });
          }.width('100%');
          List() {
            ForEach(this.queue, (ti: number, qpos: number) => {
              ListItem() {
                Row() {
                  Text('≡').fontSize(20).fontColor('#888888').width(40).textAlign(TextAlign.Center);
                  Text(this.tracks[ti].title).fontSize(15)
                    .fontColor(qpos === this.trackIndex ? '#1976D2' : '#1F1F1F')
                    .fontWeight(qpos === this.trackIndex ? FontWeight.Bold : FontWeight.Regular).layoutWeight(1);
                }.width('100%').height(56).alignItems(VerticalAlign.Center)
                  .onClick(() => this.playFromQueue(qpos))
                  .gesture(PanGesture({ direction: PanDirection.Horizontal })
                    .onActionEnd((e: GestureEvent) => { if (e.offsetX < -80 || e.offsetX > 80) { this.removeFromQueue(qpos); } }));
              }
            }, (ti: number, qpos: number) => `q_${ti}_${qpos}`);
          }.layoutWeight(1).width('100%')
            .editMode(true)
            .onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
              this.dragFrom = itemIndex;
              return this.DragPreview(this.tracks[this.queue[itemIndex]].title);
            })
            .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
              if (isSuccess && this.dragFrom >= 0) {
                this.reorderQueue(this.dragFrom, insertIndex < this.queue.length ? insertIndex : this.queue.length - 1);
              }
            });
        }.width('100%').height('70%').backgroundColor('#FFFFFF')
          .borderRadius({ topLeft: 16, topRight: 16 }).shadow({ radius: 16, color: '#40000000' });
      }
    }.width('100%').height('100%');
  }

  @Builder
  private DragPreview(title: string) {
    Text(title).fontSize(15).fontColor('#1F1F1F').padding(12).backgroundColor('#F0F0F0');
  }
}
