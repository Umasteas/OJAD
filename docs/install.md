# 在 iPhone 上安装（不需要电脑）

每次 `main` 有更新，GitHub Actions 都会自动构建一个**未签名**的 `OJAD.ipa`，并发布到 [Releases](https://github.com/Umasteas/OJAD/releases)。你在 iPhone 上用 Feather 或 ESign，配合自己的 `.p12` 证书和 `.mobileprovision` 描述文件重新签名，然后直接安装。整个过程不需要电脑，也不需要 Apple 开发者账号。

系统要求：iOS 17 或更高。

## 下载地址

固定下载地址，永远指向最新版：

<https://github.com/Umasteas/OJAD/releases/latest/download/OJAD.ipa>

- 在 Safari 里打开这个链接，会下载到「文件」App 的「下载」文件夹。
- Feather 和 ESign 都可以直接从 URL 导入，把这个链接粘贴进去即可。
- 历史版本在 [Releases](https://github.com/Umasteas/OJAD/releases) 页面，保留最近 10 个，标签形如 `v1.0.0-build.42`。

## 准备

- 证书文件 `xxx.p12` 和它的**密码**。
- 描述文件 `xxx.mobileprovision`。它必须和这张证书配套，并且已经包含你这台 iPhone（企业证书除外）。
- 已经装好的 Feather 或 ESign。

先把 `.p12` 和 `.mobileprovision` 存到「文件」App 里，例如「我的 iPhone」或 iCloud 云盘。

> 下面的按钮名称以常见版本为准。两款 App 更新频繁，界面可能略有不同，但流程是一样的：**导入证书 → 导入 ipa → 选证书签名 → 安装**。

## 用 Feather 安装

1. **导入证书**：打开 Feather，进入 **Certificates（证书）**，点右上角 **＋**。依次选择 `.p12` 文件和 `.mobileprovision` 文件，输入 p12 的密码后保存。
2. **导入 ipa**：进入 **Library（资源库）**，点 **＋**。可以选「从文件导入」并选中 `OJAD.ipa`，也可以选「从 URL 导入」并粘贴上面的下载地址。
3. **签名**：在资源库里点 OJAD，选择 **Sign（签名）**，选刚才导入的证书。如果需要修改 Bundle ID，在签名选项里改（见下文「Bundle ID」），然后开始签名。
4. **安装**：签名完成后点 **Install（安装）**，回到桌面等待安装完成。

## 用 ESign 安装

1. **导入证书**：打开 ESign，进入 **证书管理**（或「设置 → 证书」），导入 `.p12` 和 `.mobileprovision`，输入 p12 的密码。
2. **导入 ipa**：在「文件」App 里长按 `OJAD.ipa`，点「共享」，选择 ESign；也可以在 ESign 的「下载」里粘贴上面的下载地址。导入后，ipa 会出现在「文件」或「未签名」列表里。
3. **签名**：点 OJAD，选择 **签名**，然后选择证书。如果需要修改 Bundle ID，在签名设置里改，然后点「签名」。
4. **安装**：在「已签名」列表里点 OJAD，选择 **安装**。

## 第一次打开前

- **iOS 16 及以上，使用开发（Development）或 Ad Hoc 描述文件时**：需要打开 设置 → 隐私与安全性 → **开发者模式**。打开后会重启，开机后确认启用。
- **使用企业证书时**：打开 设置 → 通用 → **VPN 与设备管理**，找到对应的企业开发者，点「信任」。

## Bundle ID

App 自带的 Bundle ID 是 `io.github.umasteas.ojad`，显示名是「OJAD 重音」。

描述文件里写死了它允许的 App ID，签名时 Bundle ID 必须和它匹配，否则会安装失败（常见提示是「无法安装」或「无法验证完整性」）。

- 描述文件是**通配符**（例如 `ABCDE12345.*`）：任何 Bundle ID 都可以，不用修改。
- 描述文件是**指定 ID**（例如 `ABCDE12345.com.example.app`）：在签名器里把 Bundle ID 改成 `com.example.app`，也就是去掉前面的 Team ID 和点号。
- 描述文件对应的 App ID 可以在签名器的证书详情里看到。

**以后每次更新都用同一个 Bundle ID 签名。** 收藏和历史保存在这个 Bundle ID 对应的数据里。换了 Bundle ID，就会变成另一个独立的 App，原来的数据不会过去。

## 更新到新版本

1. 用上面的固定地址重新下载（或重新从 URL 导入），得到最新的 `OJAD.ipa`。
2. 用同一张证书、同一个 Bundle ID 签名后安装，会直接覆盖旧版本，收藏和历史会保留。

## 证书被吊销或过期之后

表现：点开 App 时提示「无法验证」或「不再可用」，或者打开后立刻闪退。

1. 拿到新的 `.p12` 和 `.mobileprovision`，在签名器里导入。
2. 用**新证书**、**同一个 Bundle ID** 对 `OJAD.ipa` 重新签名，然后安装覆盖。一般不需要先删除旧 App，数据也会保留。
3. 如果安装时提示无法覆盖，只能先删除旧 App 再安装。这样收藏和历史会丢失。

## 常见问题

| 现象 | 处理 |
|---|---|
| 安装进度条走完后 App 消失，或提示「无法安装」 | 描述文件不包含这台设备，或者 Bundle ID 和描述文件不匹配 |
| 签名时提示证书密码错误 | 重新输入 p12 的密码；文件名不影响 |
| 打开后提示需要开发者模式 | 见「第一次打开前」 |
| App 能打开，但查询一直失败 | 检查网络。App 需要联网访问 OJAD 和 Tatoeba，没有离线词库 |
