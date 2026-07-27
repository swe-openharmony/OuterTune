// Page: PlayerScreenPage — snapshot-driven full-screen player.

import { router } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import {
  playerSession,
  SessionLyricLine,
  SessionSnapshot,
  SessionTrack
} from '../common/PlayerSession';

@Entry
@Component
struct PlayerScreenPage {
  @State private currentTrack: SessionTrack | null = null;
  @State private queueTracks: SessionTrack[] = [];
  @State private queuePosition: number = 0;
  @State private progressSec: number = 0;
  @State private durationSec: number = 1;
  @State private isPlaying: boolean = false;
  @State private isCompleted: boolean = false;
  @State private isFavorite: boolean = false;
  @State private isShuffled: boolean = false;
  @State private repeatMode: number = 0;
  @State private canPrevious: boolean = false;
  @State private canNext: boolean = false;
  @State private artwork: image.PixelMap | null = null;
  @State private lyricsOpen: boolean = false;
  @State private queueOpen: boolean = false;
  private dragFrom: number = -1;

  private readonly sessionListener = (snapshot: SessionSnapshot): void => {
    this.applySnapshot(snapshot);
  };

  aboutToAppear(): void {
    playerSession.subscribe(this.sessionListener);
  }

  aboutToDisappear(): void {
    // Collapse only detaches this view. EntryAbility retains AVPlayer/AVSession.
    playerSession.unsubscribe(this.sessionListener);
  }

  private applySnapshot(snapshot: SessionSnapshot): void {
    this.currentTrack = snapshot.currentTrack;
    this.queueTracks = snapshot.queueTracks;
    this.queuePosition = snapshot.queuePosition;
    this.progressSec = snapshot.positionSec;
    this.durationSec = snapshot.durationSec > 0 ? snapshot.durationSec : 1;
    this.isPlaying = snapshot.isPlaying;
    this.isCompleted = snapshot.isCompleted;
    this.isFavorite = snapshot.isFavorite;
    this.isShuffled = snapshot.isShuffled;
    this.repeatMode = snapshot.repeatMode;
    this.canPrevious = snapshot.canPrevious;
    this.canNext = snapshot.canNext;
    this.artwork = snapshot.artwork;
  }

  private title(): string {
    return this.currentTrack ? this.currentTrack.title : '(loading...)';
  }

  private artist(): string {
    return this.currentTrack ? this.currentTrack.artist : '';
  }

  private lyrics(): SessionLyricLine[] {
    return this.currentTrack ? this.currentTrack.lyrics : [];
  }

  private formatTime(sec: number): string {
    const minute = Math.floor(sec / 60);
    const second = Math.floor(sec % 60);
    return `${minute}:${second < 10 ? '0' : ''}${second}`;
  }

  private isActiveLyric(index: number): boolean {
    const lines = this.lyrics();
    return this.progressSec >= lines[index].timeSec &&
      (index === lines.length - 1 || this.progressSec < lines[index + 1].timeSec);
  }

  private onPlayPause(): void {
    if (this.isCompleted) {
      playerSession.replay();
    } else if (this.isPlaying) {
      playerSession.pause();
    } else {
      playerSession.play();
    }
  }

  private playFromQueue(position: number): void {
    playerSession.selectQueuePosition(position, true);
    this.queueOpen = false;
  }

  private removeFromQueue(position: number): void {
    playerSession.removeQueuePosition(position);
  }

