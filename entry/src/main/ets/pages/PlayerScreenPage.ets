// Page: PlayerScreenPage

import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';

const TAG = 'PlayerScreenPage';

@Entry
@Component
struct PlayerScreenPage {
  // Real values populated from rawfile/ at aboutToAppear — NOT hardcoded.
  @State private trackTitle: string = '(loading...)';
  @State private artistName: string = '';
  @State private isPlaying: boolean = true;
  @State private isFavorited: boolean = false;
  @State private isShuffled: boolean = false;
  @State private repeatMode: number = 0; // 0 off, 1 all, 2 one
  @State private progressSec: number = 25;
  @State private durationSec: number = 1;
  @State private trackList: string[] = [];

  // Deterministic colored stripe palette for the album-art placeholder.
  private artPalette: string[] = [
    '#1976D2', '#1E88E5', '#039BE5', '#00ACC1', '#00897B',
    '#43A047', '#7CB342', '#C0CA33', '#FDD835', '#FFB300',
    '#FB8C00', '#F4511E', '#E53935', '#D81B60', '#8E24AA',
    '#5E35B1', '#3949AB'
  ];

  aboutToAppear(): void {
    hilog.info(0x0000, TAG, 'PlayerScreenPage mounted');
    this.loadFromRawfile();
  }

  aboutToDisappear(): void {
    // TODO Phase D: this.avPlayer?.release();
  }

