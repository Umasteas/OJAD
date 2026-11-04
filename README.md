# OJAD 重音

个人学习用的 iOS App，用来查询 [OJAD（オンライン日本語アクセント辞書）](https://www.gavo.t.u-tokyo.ac.jp/ojad/)。

- **单词検索**：查看各活用形的重音（高音上划线 + 红色的アクセント核）。音高曲线用 OJAD 页面内联的数据，按藤崎模型在本机重画。
- **例句**：来自 [Tatoeba](https://tatoeba.org)（CC BY 2.0 FR），优先显示简体中文翻译。点开一句后，用スズキクン的分析结果画出整句的语调曲线。
- **历史 / 收藏**：保存在本机（SwiftData）。查过的结果也会缓存，以减少对 OJAD 的请求。
- **不使用任何音频或合成语音**，遵守 OJAD 的使用条款（仅限教育和学术研究用途）。

## 结构

```text
Packages/OJADKit/   OJAD / Tatoeba 客户端、HTML 解析、藤崎曲线（Linux 和 macOS 都能 swift test）
App/                SwiftUI App（XcodeGen 的 project.yml，由 CI 生成 .xcodeproj）
scripts/            App 图标生成脚本
```

## 开发

```bash
cd Packages/OJADKit && swift test        # Linux 或 macOS 均可
cd App && xcodegen generate && open OJAD.xcodeproj   # 需要 Mac
```

CI 的分工如下：

- `OJADKit` workflow：在 Linux 和 macOS 上跑包的测试。
- `iOS` workflow：每个 PR 都在 iPhone 模拟器上 build 并跑测试，不签名。
- `TestFlight` workflow：push 到 `main` 时签名并上传到 TestFlight。配置方法见 [docs/testflight-setup.md](docs/testflight-setup.md)。

## 数据来源

- OJAD：東京大学 大学院工学系研究科 峯松研究室・齋藤研究室
- 例句：Tatoeba，CC BY 2.0 FR，作者见各例句页面
- [SwiftSoup](https://github.com/scinfu/SwiftSoup)：MIT
