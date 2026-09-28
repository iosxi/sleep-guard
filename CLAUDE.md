# sleep-guard の作業方針

## リリース運用

**手順は共通の `~/.claude/CLAUDE.md`「修正が終わったら、リリースまで通す」に従う。**
ここにはこのリポジトリ固有の事情だけを書く。

- リモート: `https://github.com/iosxi/sleep-guard.git`（`iosxi/sleep-guard`）
- ブランチ: **`master`**（`main` ではない）
- 最新バージョンの確認: `git tag --sort=-v:refname | head -1`
- リリースの添付物: **`SleepGuard.exe`**。改名もコピーもせず、そのまま
  `gh release create` に渡す。
  **版入りの名前にしない。** この exe は単体で置いて使うものなので、利用者は
  同じ名前に上書きして更新する。`SleepGuard-vN.exe` のように名前が版ごとに
  変わると、更新するたびに旧版が隣に残り続け、ショートカットや
  タスクスケジューラの参照も切れてしまう。
  （v1〜v4 は版入りの名前で添付してしまっている。v5 以降がこの方針。）

### exe を変更したとき

ソース（`sleepguard.c` / `sleepguard.rc` など）を直したら、**`build.cmd` で exe を
作り直してからコミットする**。exe はリポジトリに追跡させているので、コミットに含める。
v6 で PowerShell（ps2exe）版から C 版に置き換えた。`SleepGuard.ps1` はもう無い。

### バージョンの持ち方

タグの `vN` とは別に、exe の `FileVersion`（`sleepguard.rc` の VERSIONINFO）がある。
連動はさせていない（v6 時点で `2.0.0`）。機能が変わったら上げる。

## 動作確認について

GUI アプリなので、ダイアログを出すと**利用者の画面の前面を奪う**。
確認するときは画面を撮ったりキー操作を送ったりせず、プロセスを直接扱う。

- **ダイアログを経由しない確認**は、コマンドライン `-s <秒>` / `-m <分>` / `-nodisplay`
  で直接開始できる。実行状態は管理者権限なしで
  `CallNtPowerInformation(SystemExecutionState)` から読める
  （`powercfg /requests` は管理者権限が要るので使えない）。
- **ダイアログの確認**は、起動して `MainWindowTitle` が「スリープ防止」になるのを見て、
  子ウィンドウの文字・チェック状態を `EnumChildWindows` で読み、「開始」を押す前に
  `Kill()` する。押す前なら `SetThreadExecutionState` は呼ばれていない。

### 実際にスリープさせて確かめるとき

- `SYSTEM_POWER_INFORMATION.TimeRemaining`（アイドルスリープまでの残り秒）は
  この PC では常に `0xFFFFFFFF` で使えない。実際に寝かせて壁時計の飛びで見る。
- 寝かせたら `SetWaitableTimer(..., fResume=TRUE)` のウェイクタイマーで自動復帰させる
  （AC のスリープ解除タイマーは有効）。
- スリープ設定は `powercfg /change standby-timeout-ac N` で管理者なしで変えられる。
  **元の値（AC: 画面オフ 3 分 / スリープ 10 分）に必ず戻す。**
- スリープ設定を画面オフより短くすると、この PC では画面が消えるまで寝ないので、
  測るときは「画面オフ < スリープ」の順にする。
