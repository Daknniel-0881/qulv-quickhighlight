# 快捷高光 (QuickHighlight)

> 录屏 / 演讲 / 远程协作场景下，按住一个键即可让鼠标周围浮起一个放大圈，圈外暗化，圈内高亮放大画面细节。

一个轻量的跨平台屏幕局部放大工具——让观众一眼看清你正在操作的位置。macOS 版基于 ScreenCaptureKit 60 fps 抓帧 + AppKit 渲染；Windows 版基于 Windows.Graphics.Capture + WPF 透明 overlay。

![放大镜设置](screenshots/03_settings_magnifier.png)

---

## ✨ 功能一览

### 核心交互
- 🔍 **按住激活**：默认按住「左 Option」，鼠标周围浮现放大圈，松开即消失
- 🎯 **跟手居中**：60 fps 实时跟随鼠标，无延迟
- ◯ **两种形状**：圆形 / 圆角矩形，圆角矩形宽高独立调节
- ⌨️ **全局组合键秒切形状**：自定义快捷键（如 ⌃⌥S）随时切换圆形⇄矩形，不用打开设置
- 📹 **OBS 可录制**：高光 overlay 对外部录屏软件可见，但内部抓帧仍排除自身，避免递归套娃
- 🚀 **菜单栏常驻**：低存在感，不抢 Dock 位置

### 画面控制
- 🔬 **放大倍率 1.0× ~ 6.0×**（默认 1.5×，0.1 步进）
- 📏 **尺寸滑块**：圆形半径 50–400 px / 矩形宽 100–800 px / 矩形高 30–600 px
- 🌑 **外圈暗化**：0% – 90% 可调，强化视觉聚焦
- ⚪ **白色高光圆环**：可开关，让放大圈的边界更清晰
- ✨ **抗模糊锐化**：CIUnsharpMask 锐化，仅 zoom > 1.0× 时生效，让文字边缘更清晰
- 🔢 **当前倍率小标识**：放大圈下方显示 `1.5×` / `4.0×` 实时倍率（录屏时建议关闭）

### 可调试性
- 🪞 **实时预览**：设置面板内嵌预览框，拖滑块时即时看到形状/暗度/倍率效果
- 🎬 **持续预览模式**：开启后放大圈一直显示，可一边拖滑块一边在真实窗口对比
- ⚡ **瞬时测试 (1.5s)**：在当前鼠标位置闪现放大圈 1.5 秒，验证参数

### 系统集成
- 🎬 **开机自启**：可选，由 `SMAppService` 管理
- 🔐 **无证书默认安装**：默认不要求本地证书；频繁开发 rebuild 时可选 `QH_SIGNING_MODE=local`
- 🧹 **单一安装副本**：只保留 `/Applications/快捷高光.app`，避免桌面/`dist` 副本造成授权身份错位
- 📍 **多显示器感知**：副屏暂不放大（SCStream 当前仅抓主屏），不会出错或卡死
- 🪟 **Windows 端口**：WPF/.NET 8 托盘应用，使用 Windows.Graphics.Capture，失败时同样不弹窗、不画错误文字、静默恢复

---

## 📸 界面预览

### 通用设置（开机自启 / 高光圆环）
![通用设置](screenshots/01_settings_general.png)

### 快捷键设置（激活键 / 切换形状组合键）
![快捷键设置](screenshots/02_settings_hotkey.png)

### 放大镜参数（形状 / 尺寸 / 倍率 / 暗度 / 锐化）
![放大镜设置](screenshots/03_settings_magnifier.png)

---

## 🚀 安装

### 自己 Build（推荐）

要求：**macOS 14+** + Xcode Command Line Tools (`xcode-select --install`)

```bash
git clone https://github.com/Daknniel-0881/quickhighlight.git
cd quickhighlight
bash build_app.sh
```