  @Builder
  private TopBar() {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        Text('⌄').fontSize(22).fontColor('#1F1F1F');
      }.width(40).height(40).backgroundColor(Color.Transparent).accessibilityDescription('Collapse player')
        .onClick(() => router.back());
      Blank().layoutWeight(1);
    }.width('100%').height(56).padding({ left: 8, right: 8 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  private CoverOrLyrics() {
    if (this.lyricsOpen) {
      Column() {
        if (this.lyrics().length === 0) {
          Text('歌词未找到').fontSize(16).fontColor('#888888');
        } else {
          ForEach(this.lyrics(), (line: SessionLyricLine, index: number) => {
            Text(line.text).fontSize(16).fontColor(this.isActiveLyric(index) ? '#1976D2' : '#888888')
              .fontWeight(this.isActiveLyric(index) ? FontWeight.Bold : FontWeight.Regular).margin({ top: 8 })
              .accessibilityDescription(this.isActiveLyric(index) ? `${line.text}, current lyric` : `${line.text}, lyric`)
              .onClick(() => playerSession.seek(line.timeSec));
          }, (line: SessionLyricLine) => `${line.timeSec}_${line.text}`);
        }
      }.width(280).height(280).borderRadius(16).backgroundColor('#F4F4F4')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).margin({ top: 16 });
    } else {
      Image(this.artwork).width(280).height(280).objectFit(ImageFit.Cover)
        .borderRadius(16).clip(true).margin({ top: 16 }).accessibilityDescription('Track artwork');
    }
  }

  @Builder
  private ControlRow() {
    Row() {
      Text('\u{1F500}').fontSize(20).fontColor(this.isShuffled ? '#1976D2' : '#666666').padding(10)
        .accessibilityDescription(this.isShuffled ? 'Shuffle on' : 'Shuffle off')
        .onClick(() => playerSession.toggleShuffle());
      Text('⏮').fontSize(28).fontColor(this.canPrevious ? '#1F1F1F' : '#BDBDBD').padding(10)
        .accessibilityDescription(this.canPrevious ? 'Previous available' : 'Previous unavailable')
        .enabled(this.canPrevious).onClick(() => playerSession.previous());
      Column() {
        Text(this.isCompleted ? '↺' : (this.isPlaying ? '⏸' : '▶'))
          .fontSize(36).fontColor('#FFFFFF').fontWeight(FontWeight.Bold);
      }.width(72).height(72).borderRadius(36).backgroundColor('#1976D2')
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).margin({ left: 16, right: 16 })
        .accessibilityDescription(this.isCompleted ? 'Replay' : (this.isPlaying ? 'Pause' : 'Play'))
        .onClick(() => this.onPlayPause());
      Text('⏭').fontSize(28).fontColor(this.canNext ? '#1F1F1F' : '#BDBDBD').padding(10)
        .accessibilityDescription(this.canNext ? 'Next available' : 'Next unavailable')
        .enabled(this.canNext).onClick(() => playerSession.next());
      Text('\u{1F501}').fontSize(20).fontColor(this.repeatMode === 0 ? '#666666' : '#1976D2').padding(10)
        .accessibilityDescription(this.repeatMode === 0 ? 'Repeat off' : (this.repeatMode === 1 ? 'Repeat all' : 'Repeat one'))
        .onClick(() => playerSession.setRepeatMode((this.repeatMode + 1) % 3));
    }.width('100%').margin({ top: 24 }).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center);
  }

  @Builder
  private QueueSheet() {
    Column() {
      Row() {
        Text('Queue').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1F1F1F').layoutWeight(1).padding(16);
        Text('⌄').fontSize(22).fontColor('#1F1F1F').padding(16)
          .accessibilityDescription('Close queue').onClick(() => { this.queueOpen = false; });
      }.width('100%');
      List() {
        ForEach(this.queueTracks, (track: SessionTrack, position: number) => {
          ListItem() {
            Row() {
              Text('≡').fontSize(20).fontColor('#888888').width(40).textAlign(TextAlign.Center)
                .accessibilityDescription(`Reorder ${track.title}`);
              Text(track.title).fontSize(15)
                .fontColor(position === this.queuePosition ? '#1976D2' : '#1F1F1F')
                .fontWeight(position === this.queuePosition ? FontWeight.Bold : FontWeight.Regular)
                .layoutWeight(1)
                .accessibilityDescription(position === this.queuePosition ? `${track.title}, current media` : track.title);
            }.width('100%').height(56).alignItems(VerticalAlign.Center)
              .onClick(() => this.playFromQueue(position))
              .gesture(PanGesture({ direction: PanDirection.Horizontal })
                .onActionEnd((event: GestureEvent) => {
                  if (event.offsetX < -80 || event.offsetX > 80) {
                    this.removeFromQueue(position);
                  }
                }));
          }
        }, (track: SessionTrack, position: number) =>
          `${track.id}_${position}`);
      }.layoutWeight(1).width('100%')
        .editMode(true)
        .onItemDragStart((event: ItemDragInfo, itemIndex: number) => {
          this.dragFrom = itemIndex;
          return this.DragPreview(this.queueTracks[itemIndex].title);
        })
        .onItemDrop((event: ItemDragInfo, itemIndex: number, insertIndex: number, isSuccess: boolean) => {
          if (isSuccess && this.dragFrom >= 0) {
            const finalIndex = insertIndex < this.queueTracks.length ? insertIndex : this.queueTracks.length - 1;
            playerSession.reorderQueue(this.dragFrom, finalIndex);
            this.dragFrom = -1;
          }
        });
    }.width('100%').height('70%').backgroundColor('#FFFFFF')
      .borderRadius({ topLeft: 16, topRight: 16 }).shadow({ radius: 16, color: '#40000000' });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.TopBar();
        Column() {
          this.CoverOrLyrics();
          Text(this.title()).fontSize(22).fontWeight(FontWeight.Bold).fontColor('#1F1F1F').margin({ top: 20 });
          Text(this.artist()).fontSize(15).fontColor('#666666').margin({ top: 6 });

          Column() {
            Slider({ value: this.progressSec, min: 0, max: this.durationSec, step: 1, style: SliderStyle.OutSet })
              .width('100%').blockColor('#1976D2').selectedColor('#1976D2').trackColor('#E0E0E0')
              .accessibilityDescription('Playback position')
              .onChange((value: number, mode: SliderChangeMode) => {
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  playerSession.seek(value);
                }
              });
            Row() {
              Text(this.formatTime(this.progressSec)).fontSize(12).fontColor('#666666').layoutWeight(1);
              Text(this.formatTime(this.durationSec)).fontSize(12).fontColor('#666666');
            }.width('100%').margin({ top: 4 });
          }.width('100%').padding({ left: 24, right: 24 }).margin({ top: 24 });

          this.ControlRow();

          Text(`Shuffle: ${this.isShuffled ? 'on' : 'off'} · Repeat: ${this.repeatMode === 0 ? 'off' :
            (this.repeatMode === 1 ? 'all' : 'one')}`)
            .fontSize(11).fontColor('#888888').margin({ top: 6 });

          Row() {
            Column() {
              Text('☰').fontSize(20).fontColor('#1F1F1F');
              Text('Queue').fontSize(11).fontColor('#666666').margin({ top: 4 });
            }.layoutWeight(1).accessibilityDescription('Queue').onClick(() => { this.queueOpen = true; });
            Column() {
              Text('♫').fontSize(20).fontColor(this.lyricsOpen ? '#1976D2' : '#1F1F1F');
              Text('Lyrics').fontSize(11).fontColor('#666666').margin({ top: 4 });
            }.layoutWeight(1).accessibilityDescription(this.lyricsOpen ? 'Hide lyrics' : 'Show lyrics')
              .onClick(() => { this.lyricsOpen = !this.lyricsOpen; });
            Column() {
              Text(this.isFavorite ? '♥' : '♡').fontSize(20).fontColor(this.isFavorite ? '#E53935' : '#1F1F1F');
              Text('Favorite').fontSize(11).fontColor('#666666').margin({ top: 4 });
            }.layoutWeight(1).accessibilityDescription(this.isFavorite ? 'Favorite selected' : 'Favorite unselected')
              .onClick(() => playerSession.toggleFavorite());
          }.width('100%').padding({ top: 16, bottom: 24 }).alignItems(VerticalAlign.Center);
        }.layoutWeight(1).width('100%').alignItems(HorizontalAlign.Center).padding({ left: 16, right: 16 });
      }.width('100%').height('100%').backgroundColor('#FFFFFF');

      if (this.queueOpen) {
        this.QueueSheet();
      }
    }.width('100%').height('100%');
  }

  @Builder
  private DragPreview(title: string) {
    Text(title).fontSize(15).fontColor('#1F1F1F').padding(12).backgroundColor('#F0F0F0');
  }
}
