# TestFlight 配置（只需做一次，全程可以用手机完成）

完成下面 5 步后，每次 push 到 `main`，GitHub Actions 都会自动构建、签名，并上传到 TestFlight。4 个 secret 还没配齐时，`TestFlight` workflow 会直接跳过，不会报错。

> 提示：Apple 开发者网站和 App Store Connect 在手机 Safari 上偶尔会排版错乱。遇到这种情况，点地址栏左侧的「大小」按钮，选「请求桌面网站」即可。

## 1. 注册 Bundle ID

1. 打开 <https://developer.apple.com/account/resources/identifiers/add/bundleId>，用付费开发者账号登录。
2. 选择 **App IDs**，点 Continue，再选 **App**，点 Continue。
3. Description 填 `OJAD`；Bundle ID 选 **Explicit**，填 `io.github.umasteas.ojad`。
4. Capabilities 一项都不用勾。点 Continue，再点 Register。

## 2. 在 App Store Connect 创建 App 记录

1. 打开 <https://appstoreconnect.apple.com/apps>，点左上角的 **＋**，选 **新建 App**。
2. 按下面填写：
   - 平台：**iOS**
   - 名称：例如 `OJAD 重音 个人版`。这个名称要求在整个 App Store 里唯一，被占用时换一个即可。手机上显示的名字仍然是「OJAD 重音」。
   - 主要语言：**简体中文**
   - 套装 ID：选 `io.github.umasteas.ojad`（第 1 步注册的那个）
   - SKU：`ojad-personal`（只给自己看，随便填）
   - 用户访问权限：**完全访问**
3. 点「创建」。这个 App 只用于 TestFlight，不需要提交审核，也不需要截图。

## 3. 创建 App Store Connect API 密钥

1. 打开 <https://appstoreconnect.apple.com/access/integrations/api>（用户和访问 → 集成 → App Store Connect API → **团队密钥**）。第一次使用时需要先点「请求访问」，只有账户持有人能操作。
2. 点 **＋／生成 API 密钥**：
   - 名称：`GitHub Actions`
   - 访问权限：**管理（Admin）**。CI 用的是 Apple 云端管理的分发证书，只有 Admin 权限能用它签名。
3. 生成后记下页面上的两个值：
   - **密钥 ID**（10 位，例如 `ABC123DEFG`）：用作 `ASC_KEY_ID`
   - **Issuer ID**（页面上方的 UUID）：用作 `ASC_ISSUER_ID`
4. 点「下载 API 密钥」，得到 `AuthKey_XXXXXXXXXX.p8`。**这个文件只能下载一次**，请保存好。

**在 iPhone 上拿到 .p8 的文本内容**：打开「文件」App，找到「下载」里的 `AuthKey_….p8`，长按选「重新命名」，把扩展名改成 `.txt`。然后点开文件，全选并拷贝。拷贝的内容应该以 `-----BEGIN PRIVATE KEY-----` 开头、以 `-----END PRIVATE KEY-----` 结尾，这就是 `ASC_KEY_P8`。

## 4. 查找 Team ID

打开 <https://developer.apple.com/account>，在「会员资格详细信息（Membership details）」里找到 **团队 ID（Team ID）**（10 位），用作 `APPLE_TEAM_ID`。

## 5. 在 GitHub 添加 4 个 secret

打开 <https://github.com/Umasteas/OJAD/settings/secrets/actions>，点 **New repository secret**，逐个添加下面 4 个：

| Name | Secret |
|---|---|
| `ASC_KEY_ID` | 第 3 步的密钥 ID |
| `ASC_ISSUER_ID` | 第 3 步的 Issuer ID |
| `ASC_KEY_P8` | 第 3 步拷贝的 .p8 全文（包括 BEGIN 和 END 两行）。也可以填它的 base64 |
| `APPLE_TEAM_ID` | 第 4 步的 Team ID |

（可选）如果以后想换 Bundle ID，到 Settings → Secrets and variables → Actions → **Variables** 里添加 `BUNDLE_ID` 即可，不需要改代码。

## 触发构建并安装

1. 打开 <https://github.com/Umasteas/OJAD/actions/workflows/testflight.yml>，点 **Run workflow**；或者 push 一次到 `main`，也会触发。整个过程大约 10–15 分钟。
2. 上传成功后，Apple 还要处理 5–30 分钟。处理完会出现在 App Store Connect → 你的 App → **TestFlight**。
3. 在 TestFlight 页面的「内部测试」里新建一个群组，把自己加进去，并打开「自动分发」。之后每个新 build 都会自动推送给你。
4. iPhone 上安装 Apple 的 **TestFlight** App，用同一个 Apple ID 登录，就能安装「OJAD 重音」。

TestFlight 的每个 build 有效期是 90 天。只要 `main` 有更新，就会自动产生新 build。

## 常见失败原因

| Actions 日志里的报错 | 处理 |
|---|---|
| `No suitable application records were found` | 第 2 步的 App 记录还没建，或者套装 ID 选错了 |
| `Cloud signing permission error` 或证书相关错误 | API 密钥的访问权限不是「管理（Admin）」，重新生成一个 |
| `ASC_KEY_P8 is not a .p8 private key` | secret 里缺了 BEGIN/END 行，或者拷贝时被截断了 |
| `The bundle version must be higher` | build 号重复了；重新运行一次 workflow 即可（build 号 = 运行序号 × 10 + 重试次数） |