`build_app.sh` 一键完成：
1. `swift build -c release` 编译
2. 用 `generate_icon.swift` 生成图标 `.icns`
3. 打包成 `dist/快捷高光.app`
4. 默认使用无需证书的 ad-hoc 签名（可选 `QH_SIGNING_MODE=local` 稳定本地签名）
5. 安装到 `/Applications/快捷高光.app`
6. 清理桌面和 `dist/` 临时副本，避免误启动另一个代码身份
7. 重新注册到 Launch Services 刷图标缓存
8. 关闭旧实例，准备启动新版本

### 首次运行

从【应用程序】里启动【快捷高光】，菜单栏会出现 🔍 图标。不要从 `dist/` 或桌面旧副本启动，否则 macOS 可能把它当成另一份 App。

首次运行需授权两项系统权限：

| 权限 | 用途 | 路径 |
|---|---|---|
| **辅助功能** | 监听全局热键（按住激活、组合键切换形状）| 系统设置 → 隐私与安全性 → 辅助功能 |
| **屏幕录制** | 抓主屏画面给放大圈显示 | 系统设置 → 隐私与安全性 → 屏幕录制 |

> macOS 的屏幕录制授权和 App 代码身份绑定。默认安装不需要证书，但每次 rebuild 后系统仍可能把新二进制当成另一个 App。快捷高光不会反复弹权限窗；如果抓帧权限未被当前 `/Applications/快捷高光.app` 身份识别，放大圈会先透明高光，需要在系统设置里把这一份 App 加回权限列表。

### 权限与签名 FAQ

**放大倍率需要签名吗？**

不需要。Zoom 的实现只是：从屏幕帧里裁一块更小的区域（`lensSize / zoom`），再拉伸画回 lens。签名不参与这个数学。

**那为什么还需要“录屏与系统录音”权限？**

因为圈内要显示“真实屏幕内容”的放大画面，App 必须读取屏幕像素。macOS 把这类能力统一放在“录屏与系统录音”权限里；快捷高光不录音，但系统 UI 会这么命名。

**签名的意义是什么？可以删掉吗？**

可以。签名/证书不是 Zoom 功能的技术前提。仓库默认不要求证书，只做无需证书的 ad-hoc 安装；代码会在未授权时静默降级，不会反复触发系统权限弹窗。

代价是：频繁 rebuild 时，macOS 仍可能因为二进制身份变化而不认旧授权。此时不是 Zoom 数学坏了，而是当前 `/Applications/快捷高光.app` 没有拿到屏幕像素。开发者如果想让同一台 Mac 上的 rebuild 更稳定，可以显式使用 `QH_SIGNING_MODE=local bash build_app.sh`。

**开源用户在自己的 Mac 上怎么办？**

本地自签证书不能跨电脑复用，仓库也不会携带任何人的私钥。每个自己 build 的用户有两条路：

1. 普通使用：运行 `bash build_app.sh`，安装后给 `/Applications/快捷高光.app` 授权一次。
2. 频繁开发：运行 `QH_SIGNING_MODE=local bash build_app.sh`，在自己的 Mac 上生成并复用 `QuickHighlightLocalSigner`。

如果未来发布正式二进制，最好使用 Apple Developer ID 签名并 notarize。那样所有用户下载同一个发布包时，代码身份对升级更稳定。

**反复弹“录屏与系统录音”怎么办？**

1. 退出快捷高光。
2. 删除桌面、`dist/`、旧项目目录里的 `快捷高光.app`，只保留 `/Applications/快捷高光.app`。
3. 在系统设置 → 隐私与安全性 → 录屏与系统录音里，移除旧的“快捷高光”条目，再把 `/Applications/快捷高光.app` 加回来并打开。
4. 只从【应用程序】启动，不要启动桌面副本或仓库 `dist` 副本。

**放大倍率调了，但看起来没放大？**

