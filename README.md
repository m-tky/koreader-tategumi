# koreader-tategumi

**English** | [日本語](#日本語)

**KOReader fork for Japanese vertical text (縦書き) and right-to-left manga.**

This is a personal fork of [KOReader](https://github.com/koreader/koreader) for
Japanese books. It adds `writing-mode: vertical-rl` rendering for EPUB novels and
automatic right-to-left (RTL) page order for manga EPUBs and comic archives.
It is regularly synced with upstream KOReader (master / nightly).

![Vertical text rendering of 三四郎 (Natsume Soseki)](doc/screenshots/tategumi.png)

## Downloads

Download the build for your device from the
[latest release](https://github.com/m-tky/koreader-tategumi/releases/latest).

## Installation

### Standard installation

Installation steps are the same as upstream KOReader:
[Android](https://github.com/koreader/koreader/wiki/Installation-on-Android-devices) •
[Kindle](https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices) •
[Kobo](https://github.com/koreader/koreader/wiki/Installation-on-Kobo-devices)

Kindle, Kobo, PocketBook, Cervantes, and reMarkable builds support KOReader's
file-based OTA updater: **Menu → Update → Check for update**. Android APK builds
use Android's APK install flow instead; the APKs published by this fork's GitHub
releases support the same in-app update check, download the next APK in-app, and
then hand it to Android's installer.

### Fonts for Japanese vertical text

For correct vertical punctuation and symbols, select a Japanese font with the
OpenType `vert` and `vrt2` features—`vrt2` is especially important for some
composite vertical glyphs. Fonts without these vertical substitutions can leave
brackets, quotation marks, dashes, and other symbols in horizontal forms.
**Noto Sans CJK JP** and **Noto Serif CJK JP** are suitable examples; add one
through KOReader's font settings and select it as the document font.

### Kindle: install with KPM

On a Kindle with the Kindle Package Manager (KPM), add this fork's repository once:

```text
;kpm add-repo https://raw.githubusercontent.com/m-tky/koreader-tategumi/master/kpm/manifest.json
```

Then install either channel:

```text
;kpm install koreader-tategumi
;kpm install koreader-tategumi-nightly
```

The first command installs the latest numbered release; the second installs the
latest nightly build. Both support Kindle PW2 and newer, including Kindle HF
devices. They share the same KOReader installation directory, so installing one
replaces the other while keeping your KOReader settings.

Launch the selected package from the Kindle search bar:

```text
;kpm launch koreader-tategumi
;kpm launch koreader-tategumi-nightly
```

Installation also adds a matching scriptlet to the Kindle library. If KUAL is
installed, its existing KOReader menu entry remains available as well; KPM handles
installation and updates, whereas KUAL is a launcher UI.

### Switching from vanilla KOReader

If you already have vanilla KOReader installed, you can switch to this fork without
reinstalling from scratch:

1. Copy `frontend/ui/otamanager.lua` from this repository into
   `<koreader-dir>/frontend/ui/otamanager.lua` on your device.
2. Restart KOReader and go to **Menu → Update → Check for update**.
3. KOReader will download and apply this fork's build automatically.

This shortcut only works for file-based installs that expose a writable
`<koreader-dir>/frontend/` directory. Android APK installs, including Boox
devices, cannot use this migration path because the application files are
packaged inside the APK. If you installed KOReader from an APK, install this
fork's Android APK from the release page instead. After that, this fork's GitHub
APK builds can check for updates in-app, download the next APK, and hand it to
Android's installer.

## Nightly builds

In addition to tagged releases, a **nightly** build is produced automatically from
the latest `master` every day (around 05:00 JST) for all supported devices. Use it
to get vertical-text fixes and features before they land in a numbered release —
at the cost of less testing, so it may be less stable.

- **Download**: the rolling
  [`nightly` pre-release](https://github.com/m-tky/koreader-tategumi/releases/tag/nightly)
  (labelled `vYYYY.MM.DD`). It is replaced in place by each build, so the link
  always points at the most recent one.
- **OTA for nightly builds**: on Kindle, Kobo, PocketBook, Cervantes,
  reMarkable, and this fork's Android APK builds, switch the update channel to
  development if you want to receive nightly builds:
  **Menu → Update → Settings → Update channel → Development**, then
  **Menu → Update → Check for update**. Switch back to **Stable** to return to
  numbered releases.

## Using vertical text

EPUBs that already contain `writing-mode: vertical-rl` in their CSS (most commercial
Japanese novels do) render vertically automatically.

For EPUBs that do not include this CSS, add the following via
**Document (page icon) → Style tweaks → Book-specific tweak**
(long-press to edit):

```css
body { writing-mode: vertical-rl !important; }
```

## Automatic RTL page order (漫画・右開き)

Japanese manga EPUBs and CBZ/CBR/CBT comic archives with right-to-left page order
are detected automatically when you open them for the first time:

- **EPUB**: reads `page-progression-direction="rtl"` from the OPF spine
- **CBZ/CBR/CBT**: reads the standard
  `<Manga>YesAndRightToLeft</Manga>` value from `ComicInfo.xml`
  (`<ReadingDirection>RTL</ReadingDirection>` and `RightToLeft` are also
  accepted for compatibility)

`ComicInfo.xml` may be at the archive root or in a subdirectory. The detector also
handles namespaced XML, a UTF-8 BOM, comments, case differences in the archive path,
and common separator/capitalization variants of the compatibility values.

When RTL is detected a notification appears. Page turns—including physical left
and right arrow keys—follow the RTL reading order, and the progress bar fills from
right (page 1) to left (last page).

You can always override the detected direction via
**Menu → Taps & gestures → Page turns → Switch page-turn direction**.
The override is saved per-book and will not be overwritten on subsequent opens.

## Known limitations

- **Mixed writing modes within a single page**: Books that switch writing mode per
  section — a vertical novel with a horizontal author bio, colophon or ad page, for
  example — now render each page in its own mode. What is still unsupported is mixing
  horizontal and vertical content *within one page* (e.g. a horizontal table or block
  embedded in vertical body text); such intra-page mixing may not display correctly.

- **Whitespace between ruby groups**: EPUBs with stray whitespace adjacent to ruby
  groups may show a small gap between the ruby and the following character. This is
  a property of the EPUB source, not a rendering bug.

- **Double paragraph indent**: Some EPUBs use a U+3000 ideographic space (`　`) for
  indentation while CREngine also applies its default `text-indent: 1.2em`, producing
  a two-character indent. Fix per-book via **Document (page icon) → Style
  tweaks → Paragraph first-line indentation → 0** (no indent).

## Compatibility

This fork tracks upstream KOReader master, so its base is equivalent to upstream
**nightly**, not the stable release. Reports about third-party plugins are welcome
even without upstream verification, but noting whether the issue also reproduces in
vanilla upstream KOReader nightly helps triage — plugin breakage that also occurs
upstream is out of scope for this fork.

### Related plugins

The following plugins are maintained alongside this fork or tuned for
Japanese/vertical-rl use:

- **Bookends** ([m-tky/bookends.koplugin](https://github.com/m-tky/bookends.koplugin)) —
  configurable text overlays. Forked from
  [AndyHazz/bookends.koplugin](https://github.com/AndyHazz/bookends.koplugin) with
  vertical-rl auto-detection so progress bars fill right→left in vertical documents.

- **koreader-skk** ([m-tky/koreader-skk](https://github.com/m-tky/koreader-skk)) —
  SKK Japanese input plugin for KOReader. KOReader's built-in Japanese keyboard
  can enter hiragana and katakana, while this plugin adds SKK-style kana-to-kanji
  conversion with a bundled dictionary. It supports both physical keyboards and
  a touch virtual keyboard.

## Support

If you find this vertical text fork useful, you can support its development:

[![GitHub Sponsors](https://img.shields.io/github/sponsors/m-tky?label=Sponsor&logo=GitHub&style=for-the-badge)](https://github.com/sponsors/m-tky)

For the upstream KOReader project itself, please see
[koreader/koreader](https://github.com/koreader/koreader).

## Acknowledgements

KOReader is an open-source e-book reader for e-ink devices, developed by volunteers
around the world. The vertical text implementation in this fork is built
on their work. See [upstream KOReader](https://github.com/koreader/koreader) for the
project's main features, supported formats, and developer documentation.

[![Last commit](https://img.shields.io/github/last-commit/m-tky/koreader-tategumi?color=orange)](https://github.com/m-tky/koreader-tategumi/commits/master)
[![License](https://img.shields.io/github/license/koreader/koreader)](https://github.com/koreader/koreader/blob/master/COPYING)

---

# 日本語

[English](#koreader-tategumi) | **日本語**

**KOReader を日本語の縦書きと右開き漫画に対応させた個人フォークです。**

日本語書籍向けの [KOReader](https://github.com/koreader/koreader) フォークです。
EPUB 小説の `writing-mode: vertical-rl` レンダリングに加え、漫画 EPUB とコミック
アーカイブの右から左（RTL）へのページ順序を自動検出します。
upstream KOReader（master / nightly）と定期的に同期しています。

![三四郎（夏目漱石）の縦書き表示](doc/screenshots/tategumi.png)

## ダウンロード

ご利用の端末向けビルドを
[最新リリース](https://github.com/m-tky/koreader-tategumi/releases/latest)
からダウンロードしてください。

## インストール

### 通常のインストール

インストール手順は upstream KOReader と同じです:
[Android](https://github.com/koreader/koreader/wiki/Installation-on-Android-devices) •
[Kindle](https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices) •
[Kobo](https://github.com/koreader/koreader/wiki/Installation-on-Kobo-devices)

Kindle、Kobo、PocketBook、Cervantes、reMarkable 版は KOReader のファイル
差し替え型 OTA アップデートに対応しています: **メニュー → 更新 → 更新を確認**。
Android APK 版は Android の APK インストール機能を使います。本フォークの GitHub
リリースで配布している APK では、同じアプリ内の更新確認から次の APK を検出・
ダウンロードし、Android のインストーラに渡して更新できます。

### 日本語縦書き用フォント

縦書きの約物・記号を正しく表示するには、OpenType の `vert` と `vrt2` 機能を
持つ日本語フォントを選んでください。特に `vrt2` は一部の複合縦組み字形に必要です。
これらの縦組み字形に未対応のフォントでは、括弧・引用符・ダッシュなどが横書き用の
字形のまま表示されることがあります。**Noto Sans CJK JP** や **Noto Serif CJK JP**
が適しています。KOReader のフォント設定から追加し、文書フォントとして選択してください。

### Kindle: KPM を使ったインストール

Kindle Package Manager（KPM）が導入済みの Kindle では、最初に一度だけ本フォークの
リポジトリを追加します:

```text
;kpm add-repo https://raw.githubusercontent.com/m-tky/koreader-tategumi/master/kpm/manifest.json
```

続いて、利用したいチャンネルをインストールします:

```text
;kpm install koreader-tategumi
;kpm install koreader-tategumi-nightly
```

上は最新の番号付きリリース、下は最新の nightly ビルドを導入します。いずれも
Kindle PW2以降（Kindle HF を含む）に対応します。両者は同じ KOReader の
インストール先を使うため、一方を導入するともう一方を置き換えますが、KOReaderの
設定は維持されます。

選択したパッケージは Kindle の検索欄から起動できます:

```text
;kpm launch koreader-tategumi
;kpm launch koreader-tategumi-nightly
```

インストール時には、対応する scriptlet も Kindle のライブラリへ追加されます。
KUAL が導入済みなら、従来の KOReader メニューからも起動できます。KPM は
インストール・更新を扱い、KUAL は起動用UIという役割分担です。

### vanilla KOReader からの移行

既に vanilla KOReader をインストール済みの場合、再インストールせずに
本フォークへ切り替えられます:

1. 本リポジトリの `frontend/ui/otamanager.lua` を端末上の
   `<koreader-dir>/frontend/ui/otamanager.lua` にコピーします。
2. KOReader を再起動し、**メニュー → 更新 → 更新を確認** へ進みます。
3. KOReader が本フォークのビルドを自動的にダウンロード・適用します。

この方法が使えるのは、端末上で書き込み可能な `<koreader-dir>/frontend/`
ディレクトリが見えているファイル配置型のインストールだけです。Boox 端末を含む
Android APK 版は、アプリ本体が APK 内にパッケージされるため、この移行方法は
使えません。APK からインストールしている場合は、リリースページから本フォークの
Android APK をインストールしてください。その後は、アプリ内で更新を確認し、
次の APK をダウンロードして Android のインストーラで更新できます。

## Nightly ビルド

タグ付きリリースに加え、毎日（日本時間 5:00 頃）最新の `master` から **nightly**
ビルドが全対応端末向けに自動生成されます。番号付きリリースに入る前の縦書き
修正・機能を試せますが、テスト量が少ないため安定性は劣ります。

- **ダウンロード**: ローリング更新の
  [`nightly` pre-release](https://github.com/m-tky/koreader-tategumi/releases/tag/nightly)
  （`vYYYY.MM.DD` ラベル）。各ビルドで置き換わるため、リンクは常に最新を指します。
- **nightly ビルドの OTA**: Kindle、Kobo、PocketBook、Cervantes、reMarkable、
  および本フォークの Android APK ビルドでは、nightly ビルドを受け取りたい場合に
  更新チャンネルを Development に切り替えてください:
  **メニュー → 更新 → 設定 → 更新チャンネル → Development**、続いて
  **メニュー → 更新 → 更新を確認**。番号付きリリースに戻すには **Stable** に
  切り替えてください。

## 縦書きの利用方法

CSS に `writing-mode: vertical-rl` が既に含まれている EPUB（市販の日本語小説の
多くがそうです）は自動的に縦書きで表示されます。

含まれていない EPUB には、**Document（文書アイコン）→ Style tweaks →
Book-specific tweak**（長押しで編集）から以下を追加してください:

```css
body { writing-mode: vertical-rl !important; }
```

## RTL ページ順序の自動検出（漫画・右開き）

日本語の漫画 EPUB や、右から左へのページ順序を持つ CBZ/CBR/CBT コミック
アーカイブは、初回オープン時に自動検出されます:

- **EPUB**: OPF spine の `page-progression-direction="rtl"` を読み取り
- **CBZ/CBR/CBT**: `ComicInfo.xml` の標準指定
  `<Manga>YesAndRightToLeft</Manga>` を読み取り
  （互換性のため `<ReadingDirection>RTL</ReadingDirection>` と `RightToLeft` にも対応）

`ComicInfo.xml` はアーカイブ直下だけでなくサブディレクトリ内にあっても検出
されます。名前空間付き XML、UTF-8 BOM、コメント、アーカイブ内パスの大文字・
小文字の違い、互換値の一般的な区切り・大文字表記の違いにも対応しています。

RTL が検出されると通知が表示されます。物理キーボードの左右矢印を含むページ
めくりが RTL の読書順序に従い、進捗バーは右（1 ページ目）から左（最終ページ）
に進みます。

検出された方向は **メニュー → タップとジェスチャー → ページめくり →
ページめくり方向を切り替え** からいつでも上書きできます。変更内容は本ごとに
保存され、次回オープン時に上書きされません。

## 既知の制限

- **1 ページ内での書字方向混在**: 縦書き小説に横書きの著者紹介・奥付・広告が
  混在するようなセクション単位の切り替えは、ページごとに各々の方向で描画
  されるようになりました。一方、**1 ページ内**に縦書きと横書きを混在させる
  ケース（縦書き本文中に横書きの表やブロックなど）は未対応で、正しく表示
  されない場合があります。

- **ルビ間の空白**: ルビグループに隣接する空白文字が EPUB ソースに含まれている
  場合、ルビと次の文字の間に小さなギャップが残ることがあります。これは EPUB
  側の仕様であり、レンダリングのバグではありません。

- **段落字下げの二重化**: 一部の EPUB は U+3000（`　` 全角スペース）で字下げを
  行いますが、CREngine がデフォルトの `text-indent: 1.2em` も適用するため二
  文字分の字下げになります。本ごとに **Document（文書アイコン）→ Style tweaks
  → Paragraph first-line indentation → 0**（インデント無し）で修正してください。

## 互換性

本フォークは upstream KOReader の master を追従しているため、その基盤は
upstream の安定版ではなく **nightly** 相当です。サードパーティプラグインの
不具合報告は、upstream での検証なしでも歓迎します。ただし本家 upstream
KOReader nightly でも同様に再現するか併記いただけると振り分けに役立ちます
— upstream でも壊れているプラグインは本フォークの対象外です。

### 関連プラグイン

以下のプラグインは、本フォークとあわせて利用できるよう整備しています:

- **Bookends** ([m-tky/bookends.koplugin](https://github.com/m-tky/bookends.koplugin)) —
  設定可能なテキストオーバーレイ。
  [AndyHazz/bookends.koplugin](https://github.com/AndyHazz/bookends.koplugin) から
  フォークし、縦書きドキュメントで進捗バーが右→左に進むよう vertical-rl
  を自動検出します。

- **koreader-skk** ([m-tky/koreader-skk](https://github.com/m-tky/koreader-skk)) —
  KOReader 向けの SKK 日本語入力プラグインです。KOReader 標準の日本語
  キーボードではひらがな・カタカナ入力までだったところを、同梱辞書を使った
  SKK 方式のかな漢字変換に対応させます。物理キーボードとタッチ用の仮想
  キーボードの両方で利用できます。

## サポート

本縦書きフォークがお役に立った場合、開発を支援していただけると幸いです:

[![GitHub Sponsors](https://img.shields.io/github/sponsors/m-tky?label=Sponsor&logo=GitHub&style=for-the-badge)](https://github.com/sponsors/m-tky)

upstream の KOReader プロジェクト本体については
[koreader/koreader](https://github.com/koreader/koreader) をご覧ください。

## 謝辞

KOReader は世界中のボランティアが開発する e-ink デバイス向けオープンソース
電子書籍リーダーです。本フォークの縦書き実装はその成果の上に
構築されています。本プロジェクトの主要機能・対応フォーマット・開発者向け
ドキュメントは [upstream KOReader](https://github.com/koreader/koreader) を
ご参照ください。
