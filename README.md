# 昆曲工尺定调器

一款轻量、离线的昆曲工尺谱定调工具，支持浏览器直接使用，并提供极简原生 WebView 封装的 Android APK 构建脚本。

## 功能特性

- **七调门切换**：支持上字调、尺字调、小工调、凡字调、六字调、正宫调、乙字调，自动对应十二平均律音名与频率。
- **三音区与工尺七音**：支持低音区、中音区、高音区切换，覆盖「上、尺、工、凡、六、五、乙」七个工尺音。
- **按住即响**：基于 Web Audio API 实时合成音频，按住「发音」键持续发声，松开即停。
- **声音与音高微调**：支持笛音（泛音合成）与纯音（正弦波）两种音色，提供 `-50` 至 `+50` 音分整体微调与音量调节。
- **简繁一键切换**：顶栏右上角提供圆形语言切换按钮，支持简体中文与繁體中文实时切换。
- **本地设置记忆**：调门、音区、语言、音色、微调与音量自动保存在当前设备本地存储中，完全离线可用。

## 目录结构

```text
gongche_tuner/
├── kunqu_gongche_tuner.html    # 单文件 Web 定调器源码
├── kunqu-gongche-tuner.apk     # 本地构建生成的 Android 安装包（默认不纳入 Git）
├── android/                    # 极简原生 WebView Android 工程
│   ├── AndroidManifest.xml
│   ├── build_apk.ps1           # 一键编译、签名、安装与启动脚本
│   ├── src/com/kunqu/gongchetuner/MainActivity.java
│   └── res/                    # 应用名称、主题样式与桌面图标资源
├── .gitignore
├── LICENSE
└── README.md
```

## 使用方式

### 1. 浏览器直接使用

直接在电脑或手机浏览器中打开 `kunqu_gongche_tuner.html` 即可离线使用，无需安装任何依赖。

### 2. 本地构建 Android APK

构建脚本直接调用本机 Android SDK 工具链（`aapt2`、`javac`、`d8`、`zipalign`、`apksigner`），无需 Gradle 依赖，约数秒即可完成打包。

**环境要求**：

- Windows PowerShell
- Android SDK（含 `platforms` 与 `build-tools`）
- JDK 11 及以上（脚本可自动检测 Android Studio 内置的 `jbr`）

**构建命令**：

```powershell
# 仅构建 APK（输出到项目根目录 kunqu-gongche-tuner.apk）
powershell -ExecutionPolicy Bypass -File android\build_apk.ps1

# 构建并通过 ADB 安装到已连接的 Android 手机后自动启动
powershell -ExecutionPolicy Bypass -File android\build_apk.ps1 -Install -Launch
```

> 说明：脚本每次构建都会自动将根目录最新的 `kunqu_gongche_tuner.html` 打包进 APK，无需手动同步网页源码。

## 音高参考说明

- 音高计算依据 DB3205/T 1172—2025《苏式传统文化 昆曲清唱艺术传承指南》附录 B，采用十二平均律作为参考。
- 传统昆笛的实际音高会因笛管、师承与演唱习惯略有差异，可通过界面中的「整体微调」按需校准。
- 本工具仅作日常拍曲定调参考，不替代老师的笛色、腔格与口传心授。

## 开源协议

本项目采用 [MIT License](LICENSE) 开源。