先看菜单栏图标：如果图标是灰的，说明当前 App 没有拿到屏幕帧。此时不是 Zoom 数学失效，而是放大镜里没有“原材料”可以放大，只能画透明高光圈。快捷高光会静默轮询只读权限状态；你把 `/Applications/快捷高光.app` 加回录屏权限后，它会自动恢复抓帧，不需要重启，也不会反复弹系统授权窗。

---

## 🎮 用法

### 默认热键

| 操作 | 快捷键 |
|---|---|
| 激活放大镜 | 按住 **左 Option (⌥)** |
| 切换形状 | 默认未设置（建议设为 ⌃⌥S）|
| 打开偏好设置 | 菜单栏 🔍 → 偏好设置 |

### 自定义快捷键

打开偏好设置 → **快捷键** Tab：

- **激活放大镜**：点击输入框 → 按一下你要的修饰键（⌥ / ⇧ / ⌃ / ⌘ / Fn）→ 完成。**仅支持单个修饰键**（按住-放开式交互）
- **切换形状**：点击输入框 → 按下组合键（必须含修饰键，如 ⌃⌥S）→ 完成。每次按下立即在圆形⇄圆角矩形之间切换

### 调参流程（推荐）

1. 打开偏好设置 → **放大镜** Tab
2. 看上方「实时预览」框，先选好形状
3. 拖动尺寸/倍率/暗度滑块，每一帧都自动保存
4. 点「**持续预览**」按钮 → 放大圈在真实桌面上长亮
5. 把鼠标移到任意窗口，继续拖滑块 → 实时对比真实效果
6. 满意后再点一次按钮关闭持续预览

### 录屏建议参数

- **屏幕录制教学**：圆角矩形 360×220 / 倍率 1.5× / 暗度 60% / 关闭倍率标签
- **代码细节展示**：圆形半径 100 / 倍率 2.5× / 暗度 70% / 开启锐化
- **远程会议指引**：圆形半径 150 / 倍率 1.3× / 暗度 40% / 开启高光环

---

## 🏗 项目结构

```
Sources/CursorMagnifier/
├── main.swift               # NSApplication 入口（.accessory 模式不抢 Dock）
├── AppDelegate.swift        # 菜单栏 + 设置窗口 + 总指挥
├── CaptureRecoveryPolicy.swift # 抓帧权限/帧恢复策略（不弹窗，静默轮询）
├── HotkeyMonitor.swift      # IOKit 设备掩码 + 组合键 keyDown 监听
├── HotkeyRecorder.swift     # SwiftUI 录入式快捷键控件
├── KeyDisplay.swift         # keyCode → "⌃⌥S" 文字渲染
├── ScreenCapturer.swift     # SCStream 60 fps 抓帧（@MainActor）
├── OverlayWindow.swift      # 透明全屏窗口（不抢焦点 / 不挡点击）
├── OverlayView.swift        # 暗化挖洞 + crop + 缩放绘制 + CIUnsharpMask 锐化
├── SettingsStore.swift      # UserDefaults + @Published + 版本迁移
├── SettingsView.swift       # SwiftUI 三 Tab 设置面板 + 实时预览 Canvas
└── LaunchAtLogin.swift      # SMAppService 开机自启

quickhighlight-win/
├── QuickHighlight/Capture/  # Windows.Graphics.Capture + D3D11 frame pool
├── QuickHighlight/Overlay/  # WPF click-through overlay + crop/zoom 绘制
├── QuickHighlight/Hotkeys/  # 全局激活键 + 形状切换组合键
├── QuickHighlight/Settings/ # WPF 设置页 + JSON 设置存储
└── build.ps1                # self-contained single-file win-x64 打包
```

---

## 🔬 技术要点

### 为什么不用 `CGWindowListCreateImage`

macOS 15+ 已废弃，且**权限缺失时会静默退化为只返回桌面壁纸**（不报错）—— 这是网上很多老项目「圈内只显示桌面」的真凶。本项目用 `ScreenCaptureKit (SCStream)` 持续抓主屏帧，60 fps、IOSurface-backed `CVPixelBuffer`，性能与正确性兼得。

