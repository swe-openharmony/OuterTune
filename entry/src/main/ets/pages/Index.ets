// ====================================================================
// Page: Index (OuterTune L0 Home — search + quick actions + bottom nav)
// Android baseline: D:/OH-Appforge/_doc_screenshots_v2/OuterTune/L0_home.png
// Layout contract:
//   - Top search bar pill: 🔍 "Search" placeholder + gear ⚙ (right)
//   - Three quick-action circle tiles (centered row): History | Stats | Local scanner
//   - Bottom nav 4 tabs: Home (active, filled bg) | Songs | Folders | Library
// Navigation:
//   - "History" quick-action tile (and any tile tap) → PlayerScreenPage
//     (acts as the "Now Playing" entry point on the home shell)
// ====================================================================

import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'OuterTuneIndex';

interface QuickAction {
  id: string;
  label: string;
  glyph: string;
}

interface NavTab {
  id: string;
  label: string;
  glyph: string;
}

@Entry
@Component
struct Index {
  @State private currentTab: string = 'home';
  @State private query: string = '';

  private actions: QuickAction[] = [
    { id: 'history', label: 'History',       glyph: '↻' },
    { id: 'stats',   label: 'Stats',         glyph: '📈' },
    { id: 'local',   label: 'Local scanner', glyph: '💾' },
  ];

  private tabs: NavTab[] = [
    { id: 'home',    label: 'Home',    glyph: '🏠' },
    { id: 'songs',   label: 'Songs',   glyph: '♪' },
    { id: 'folders', label: 'Folders', glyph: '📁' },
    { id: 'library', label: 'Library', glyph: '🎵' },
  ];

  aboutToAppear(): void {
    hilog.info(0x0000, TAG, 'OuterTune L0 home mounted');
  }

  private openPlayer(reason: string): void {
    hilog.info(0x0000, TAG, 'open player (reason=%{public}s) → PlayerScreenPage', reason);
    router.pushUrl({ url: 'pages/PlayerScreenPage' });
  }

  private onTabTap(tab: NavTab): void {
    this.currentTab = tab.id;
    console.info(`TODO: tab ${tab.id}`);
  }

  @Builder
  private SearchBar() {
    Row() {
      Row() {
        Text('🔍').fontSize(18).fontColor('#444444').margin({ left: 16, right: 12 });
        TextInput({ text: this.query, placeholder: 'Search' })
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .placeholderColor('#888888')
          .fontSize(15)
          .onChange((v: string) => { this.query = v; });
        Text('⚙').fontSize(20).fontColor('#1F1F1F').width(40).height(40).textAlign(TextAlign.Center)
          .onClick(() => console.info('TODO: settings'));
      }
      .width('92%').height(48)
      .backgroundColor('#E0DEE6').borderRadius(24)
      .alignItems(VerticalAlign.Center);
    }
    .width('100%').padding({ top: 16, bottom: 12 }).justifyContent(FlexAlign.Center);
  }

  @Builder
  private QuickActionTile(a: QuickAction) {
    Column() {
      Text(a.glyph).fontSize(22).fontColor('#1F1F1F')
        .width(56).height(56).textAlign(TextAlign.Center)
        .backgroundColor('#E5E3EB').borderRadius(28);
      Text(a.label).fontSize(13).fontColor('#1F1F1F').margin({ top: 6 });
    }
    .layoutWeight(1)
    .onClick(() => this.openPlayer(a.id));
  }

  @Builder
  private QuickActions() {
    Row() {
      ForEach(this.actions, (a: QuickAction) => {
        this.QuickActionTile(a);
      }, (a: QuickAction) => a.id);
    }
    .width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 });
  }

  @Builder
  private BottomNav() {
    Row() {
      ForEach(this.tabs, (tab: NavTab) => {
        Column() {
          if (this.currentTab === tab.id) {
            Text(tab.glyph).fontSize(18).fontColor('#1F1F1F')
              .width(56).height(28).textAlign(TextAlign.Center)
              .backgroundColor('#DCE3F7').borderRadius(14);
          } else {
            Text(tab.glyph).fontSize(18).fontColor('#555555')
              .width(56).height(28).textAlign(TextAlign.Center);
          }
          Text(tab.label).fontSize(11).fontColor('#1F1F1F').margin({ top: 4 });
        }
        .layoutWeight(1).height(64).justifyContent(FlexAlign.Center)
        .onClick(() => this.onTabTap(tab));
      }, (tab: NavTab) => tab.id);
    }
    .width('100%').height(68).backgroundColor('#F1EFF6');
  }

  build() {
    Column() {
      this.SearchBar();
      this.QuickActions();
      Blank().layoutWeight(1);
      this.BottomNav();
    }
    .width('100%').height('100%').backgroundColor('#F4F2F8');
  }
}
