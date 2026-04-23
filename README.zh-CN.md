# KOReader TXT Auto TOC 中文说明

`TXT Auto TOC` 是一个独立的 KOReader 插件，用来识别 `.txt` 电纸书里的章节标题，并把识别结果直接接入 KOReader 默认的“目录 / Table of contents”入口。

## 功能简介

- 打开 TXT 书籍时自动尝试识别章节
- 识别结果按书缓存，文件没有变化时直接复用
- 如果 KOReader 已经有手工自定义目录，插件会自动让位
- 支持常见中文标题、英文 `Chapter/Part` 和 Markdown 标题
- 提供简单菜单，用于重建目录、清除缓存和通知开关

## 支持的标题格式

- 中文：`第N章/回/节/卷/部/篇/册`、`序章`、`楔子`、`引子`、`前言`、`后记`、`尾声`、`终章`、`番外`、`附录`
- 英文：`Chapter N`、`Part N`、`Prologue`、`Epilogue`、`Appendix`
- Markdown：`#`、`##`、`###`

## 安装方法

1. 将 `txtautotoc.koplugin` 整个目录复制到 KOReader 的 `plugins/` 目录中。
2. 重启 KOReader。
3. 打开一本 `.txt` 书籍，插件会在首次打开时自动尝试生成目录。

## 使用方法

### 1. 自动识别目录

1. 在 KOReader 中打开一本 TXT 书籍。
2. 首次打开时，插件会自动扫描正文并尝试识别章节标题。
3. 如果识别成功，直接打开 KOReader 默认的“目录 / Table of contents”即可看到生成后的章节目录。

### 2. 手动重建目录

如果你修改了 TXT 文件内容，或者第一次识别结果不理想：

1. 打开阅读菜单。
2. 进入 `TXT Auto TOC`。
3. 点击 `Rebuild TOC for current book`。
4. 插件会重新扫描当前这本书，并刷新默认目录。

### 3. 清除当前书籍缓存

如果你想删除这本书已有的识别结果：

1. 打开阅读菜单。
2. 进入 `TXT Auto TOC`。
3. 点击 `Clear cached TOC for current book`。

清除后，下次重新打开这本书，或者手动重建时，会重新生成目录。

### 4. 开关自动生成

如果你暂时不希望插件自动工作：

1. 打开阅读菜单。
2. 进入 `TXT Auto TOC`。
3. 点击 `Enable auto generation` 进行开关切换。

关闭后，插件不会在打开 TXT 时自动接管目录。

### 5. 通知开关

如果你不想看到插件提示：

1. 打开阅读菜单。
2. 进入 `TXT Auto TOC`。
3. 点击 `Show notifications` 进行开关切换。

## 菜单说明

`TXT Auto TOC` 菜单包含以下项目：

- `Enable auto generation`
- `Rebuild TOC for current book`
- `Clear cached TOC for current book`
- `Show notifications`

## 工作规则

- 只处理 TXT 文档，不处理 EPUB、PDF 等格式
- 只有当成功映射到至少 3 个有效章节时，才会正式接管默认目录
- 同一本书在文件未变化时会优先使用缓存结果
- 如果这本书已经有 KOReader 手工创建的自定义目录，插件不会覆盖它

## 开发与测试

项目使用轻量级 Luajit 测试入口，不依赖 KOReader 完整模拟器。

运行测试：

```bash
luajit spec/run.lua
```
