// Page: PlayerScreenPage — full-screen player (5 scenarios)

import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { MockDataSource } from '../common/MockDataSource';
import { PlayerSession, SessionCallbacks } from '../common/PlayerSession';

const TAG = 'PlayerScreenPage';
const STORE = 'outune_player';

interface Track {
  title: string;
  artist: string;
  durationSec: number;
  lyrics: string[];
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
  private dragFrom: number = -1;
  private session: PlayerSession = new PlayerSession();

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.session.destroy();
  }

  // 场景五: register the system media session, then publish now-playing state.
  private async initSession(): Promise<void> {
    const cb: SessionCallbacks = {
      onPlay: () => { this.isPlaying = true; this.pushState(); },
      onPause: () => { this.isPlaying = false; this.pushState(); },
      onNext: () => { this.onNext(); },
      onPrev: () => { this.onPrev(); }
    };
    await this.session.init(getContext(this) as common.UIAbilityContext, cb);
  }

  // Publish current track metadata + playback state to the media session.
  private pushSession(): void {
    this.session.setMetadata(this.trackTitle, this.artistName, this.durationSec);
    this.session.setState(this.isPlaying, this.progressSec);
  }

  private pushState(): void {
    this.session.setState(this.isPlaying, this.progressSec);
  }

  private async store(): Promise<preferences.Preferences> {
    return await preferences.getPreferences(getContext(this) as common.UIAbilityContext, { name: STORE });
  }

  private async load(): Promise<void> {
    try {
      this.tracks = (await MockDataSource.loadJson<PlayerFile>(this, 'mock_player.json')).tracks;
      this.queue = this.tracks.map((_t: Track, i: number) => i);
      const s = await this.store();
      const fav = await s.get('fav_titles', '') as string;
      this.favTitles = fav.length > 0 ? fav.split('\n') : [];
      await this.initSession();
      this.applyTrack(0);
    } catch (e) {
      hilog.error(0x0000, TAG, 'load failed: %{public}s', String(e));
    }
  }

  private applyTrack(qpos: number): void {
    if (qpos < 0 || qpos >= this.queue.length) { return; }
    this.trackIndex = qpos;
    const t = this.tracks[this.queue[qpos]];
    this.trackTitle = t.title;
    this.artistName = t.artist;
    this.durationSec = t.durationSec;
    this.progressSec = 0;
    this.isPlaying = true;
    this.isFavorited = this.favTitles.includes(t.title);
    this.pushSession();   // 场景五 step 3: in-app track switch syncs the media card
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

  private onPlayPause(): void {
    if (this.atEnd()) {
      this.progressSec = 0;     // replay (场景一 step 5)
      this.isPlaying = true;
      this.pushState();
      return;
    }
    this.isPlaying = !this.isPlaying;
    this.pushState();
  }

  private onPrev(): void {
    if (this.progressSec > 3) {
      this.progressSec = 0;     // restart current (场景二 step 2)
      this.pushState();
    } else {
      this.applyTrack(this.trackIndex > 0 ? this.trackIndex - 1 : this.queue.length - 1);
    }
  }

  private onNext(): void {
    this.applyTrack(this.trackIndex < this.queue.length - 1 ? this.trackIndex + 1 : 0);
  }

  private async onFavorite(): Promise<void> {
    const title = this.trackTitle;
    if (this.favTitles.includes(title)) {
      this.favTitles = this.favTitles.filter((x: string) => x !== title);
    } else {
      this.favTitles = this.favTitles.concat([title]);
    }
    this.isFavorited = this.favTitles.includes(title);
    const s = await this.store();
    await s.put('fav_titles', this.favTitles.join('\n'));
    await s.flush();
  }

  private playFromQueue(qpos: number): void {
    this.applyTrack(qpos);
    this.queueOpen = false;
  }

  private removeFromQueue(qpos: number): void {
    const arr = this.queue.slice();
    arr.splice(qpos, 1);
    this.queue = arr;
    if (this.trackIndex >= this.queue.length) { this.trackIndex = this.queue.length - 1; }
  }

  private reorderQueue(from: number, to: number): void {
    if (from < 0 || from >= this.queue.length) { return; }
    const arr = this.queue.slice();
    const moved = arr.splice(from, 1)[0];
    let dest = to;
    if (dest < 0) { dest = 0; }
    if (dest > arr.length) { dest = arr.length; }
    arr.splice(dest, 0, moved);
    this.queue = arr;
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
          ForEach(this.curTrack().lyrics, (line: string, i: number) => {
            Text(line).fontSize(16).fontColor(i === 0 ? '#1976D2' : '#888888')
              .fontWeight(i === 0 ? FontWeight.Bold : FontWeight.Regular).margin({ top: 8 })
              .onClick(() => { this.progressSec = 0; });
          }, (line: string, i: number) => `ly_${i}`);
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
        .onClick(() => { this.isShuffled = !this.isShuffled; });
      Text('⏮').fontSize(28).fontColor('#1F1F1F').padding(10).onClick(() => this.onPrev());
      Column() {
        Text(this.atEnd() ? '↺' : (this.isPlaying ? '⏸' : '▶')).fontSize(36).fontColor('#FFFFFF').fontWeight(FontWeight.Bold);
      }.width(72).height(72).borderRadius(36).backgroundColor('#1976D2')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).margin({ left: 16, right: 16 })
        .onClick(() => this.onPlayPause());
      Text('⏭').fontSize(28).fontColor('#1F1F1F').padding(10).onClick(() => this.onNext());
      Text(this.repeatMode === 2 ? '\u{1F501}' : '\u{1F501}').fontSize(20)
        .fontColor(this.repeatMode === 0 ? '#666666' : '#1976D2').padding(10)
        .onClick(() => { this.repeatMode = (this.repeatMode + 1) % 3; });
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
              .onChange((value: number) => { this.progressSec = value; });
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
            }.layoutWeight(1).onClick(() => this.onFavorite());
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