### 为什么 zoom 必须算 backingScaleFactor

`SCDisplay.width / .height` 已经是物理像素（不是点）。如果直接 `config.width = display.width × 2` 会变成 4× 超采样，导致 `frame.width / pointSize.width` 算出 4.0 而不是 backing scale 真值 2.0，crop 像素区域是预期 2 倍 —— **zoom 参数被这个错误的 scale 视觉化抵消掉**。正确做法：

```swift
let pointSize = NSScreen.main!.frame.size
let backingScale = NSScreen.main!.backingScaleFactor
config.width = Int((pointSize.width * backingScale).rounded())
config.height = Int((pointSize.height * backingScale).rounded())
```

### 关键 bug 修复：`CGImage.cropping(to:)` 是「父帧 buffer 的窗口视图」

> 这是本项目最难调的一个 bug。表象：把 zoom 拉到 4×、6× 也看不出任何放大效果。

`CGImage.cropping(to: rect)` **不返回独立 bitmap**，而是返回一个引用父帧的「cropping view」。在某些 macOS / 显卡驱动版本上，把这个 view 喂给 `ctx.draw(image, in: dstRect)` 时，CG 渲染管线会忽略 cropping view 的边界，**实际渲染整个父帧再缩放到 dstRect** —— 用户自始至终看到的都是 1920×1080 整屏被强行塞进放大圈，倍率信息完全丢失。

**修复方案**：用 `CIImage` + `CIContext.createCGImage(_:from:)` 强制物化成独立的 standalone bitmap：

```swift
let fullCI = CIImage(cgImage: frame)
// 注意 CIImage 用左下原点，CGImage cropRect 是左上原点，需要翻 Y
let ciCropRect = CGRect(
    x: cropRect.minX,
    y: CGFloat(frame.height) - cropRect.maxY,
    width: cropRect.width,
    height: cropRect.height
)
let processedCI = fullCI.cropped(to: ciCropRect)

// CIUnsharpMask 抗模糊（zoom > 1.05 时生效）
if SettingsStore.shared.sharpenEnabled, zoom > 1.05 {
    let f = CIFilter.unsharpMask()
    f.inputImage = processedCI
    f.radius = 1.2
    f.intensity = 0.5
    if let out = f.outputImage { processedCI = out }
}

// createCGImage 是关键 —— 强制物化成自洽 bitmap，彻底解耦父帧
let materialized = sharpenCIContext.createCGImage(processedCI, from: ciCropRect)
```

然后绘制时不要再手动翻转，直接让 AppKit 的 `CGContext` 把独立小图拉伸到 lens 几何区域：

```swift
ctx.draw(img, in: circleRect)
```

### 设备级 mask 区分左右修饰键

`NSEvent.ModifierFlags.option` 不区分左右键。但 `event.modifierFlags.rawValue` 包含 IOKit device-side bits（`kIOHIDKeyboardModifierMaskLeft*`），按位与即可：

```swift
.leftOption.deviceMask  = 0x000020
.rightOption.deviceMask = 0x000040
.fn.deviceMask          = 0x800000
```

### 全局组合键监听

用 `NSEvent.addGlobalMonitorForEvents(.keyDown)` + `addLocalMonitorForEvents` 双管齐下：global 接其他 app 内的按键，local 接自家窗口的按键并能消费事件（避免误触表单）。已授权辅助功能即可工作，**不需要额外授权 Input Monitoring**。

### 签名模式（默认不需要证书）

默认安装不需要证书：

```bash
bash build_app.sh
```

如果你在同一台 Mac 上频繁 rebuild，想尽量减少 TCC 因 cdhash 变化而不认旧授权，可以选择本地稳定签名：

```bash
QH_SIGNING_MODE=local bash build_app.sh
```

`QuickHighlightLocalSigner` 只属于当前 Mac，不能提交到仓库，也不能替其他电脑解决权限。正式分发仍建议 Apple Developer ID 签名并 notarize。