  /**
   * Discovers .mp3 / .m4a / .flac files shipped in entry/src/main/resources/rawfile/
   * via resourceManager.getRawFileList(''), then loads the first track's metadata
   * (title, artist, duration) using AVMetadataExtractor. Falls back to filename if
   * tag-based metadata is absent. No hardcoded track values.
   */
  private async loadFromRawfile(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const rm = ctx.resourceManager;
      const files: string[] = await rm.getRawFileList('');
      const tracks = files.filter((f: string) =>
        f.toLowerCase().endsWith('.mp3') ||
        f.toLowerCase().endsWith('.m4a') ||
        f.toLowerCase().endsWith('.flac'));
      this.trackList = tracks;
      hilog.info(0x0000, TAG, 'rawfile audio found: %{public}d files', tracks.length);
      if (tracks.length === 0) {
        this.trackTitle = '(no audio in rawfile/)';
        return;
      }
      const firstFile = tracks[0];
      // Display filename (sans extension) as fallback title
      this.trackTitle = firstFile.replace(/\.(mp3|m4a|flac)$/i, '');
      // Try to extract richer metadata via AVMetadataExtractor
      try {
        const fd = await rm.getRawFd(firstFile);
        const extractor = await media.createAVMetadataExtractor();
        extractor.fdSrc = fd;
        const meta = await extractor.fetchMetadata();
        if (meta) {
          if (meta.title) this.trackTitle = meta.title;
          if (meta.artist) this.artistName = meta.artist;
          if (meta.duration) this.durationSec = Math.floor(Number(meta.duration) / 1000);
        }
        await extractor.release();
        await rm.closeRawFd(firstFile);
        hilog.info(0x0000, TAG, 'loaded metadata: title=%{public}s artist=%{public}s dur=%{public}d',
          this.trackTitle, this.artistName, this.durationSec);
      } catch (metaErr) {
        hilog.warn(0x0000, TAG, 'metadata extraction failed: %{public}s', String(metaErr));
        // trackTitle already set to filename; leave artistName empty, durationSec=1
      }
    } catch (e) {
      hilog.error(0x0000, TAG, 'rawfile scan failed: %{public}s', String(e));
      this.trackTitle = '(load error)';
    }
  }

  private formatTime(sec: number): string {
    const m = Math.floor(sec / 60);
    const s = Math.floor(sec % 60);
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  }

  private onBack(): void {
    router.back();
  }

  private onMore(): void {
    hilog.info(0x0000, TAG, 'TODO open player menu');
  }

  private onPlayPause(): void {
    this.isPlaying = !this.isPlaying;
    // TODO Phase D: this.isPlaying ? this.avPlayer?.play() : this.avPlayer?.pause();
  }

  private onPrev(): void {
    hilog.info(0x0000, TAG, 'TODO skip prev');
  }

  private onNext(): void {
    hilog.info(0x0000, TAG, 'TODO skip next');
  }

  private onShuffle(): void {
    this.isShuffled = !this.isShuffled;
  }

  private onRepeat(): void {
    this.repeatMode = (this.repeatMode + 1) % 3;
  }

  private onFavorite(): void {
    this.isFavorited = !this.isFavorited;
  }

  private onOpenQueue(): void {
    hilog.info(0x0000, TAG, 'TODO open queue sheet');
  }

  private onLyrics(): void {
    hilog.info(0x0000, TAG, 'TODO toggle lyrics');
  }

  @Builder
  private TopBar() {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        Text('⌄').fontSize(22).fontColor('#1F1F1F');
      }
      .width(40).height(40).backgroundColor(Color.Transparent)
      .accessibilityText('Collapse player')
      .onClick(() => this.onBack());

      Blank().layoutWeight(1);

      Button({ type: ButtonType.Circle, stateEffect: true }) {
        Text('⋮').fontSize(20).fontColor('#1F1F1F');
      }
      .width(40).height(40).backgroundColor(Color.Transparent)
      .accessibilityText('More')
      .onClick(() => this.onMore());
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center);
  }

  // Album art placeholder rendered as stacked colored stripes
  // (Catima barcode visual idiom).
  @Builder
  private AlbumArt() {
    Column() {
      ForEach(this.artPalette, (color: string, idx: number) => {
        Column()
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(color);
      }, (_c: string, idx: number) => `stripe_${idx}`);
    }
    .width(280)
    .height(280)
    .borderRadius(16)
    .clip(true)
    .margin({ top: 16 });
  }

  @Builder
  private ProgressBar() {
    Column() {
      Slider({
        value: this.progressSec,
        min: 0,
        max: this.durationSec,
        step: 1,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .blockColor('#1976D2')
        .selectedColor('#1976D2')
        .trackColor('#E0E0E0')
        .onChange((value: number) => {
          this.progressSec = value;
          // TODO Phase D: this.avPlayer?.seek(value * 1000)
        });

      Row() {
        Text(this.formatTime(this.progressSec))
          .fontSize(12)
          .fontColor('#666666')
          .layoutWeight(1);
        Text(this.formatTime(this.durationSec))
          .fontSize(12)
          .fontColor('#666666');
      }
      .width('100%')
      .margin({ top: 4 });
    }
    .width('100%')
    .padding({ left: 24, right: 24 })
    .margin({ top: 32 });
  }

  @Builder
  private ControlRow() {
    Row() {
      // Shuffle (small)
      Text('\u{1F500}')
        .fontSize(20)
        .fontColor(this.isShuffled ? '#1976D2' : '#666666')
        .padding(10)
        .onClick(() => this.onShuffle());

      // Previous
      Text('⏮')
        .fontSize(28)
        .fontColor('#1F1F1F')
        .padding(10)
        .onClick(() => this.onPrev());

      // Play / Pause (big)
      Column() {
        Text(this.isPlaying ? '⏸' : '▶')
          .fontSize(36)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Bold);
      }
      .width(72)
      .height(72)
      .borderRadius(36)
      .backgroundColor('#1976D2')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .margin({ left: 16, right: 16 })
      .onClick(() => this.onPlayPause());

      // Next
      Text('⏭')
        .fontSize(28)
        .fontColor('#1F1F1F')
        .padding(10)
        .onClick(() => this.onNext());

      // Repeat (small)
      Text(this.repeatMode === 2 ? '\u{1F501}' : '\u{1F501}')
        .fontSize(20)
        .fontColor(this.repeatMode === 0 ? '#666666' : '#1976D2')
        .padding(10)
        .onClick(() => this.onRepeat());
    }
    .width('100%')
    .margin({ top: 32 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  private FooterRow() {
    Row() {
      // Queue
      Column() {
        Text('☰').fontSize(20).fontColor('#1F1F1F');
        Text('Queue').fontSize(11).fontColor('#666666').margin({ top: 4 });
      }
      .layoutWeight(1)
      .onClick(() => this.onOpenQueue());

      // Lyrics
      Column() {
        Text('♫').fontSize(20).fontColor('#1F1F1F');
        Text('Lyrics').fontSize(11).fontColor('#666666').margin({ top: 4 });
      }
      .layoutWeight(1)
      .onClick(() => this.onLyrics());

      // Favorite
      Column() {
        Text(this.isFavorited ? '♥' : '♡')
          .fontSize(20)
          .fontColor(this.isFavorited ? '#E53935' : '#1F1F1F');
        Text('Favorite').fontSize(11).fontColor('#666666').margin({ top: 4 });
      }
      .layoutWeight(1)
      .onClick(() => this.onFavorite());
    }
    .width('100%')
    .padding({ top: 16, bottom: 24 })
    .alignItems(VerticalAlign.Center);
  }

  build() {
    Column() {
      this.TopBar();

      Column() {
        this.AlbumArt();

        Text(this.trackTitle)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1F1F1F')
          .margin({ top: 24 });

        Text(this.artistName)
          .fontSize(15)
          .fontColor('#666666')
          .margin({ top: 6 });

        this.ProgressBar();
        this.ControlRow();
        this.FooterRow();
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 16, right: 16 });
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF');
  }
}
