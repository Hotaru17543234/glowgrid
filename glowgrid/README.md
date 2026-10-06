# 萤格 GlowGrid

一个只做三件事的 iPhone 日程清单：

- 「几点几分之前做什么」，一天 24 小时画成时间格，双指捏合缩放
- 月总览：每天一个小方格，事项变成彩色小字条，捏合放大逐级显示细节；标出日本祝日
- 每天早上推送当天的待办；中号桌面小组件可以直接打勾

完成事项时会随机说一句鼓励的话，还会飘出几颗萤火虫一样的小光点。

## 怎么编译

不需要 Mac。每次推送到 `main` 分支，GitHub Actions 会在云端 Mac 上：

1. 用 XcodeGen 根据 `project.yml` 生成 Xcode 工程
2. 编译出不签名的 App 和小组件
3. 用临时签名把 App Group 权限写进去（SideStore 需要它来让 App 和小组件共享数据）
4. 打包成 `GlowGrid.ipa`，发布到 Releases

## 怎么装到 iPhone

用 SideStore（免费 Apple ID）安装 Releases 里最新的 `GlowGrid.ipa`。
免费 Apple ID 签出来的 App 每 7 天要在 SideStore 里点一次「Refresh All」续期。

## 代码结构

- `Shared/`：App 和小组件共用的数据、日期、祝日、配色
- `App/`：日视图、月视图、编辑页、设置、早晨推送、鼓励语
- `Widget/`：中号「今日清单」小组件