### Windows 版本

Windows WPF/.NET 8 端口位于 `quickhighlight-win/QuickHighlight/`：

- 使用 `Windows.Graphics.Capture` + D3D11 frame pool 持续抓主屏。
- 使用透明置顶 WPF overlay，`WS_EX_TRANSPARENT` 鼠标穿透。
- 默认按住 `LeftAlt` 显示高光，`Ctrl+Alt+S` 全局切换圆形 / 圆角矩形。
- 抓帧失败时不弹窗、不在 lens 内画错误文字，托盘轻提示；连续失败后低频探测，恢复后自动接上。
- 收到第一帧后才标记抓帧健康，避免“托盘显示正常但 Zoom 没画面”的误判。
- 高 DPI 下用物理像素计算 crop，再按 WPF DPI 绘制，125%/150% 缩放时倍率仍对齐。

Windows 构建：

```powershell
cd quickhighlight-win
.\build.ps1
```

输出：`quickhighlight-win/artifacts/QuickHighlight-win-x64.zip`

---

## 🪟 Windows 移植思路

如果你想在 Windows 上做同样的工具，技术栈对照：

| macOS | Windows | 说明 |
|---|---|---|
| ScreenCaptureKit (SCStream) | **Windows.Graphics.Capture** (UWP) 或 DXGI Desktop Duplication API | 推荐 Graphics.Capture，权限模型干净 |
| NSWindow level=.screenSaver | **Win32 layered window** + `WS_EX_TOPMOST` + `WS_EX_TRANSPARENT` | 透明覆盖层，鼠标事件穿透 |
| NSEvent.addGlobalMonitorForEvents | **`SetWindowsHookEx(WH_KEYBOARD_LL)`** + `WH_MOUSE_LL` 低级钩子 | 全局键盘监听 |
| AXIsProcessTrusted | 不需要 | Windows 没有等价"辅助功能"权限闸门 |
| SMAppService | **任务计划程序 / 注册表 Run 键** | 开机自启 |
| SwiftUI Settings | **WPF / WinUI 3** | 推荐 WinUI 3 + C#，原生 Fluent Design |
| AppKit drawing | **Direct2D / Skia** | 60 fps 圆形 clip + 缩放绘制 |
| CIUnsharpMask | **Direct2D Effects: D2D1_UNSHARP_MASK** | 抗模糊锐化 |

**关键复杂点**：
1. **DPI 适配**：Windows 多显示器各自 DPI scale，比 macOS 的 backingScaleFactor 更复杂
2. **DRM 内容**：Netflix / 部分流媒体在 Windows 上抓帧会变黑，需要降级
3. **多桌面 (Virtual Desktop)**：覆盖窗口要正确处理切换桌面的可见性
4. **HiDPI 鼠标坐标**：`GetCursorPos` 返回逻辑像素，与 Capture API 拿到的物理像素需要换算

当前仓库已经包含 WPF/.NET 8 Windows 端口；上表保留为后续优化参考。

---

## 🛠 开发

```bash
swift build                      # debug build
swift build -c release           # release build
bash build_app.sh                # 完整流程：编译 → ad-hoc 安装 → 装 /Applications → 清理旧副本
```

调试时直接跑 `.build/debug/CursorMagnifier`，菜单栏图标会出现，但你需要先给这个 debug binary 单独授一次屏幕录制权限。

### 调试用环境变量

| 变量 | 值 | 用途 |
|---|---|---|
| `QH_OPEN_SETTINGS` | `1` | 启动后立即打开设置面板（用于截图） |
| `QH_TAB` | `general` / `hotkey` / `magnifier` | 设置面板预选 tab |

```bash
QH_OPEN_SETTINGS=1 QH_TAB=magnifier ./.build/release/CursorMagnifier
```

---

## 📝 License

[MIT](LICENSE) © 2026 Daknniel-0881
