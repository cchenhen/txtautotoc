# TXT Auto TOC for KOReader

`TXT Auto TOC` is a standalone KOReader plugin that detects chapter headings in
plain-text (`.txt`) books and injects them into the default `Table of contents`
entry.

- Chinese README: [README.zh-CN.md](README.zh-CN.md)

## Features

- Auto-runs when a TXT book is opened
- Reuses per-book cached TOC data until the file changes
- Gives priority to KOReader's handmade/custom TOC
- Supports common Chinese headings, English `Chapter/Part`, and Markdown titles
- Adds a lightweight reader menu for rebuild, cache clear, and notification
  toggles

## Supported headings

- Chinese: `第N章/回/节/卷/部/篇/册`, `序章`, `楔子`, `引子`, `前言`,
  `后记`, `尾声`, `终章`, `番外`, `附录`
- English: `Chapter N`, `Part N`, `Prologue`, `Epilogue`, `Appendix`
- Markdown: `#`, `##`, `###`

## Installation

1. Copy the `txtautotoc.koplugin` directory into your KOReader `plugins/`
   directory.
2. Restart KOReader.
3. Open any TXT book.

## Usage

1. Open a TXT book in KOReader.
2. Wait for the plugin to scan the file on first open.
3. Open KOReader's default `Table of contents` entry to view the detected
   chapters.
4. If the TOC looks wrong or the TXT file changed, open `TXT Auto TOC` in the
   reader menu and choose `重建当前书籍目录`.
5. If you want to remove the current cached result and force a fresh scan later,
   choose `清除当前书籍缓存`.

## Behavior

- Auto generation is enabled by default.
- The plugin only handles TXT documents.
- The generated TOC is reused from cache until the TXT file changes.
- The generated TOC only activates when at least 3 valid chapter hits are
  mapped.
- KOReader handmade/custom TOC always takes priority over the generated one.

## Reader Menu

- `启用自动生成`
- `重建当前书籍目录`
- `清除当前书籍缓存`
- `显示通知`

## Development

This repository keeps the plugin self-contained. Tests use a small Luajit-based
spec runner instead of KOReader's full emulator.

Run tests:

```bash
luajit spec/run.lua
```

## Notes

- Only TXT documents are handled in v1.
- A generated TOC activates only when at least 3 mapped chapter hits are found.
- Existing handmade TOCs always win.
