# OJAD 重音

个人学习用的 iOS App，离线查询日语单词各活用形的重音，界面和曲线仿照 [OJAD（オンライン日本語アクセント辞書）](https://www.gavo.t.u-tokyo.ac.jp/ojad/)。

- **离线查询**：约 11.6 万词的词典打包在 App 里，不联网也能查。辞書形重音来自 Kanjium；动词、形容词各活用形的重音按规则推导（用 510 个 OJAD 词条校验过，动词约 99%、い形容词 100%、な形容词约 97% 与 OJAD 一致），音高曲线按藤崎模型在本机绘制。
- **输入即提示**：在搜索框里输入漢字、かな或罗马字（如 `tabe`），会按词频显示最多 10 个候选词。
- **例句**：离线例句来自 JMdict 收录的 Tatoeba 句子（附英文翻译）；可以在线加载更多（优先简体中文翻译）。点开一句后，可以在线请求スズキクン分析整句的语调。
- **在线核对**：任何结果都可以一键「在线查询 OJAD」，与原站对照。
- **历史 / 收藏**：保存在本机（SwiftData），升级后保留。在线查过的结果会缓存，以减少对 OJAD 的请求。
- **不使用任何音频或合成语音**，遵守 OJAD 的使用条款（仅限教育和学术研究用途）。

## 安装

下载最新的未签名 ipa：<https://github.com/Umasteas/OJAD/releases/latest/download/OJAD.ipa>。然后在 iPhone 上用 Feather 或 ESign，配合自己的 `.p12` 和 `.mobileprovision` 签名并安装，详见 [docs/install.md](docs/install.md)。

## 结构

```text
Packages/OJADKit/   离线词典（SQLite）、活用重音推导、候选词、OJAD / Tatoeba 客户端、藤崎曲线
                    （Linux 和 macOS 都能 swift test）
App/                SwiftUI App（XcodeGen 的 project.yml，由 CI 生成 .xcodeproj）
scripts/dictionary/ 离线词典的构建脚本：从固定版本的数据源（sources.json，带 sha256）生成 Dictionary.sqlite
scripts/            App 图标生成脚本等
```

## 开发

```bash
cd Packages/OJADKit && swift test        # Linux 或 macOS 均可（Linux 需要 libsqlite3-dev）
python3 -m unittest discover -s scripts/dictionary -p 'test_*.py'
python3 scripts/dictionary/build.py --out App/Generated/Dictionary.sqlite   # 下载固定版本的数据并生成词典
cd App && xcodegen generate && open OJAD.xcodeproj   # 需要 Mac，且先生成词典
```

词典不提交到仓库：CI 每次用 `.github/actions/build-dictionary` 从 `scripts/dictionary/sources.json` 里固定的版本下载（校验 sha256）并重新生成，结果可复现。要升级数据，改 `sources.json` 的地址和 sha256 即可。

CI 的分工如下：

- `OJADKit` workflow：在 Linux 和 macOS 上跑包的测试，并测试词典构建脚本。
- `iOS` workflow：每个 PR 都在 iPhone 模拟器上 build 并跑测试，不签名。
- `iOS screenshots` workflow：改动 App 的 PR 会额外跑一遍 UI 流程截图（会真实请求スズキクン一次，失败也不阻塞合并）。
- `IPA` workflow：每个 PR 都会构建一个未签名的 Release 版 `.ipa`，只检查能否构建；`main` 上还会把它发布到 GitHub Releases。

## 数据来源

- 重音与词频：[Kanjium](https://github.com/mifunetoshiro/kanjium)，CC BY-SA 4.0。The pitch accent notation, verb particle data, phonetics, homonyms and other additions or modifications to EDICT, KANJIDIC or KRADFILE were provided by Uros O. through his free database.
- 词条与释义：[JMdict](https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project)（Electronic Dictionary Research and Development Group），CC BY-SA 4.0，经 [jmdict-simplified](https://github.com/scriptin/jmdict-simplified) 转换。打包的 `Dictionary.sqlite` 是这两者的衍生作品，同样以 CC BY-SA 4.0 提供。
- 例句：Tatoeba，CC BY 2.0 FR，作者见各例句页面
- 在线功能：OJAD，東京大学 大学院工学系研究科 峯松研究室・齋藤研究室
- [SwiftSoup](https://github.com/scinfu/SwiftSoup)：MIT
