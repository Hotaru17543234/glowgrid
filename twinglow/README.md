# 双萤 TwinGlow

一个 App 里同时登录好几个网站账号（默认是 Muse 的两个号）。两只萤火虫，一只一个号 ✨

- 每个账号有自己独立的网页数据（登录状态、Cookie、缓存），互不干扰
- 顶部的小胶囊点一下就切换账号；切走的号留在后台，切回来页面还在原处
- 底部：后退、前进、回到主页、刷新、在 Safari 打开；下拉也能刷新
- 账号可以改名字、换颜色、改主页、添加、排序、退出登录、删除
- 网页弹出的登录小窗口、提示框都能正常显示

## 原理

iOS 17 起，`WKWebsiteDataStore(forIdentifier:)` 可以给一个 App 建多份互相独立、会保存到手机上的网页数据。
双萤给每个账号用账号自己的 UUID 建一份，所以 A 号和 B 号就像在两台不同的浏览器里登录。

## 怎么编译

不需要 Mac。`twinglow/` 文件夹有改动并推送到 `main` 时，`.github/workflows/twinglow.yml` 会在云端 Mac 上：

1. 用 XcodeGen 根据 `project.yml` 生成 Xcode 工程
2. 编译出不签名的 App
3. 打包成 `TwinGlow.ipa`，发布到 Releases（标题是「双萤 第 N 版」）

萤格（`glowgrid/`）用的是另一个工作流，两边互不影响。

## 怎么装到 iPhone

用 SideStore（免费 Apple ID）安装 Releases 里最新的 `TwinGlow.ipa`。
免费 Apple ID 签出来的 App 每 7 天要在 SideStore 里点一次「Refresh All」续期。

## 小提醒

- 这是网页版，收不到 App 的推送通知
- 登录时尽量用邮箱或手机号验证码；有的网站不允许在 App 内嵌的网页里用 Facebook 登录
- 「退出登录」和「删除这个号」只影响双萤里的数据，网站上的账号本身不会被删除

## 代码结构

- `App/AccountStore.swift`：账号列表、保存、每个账号一个网页
- `App/WebTab.swift`：单个账号的网页，处理弹窗、提示框、加载出错
- `App/RootView.swift`：账号切换栏、网页、底部工具栏
- `App/AccountManagerView.swift`：账号管理页
