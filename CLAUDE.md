# sleep-guard の作業方針

## リリース運用（修正ごとに毎回行う）

このリポジトリは修正のたびに **コミット → タグ → プッシュ → GitHub リリース** まで
通しで行う。兄弟プロジェクト `qrxx` と同じ形に揃えてある。

- リモート: `https://github.com/iosxi/sleep-guard.git`
- ブランチ: `master`（`main` ではない）
- バージョン: `v0`, `v1`, `v2` … の整数。直前のタグ +1。
  現在の最新は `git tag --sort=-v:refname | head -1` で確認する。

### 手順

1. **コミット** — 1 行目は `vN: <何をしたか>`。本文に箇条書きで変更点。
   末尾に `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` を付ける。

2. **タグ** — 注釈付きタグ。メッセージはコミットの 1 行目と同じにする。

   ```bash
   git tag -a vN -m "vN: <何をしたか>"
   ```

3. **プッシュ**

   ```bash
   git push origin master && git push origin vN
   ```

4. **リリース** — タグ名・リリース名ともに `vN`。`SleepGuard.exe` を添付する。

   ```bash
   gh release create vN SleepGuard.exe --title "vN" --notes-file <本文>
   ```

### リリース本文の書き方

qrxx のリリースに倣い、**日本語で、何をなぜ変えたかを実測値つきで書く**。
一行の要約で終わらせない。よく使う構成:

- 冒頭 1〜2 段落で「何ができるようになったか」と「なぜそうしたか」
- `## 使いかた` — 利用者から見た操作
- `## 中身` — 実装上の判断と、その根拠になった実測値（表やコードブロック）
- `## 入れかた` — 差し替え手順、ファイルサイズ、動作確認した環境

### exe を変更したとき

`SleepGuard.ps1` を直したら **exe を作り直してからコミットする**。
ビルドコマンドは README.md の「ビルド」を見る。リリースには必ず新しい exe を添付する。

## 検証について

GUI を実際に動かして確かめるときは、ダイアログが利用者の画面を奪う。
プロセスを直接起動・終了させる方法で確かめ、キー操作は送らない。
（`Start-Process -PassThru` で起動し `MainWindowTitle` を見て `Kill()` する、など）
