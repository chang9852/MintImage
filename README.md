<div align="center">

<img src="icon/icon-windows-透明背景.png" width="120" alt="MintImage" />

# MintImage

**跨平台 AI 图像生成客户端**

输入一句提示词，让 AI 为你生成图片。兼容所有 OpenAI 格式的图像 API。

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Android-5A5A5A)
![License](https://img.shields.io/badge/license-MIT-3DA639)
[![Release](https://img.shields.io/github/v/release/aiqinxuancai/MintImage?color=FF7A59)](https://github.com/aiqinxuancai/MintImage/releases)

[下载安装包](https://github.com/aiqinxuancai/MintImage/releases)

</div>

---

## ✨ 功能

- **文生图** — 输入提示词，AI 为你生成图片
- **图生图** — 上传参考图，用文字描述修改方向
- **提示词优化** — 一键润色提示词，让描述更精准
- **丰富尺寸** — 1K / 2K / 4K 多档位、8 种常用比例，或自定义任意宽高
- **批量生成** — 一次最多生成 16 张
- **收藏夹** — 把满意的结果分类整理，随时回看
- **历史记录** — 所有生成结果本地保存，离线可查
- **多配置切换** — 同时管理多个 API 地址与密钥，一键切换
- **多生图协议** — 除 OpenAI 的 Images / Responses 外，额外支持 xAI Grok Imagine
- **生图模型选择** — 首页底部可按协议在 Image 与 Grok Imagine 模型之间切换，两套选择各自独立互不影响

## 📸 截图

<img width="1266" height="713" alt="screenshot-1" src="https://github.com/user-attachments/assets/87b8b66f-17d4-4b41-a06a-e1f39936b95e" />

<img width="1266" height="713" alt="screenshot-2" src="https://github.com/user-attachments/assets/3d014dce-6c02-49b3-a5a6-55ace9591ef6" />

<img width="1266" height="713" alt="screenshot-3" src="https://github.com/user-attachments/assets/f72ea01f-1b53-41ff-94a8-981ebeddf87b" />

<img width="1266" height="713" alt="screenshot-4" src="https://github.com/user-attachments/assets/bc45353c-7e15-4564-b838-71aad375e832" />

## 🚀 快速开始

1. 从 [Releases](https://github.com/aiqinxuancai/MintImage/releases) 下载对应平台的安装包
2. 打开应用，进入设置页
3. 填写 API 地址、密钥和模型名
4. 回到主页，输入提示词，开始生成

## 🤖 Grok Imagine 接入

设置页「生图 API」下方有独立的 **添加 Grok Imagine 生图 API** 按钮，
点击后会直接新建一份配置：生图 API 预选为 `xAI Grok Imagine (/v1/images)`、
Base URL 预填 `https://api.x.ai`、模型名预填 `grok-imagine-image-2.0`，只需补上 API Key。

它和普通的 Image 配置彼此独立，各自保存自己的模型名、地址与密钥，
在首页底部的模型按钮里可以随时切换，切换其中一个不会影响另一个。

### 直连官方与走中转站的区别

该模式会按 Base URL 自动选择请求格式：

| Base URL | 请求格式 | 说明 |
| --- | --- | --- |
| `https://api.x.ai` | xAI 原生 | 发送 `aspect_ratio` 与 `resolution`，可在预设里选 13 种宽高比 |
| 其他（中转站 / 代理） | OpenAI 兼容 | 发送 `size`，并且不下发 `quality` 与 `output_format` |

中转站（例如 New API）通常只把 Grok 图像模型暴露成 OpenAI 形状的接口，
所以走中转站时需要**在尺寸里选一个具体值**（留在「自动」不会发送 `size`），
模型名也要用中转站自己的命名，可点模型名输入框右侧的云朵图标获取模型列表。

另外，Grok 只接受 `low` 与 `medium` 两档质量：应用里的「自动」会回落到
`medium`，界面也不提供 Grok 没有的「高」；2.0 之前的型号则不下发该参数。
Grok 模型不接受 `output_format`，请求会携带 `response_format: url`。

| 项目 | 取值 |
| --- | --- |
| 文生图端点 | `POST /v1/images/generations` |
| 图生图端点 | `POST /v1/images/edits` |
| 推荐模型 | `grok-imagine-image-2.0`（旗舰，支持 `quality`）；`grok-imagine-image-quality`、`grok-imagine-image`（更早的档位） |
| 宽高比 | `1:1` `16:9` `9:16` `4:3` `3:4` `3:2` `2:3` `2:1` `1:2` `19.5:9` `9:19.5` `20:9` `9:20`，或 `auto` |
| 分辨率 | `1K` / `2K` |
| 质量 | `低` / `中`（仅 2.0 支持下发；没有高清档） |
| 参考图 | 最多 3 张，单张走 `image`，多张走 `images` |

与 OpenAI 协议不同，Grok Imagine 不接受任意像素尺寸、输出格式和流式请求，
因此选择该协议后，界面会只保留宽高比与分辨率选项，并隐藏输出格式与流式开关。
4K 预设会被收敛到 2K，输出图片的落盘扩展名按服务端返回的真实图片格式推断。

## 📦 自行构建

```bash
flutter pub get
flutter run            # 调试运行
flutter build windows  # 或 macos / apk
```

推送 `v*` 形式的标签会触发 GitHub Actions 构建 Windows / macOS / Android 安装包并发布 Release。
未配置 `ANDROID_KEYSTORE_BASE64` 等签名密钥时（例如 fork 仓库），Android 会跳过签名步骤，
仍产出可安装的 APK。

---

<div align="center">

该项目已在 [LINUX DO](https://linux.do/) 社区分享。

基于 [MIT](LICENSE) 协议开源。

</div>

