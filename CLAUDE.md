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

`SleepGuard.ps1` を直したら、**exe を作り直してからコミットする**。
exe はリポジトリに追跡させているので、コミットに含める。
ビルドコマンドとメタデータは README.md の「ビルド」を見る。

### バージョンの持ち方

このプロジェクトには Android の `versionCode` にあたるものが無い。
exe のメタデータに `FileVersion` があるが、タグの `vN` とは別系統で、
今のところ連動させていない（v5 時点で `1.1.0`）。

## 動作確認について

GUI アプリなので、起動すると**利用者の画面にダイアログが出て前面を奪う**。
確認するときは画面を撮ったりキー操作を送ったりせず、プロセスを直接扱う。

```powershell
$p = Start-Process .\SleepGuard.exe -PassThru
Start-Sleep -Seconds 3
$p.MainWindowTitle   # 「スリープ防止」が出れば起動成功
$p.Kill()            # 「開始」を押す前なら実行状態は何も変わっていない
```

「開始」を押す前に落とす限り `SetThreadExecutionState` は呼ばれないので、
電源まわりの状態を汚さずに済む。
