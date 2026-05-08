# 踩坑清单（PITFALLS — 不再犯）

> **每次写新代码、改老代码前必读。**
> 这里每一条都是真实流过血的坑，写代码时主动避开 —— 不要因为「这次不一样」而重新踩。

## 索引（按风险域分组）

- [§1 渲染管线](#1-渲染管线)
- [§2 ScreenCaptureKit](#2-screencapturekit)
- [§3 坐标系 & DPI](#3-坐标系--dpi)
- [§4 权限 & 签名](#4-权限--签名)
- [§5 SwiftUI 绑定](#5-swiftui-绑定)
- [§6 安装与版本管理](#6-安装与版本管理)
- [§7 全局热键](#7-全局热键)
- [§8 验收纪律（防"按下葫芦起了瓢"）](#8-验收纪律防按下葫芦起了瓢)
- [§9 用户体验铁律（最高优先级 · 不可妥协）](#9-用户体验铁律最高优先级--不可妥协)

---

## §1 渲染管线

### P-001 · 不要用 `CGImage.cropping(to:)` 喂给 `ctx.draw`
**症状**：zoom 倍率拉到 4×、6× 也看不出任何放大效果，圈内画面始终是整屏被压缩塞进去。
**根因**：`CGImage.cropping(to:)` 不返回独立 bitmap，返回的是引用父帧 buffer 的「cropping view」。某些 macOS / 显卡驱动版本下，把这个 view 喂给 `ctx.draw(image, in: dstRect)` 会**忽略 cropping 边界**，实际渲染整个父帧再缩放到 dstRect。
**正确做法**：
```swift
let fullCI = CIImage(cgImage: frame)
let cropped = fullCI.cropped(to: ciCropRect)
let materialized = ciContext.createCGImage(cropped, from: ciCropRect)  // 强制物化
ctx.draw(materialized, in: lensRect)
```
**反模式**：`frame.cropping(to: rect)` → `ctx.draw(view, in:)` ❌ 永远不要。

---

### P-002 · 不要在 NSView (isFlipped=false) 里手动 `scaleBy(x:1, y:-1)` 翻转 CGImage
**症状**：lens 圈内画面**上下颠倒**，桌面像照镜子一样。
**根因**：误解「CGImage top-down vs CGContext y-up 需要手动翻 Y」。实际上 AppKit 的 `ctx.draw(cgImage, in: rect)` **已经会自动正向映射** top-down CGImage 到 y-up 坐标系的 rect 上。手动再翻一次就反了。
**正确做法**：
```swift
ctx.draw(cgImage, in: rect)   // 直接画就是正的
```
**反模式**：以下组合是上下颠倒的元凶 ❌
```swift
ctx.translateBy(x: rect.minX, y: rect.maxY)
ctx.scaleBy(x: 1, y: -1)
ctx.draw(img, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
```
**触发条件**：仅在你自己创建了一个 *flipped* 的 ctx 或者从 CGBitmap 之类的 top-down ctx 拷贝时才需要 flip；NSView.draw 里的 ctx **不需要**。

---

### P-003 · `NSImage(cgImage:size:)` 不一定按 size 缩放
**症状**：放大倍率参数变了，视觉上完全不变。
**根因**：`NSImage(cgImage: cgImage, size: NSSize)` 在某些缩放场景下会**忽略 size 参数**，沿用源 CGImage 的像素尺寸。
**正确做法**：
```swift
ctx.draw(cgImage, in: dstRect)   // 让 CGContext 自己按 src→dst 比例缩放
```
**反模式**：`NSImage(cgImage:size:).draw(in:from:.zero)` ❌ 在缩放路径上不可靠。

---

### P-005 · Overlay 要允许外部录屏，但内部抓帧必须排除自己
**症状**：用户肉眼能看到高光，但 OBS / 系统录屏录不到高光层。
**根因**：`window.sharingType = .none` 会把 overlay 窗口标记为不可被屏幕共享/录制捕获。
**正确做法**：
```swift
window.sharingType = .readOnly
try await ScreenCapturer.shared.start(excludingWindowIDs: [overlayWindowID])
```
这样 OBS 能录到高光；快捷高光自己的 ScreenCaptureKit 流仍然按 window ID 排除 overlay，避免 lens 把自己录进去造成递归套娃。

---

### P-004 · CIUnsharpMask 在小 crop 上参数太弱看不见
**症状**：开启「锐化抗模糊」开关后，圈内文字看着没变化，跟没开一样。
**根因**：CIUnsharpMask 的 `radius` 参数是**绝对像素**单位。crop 区域只有 68×67 像素时，radius=1.2 = 仅占图像 1.7% 半径，肉眼几乎看不出。
**正确做法**：参数跟 zoom 走（zoom 越高、crop 越小，参数要越激进）：
```swift
f.radius    = Float(min(3.5, 1.0 + z * 0.45))  // 1.5×→1.7  6×→3.5
f.intensity = Float(min(1.2, 0.4 + z * 0.15))  // 1.5×→0.62  6×→1.2
```
**经验值**：肉眼可见的最小 unsharp 强度大约是 radius ≥ 2 + intensity ≥ 0.7 在 crop 像素 < 200 的小图上。

---

## §2 ScreenCaptureKit

### P-101 · 不要用废弃的 `CGWindowListCreateImage`
**症状**：圈内只显示桌面壁纸，不显示真实桌面应用。
**根因**：macOS 15+ 已废弃；权限缺失时**静默退化**为只返回桌面壁纸（不报错）。
**正确做法**：用 `ScreenCaptureKit` (`SCStream` + `SCContentFilter`)，60 fps 抓 IOSurface-backed CVPixelBuffer。

### P-102 · `SCDisplay.width/.height` 已经是物理像素
**症状**：zoom 视觉上算出来的倍率跟参数对不上，永远小一倍。
**根因**：`SCDisplay.width / .height` 是物理像素（不是点）。如果再 `× backingScaleFactor` 就是 4× 超采样，算出来的 scale 是真值的 2 倍，crop 像素区域也跟着翻倍 —— zoom 被这个错误的 scale 抵消。
**正确做法**：
```swift
let pointSize = NSScreen.main!.frame.size
let backingScale = NSScreen.main!.backingScaleFactor
config.width  = Int((pointSize.width  * backingScale).rounded())
config.height = Int((pointSize.height * backingScale).rounded())
```

### P-103 · SCStream 当前只抓主屏
**症状**：鼠标在副屏时 crop 出来空，画面渲染成 nil。
**正确做法**：检测 `mouseScreen.frame.origin == .zero`（主屏判定），副屏时 `capturedCGImage = nil` 跳过渲染，**不要**强行 crop 一个非主屏的区域。

---

## §3 坐标系 & DPI

### P-201 · CIImage 是左下原点，CGImage 是左上原点
**症状**：crop 区域偏移，圈内画面是错误位置的内容。
**正确做法**：CGImage cropRect → CIImage cropRect 时翻 Y：
```swift
let ciCropRect = CGRect(
    x: cgRect.minX,
    y: CGFloat(frame.height) - cgRect.maxY,   // top-down → bottom-up
    width:  cgRect.width,
    height: cgRect.height
)
```

### P-202 · `NSEvent.mouseLocation` 是全局坐标，左下原点；屏幕坐标是相对当前 NSScreen 的
**症状**：lens 跟手时位置永远偏移。
**正确做法**：转 view 内坐标时减去 `viewScreen.frame.origin`：
```swift
cursorPos = NSPoint(
    x: mouseGlobal.x - viewScreen.frame.origin.x,
    y: mouseGlobal.y - viewScreen.frame.origin.y
)
```

---

## §4 权限 & 签名

### P-301 · `codesign --sign -` ad-hoc 签名 → 每次重 build 都会重新弹权限
**症状**：每次 `bash build_app.sh` 后启动 app，TCC 都重新弹一次「屏幕录制」「辅助功能」授权框。
**根因**：ad-hoc 签名每次生成新 cdhash，TCC 数据库以为是全新 app。
**正确做法**：默认不主动请求权限，先用 `CGPreflightScreenCaptureAccess()` 做只读预检；未授权时不启动 SCStream，避免弹窗死循环。普通开源安装不要求证书：
```bash
bash build_app.sh
```
频繁本地 rebuild 的开发者可显式启用稳定本地签名：
```bash
QH_SIGNING_MODE=local bash build_app.sh
```
这个证书不能跨电脑复用，也不能提交到开源仓库；正式分发应使用 Developer ID 签名 + notarize。

### P-302 · 只保留并启动 `/Applications` 里的唯一 App
**症状**：双击桌面快捷方式弹一次权限，再双击 /Applications 又弹一次。
**正确做法**：不要复制一整份 `.app` 到桌面。每次安装时清理桌面和旧项目目录里的 `快捷高光.app`，只从 `/Applications/快捷高光.app` 启动，避免 TCC 记录多份看似同名但代码身份不同的 App。

### P-303 · 别忘了清 quarantine 属性
```bash
xattr -cr "$APP_PATH"
xattr -dr com.apple.provenance "$APP_PATH"
xattr -dr com.apple.quarantine "$APP_PATH"
```
否则跨设备/下载来的 .app 启动会被 Gatekeeper 拦截。

---

## §5 SwiftUI 绑定

### P-401 · `@State` 初值用 `ProcessInfo` 必须用闭包形式
**症状**：环境变量预选 tab 不生效，永远是默认值。
**正确做法**：
```swift
@State private var selection: Int = {
    switch ProcessInfo.processInfo.environment["QH_TAB"] {
    case "general": return 0
    case "hotkey":  return 1
    default:        return 0
    }
}()
```
不要写 `@State private var selection = ProcessInfo.processInfo.environment["QH_TAB"] == "hotkey" ? 1 : 0` —— 部分 Swift 版本会报「无法在 property initializer 内访问类型成员」。

### P-402 · `TabView` 的 `tag` 类型必须和 `selection` 完全一致
**症状**：点击 tab 没反应，或预选 tab 失败。
**正确做法**：`@State selection: Int` + `.tag(0)` `.tag(1)` `.tag(2)` 全部 Int。如果 selection 是 String 但 tag 给 Int，绑定会失效。

---

---

## §6 安装与版本管理

### P-501 · 不要让机器上同时存在多份不同 cdhash 的 .app
**症状**：曲率搜索「快捷高光」时 Spotlight 列出多个 `.app`（不同路径、可能不同版本），双击哪个？根本不知道自己测的是不是修过 bug 的那一个，导致**反复说"bug 没修"实际是验错了 binary**。
**根因**：早期 build_app.sh 把 .app 放在 `dist/` + `/Applications/` + 桌面，但当 app 改名（CursorMagnifier → 快捷高光）或迁移时，旧路径的 .app 没被主动清理，Launch Services 也没反注册，留在文件系统里被 Spotlight 索引。
**正确做法**：每次 build_app.sh 主动 sweep：
```bash
mdfind 'kMDItemFSName == "*快捷高光*"cd || kMDItemFSName == "CursorMagnifier*"cd' \
    | grep -E '\.app$' | grep -vE "(/Sources/|/.build/|/Resources/|/.git/)"
```
对每个匹配项，检查不在当前构建临时路径或 `/Applications` 就 `lsregister -u` 反注册 + `rm -rf` 删除；安装完成后默认删除 `dist/快捷高光.app`，机器上只留下 `/Applications/快捷高光.app`。
**禁止**：build 完只 `cp` 不清理 → 老路径会越堆越多。

### P-502 · App 改名后 Launch Services 注册表会留下旧条目
**症状**：旧名字的 .app 物理删除后，Launch Services 仍然记得它，Spotlight/Finder 偶尔会闪一下旧名。
**正确做法**：物理删除前先 `lsregister -u <旧路径>` 反注册。物理删除后再 `lsregister -f <新路径>` 强制刷新。

### P-503 · 多个调试 binary 路径让用户分不清测哪个
**症状**：曲率不知道用 `/Applications/快捷高光.app` 还是 `.build/release/CursorMagnifier` 还是 `dist/快捷高光.app/Contents/MacOS/CursorMagnifier`。
**正确做法**：build_app.sh 完成时用户可见入口只剩 `/Applications/快捷高光.app`。所有给曲率的启动指令必须明确指向 `/Applications/快捷高光.app/Contents/MacOS/CursorMagnifier`，不要用 `dist/` 或 `.build/`。

### P-504 · 没有版本号 / BUILD ID，肉眼无法验证跑的是不是新版
**症状**：曲率说「修复版本不生效」，实际上跑的是缓存里的老进程或老菜单栏图标，但他没法肉眼区分。
**正确做法**：在 OverlayView 里 hardcode 一个 `kBuildID` 字符串，每次重 build 改一次。诊断模式（QH_DIAG=1）下把它画在 lens 下方。曲率打开 lens **一眼**就能确认自己跑的是不是当前对话里改的版本。

---

## §7 全局热键

### P-601 · `NSEvent.addGlobalMonitorForEvents` 是被动监听器，被系统级快捷键劫持后到不了
**症状**：曲率设了 Option+F1 切形状，按下没反应；但**打开设置面板时**有时能切（因为设置内的 ChordHotkeyRecorder 在前台局部监听同样捕获了事件）。
**根因**：macOS 把 F1/F2/F3/F4 等映射成系统级亮度/键盘亮度等功能键，系统先消费，被动监听拿不到。
**正确做法**：用 Carbon `RegisterEventHotKey` API（主动注册全局热键）：
```swift
import Carbon
var hotKeyRef: EventHotKeyRef?
let hotKeyID = EventHotKeyID(signature: OSType(0x51484C54), id: 1)  // 'QHLT'
RegisterEventHotKey(UInt32(keyCode), UInt32(carbonModifiers), hotKeyID,
                    GetApplicationEventTarget(), 0, &hotKeyRef)
```
能拦截系统已分配的快捷键。**临时绕过**：让用户改用 ⌃⌥S 这种系统未占用的组合。

---

## §8 验收纪律（防"按下葫芦起了瓢"）

### P-701 · 每次发版前必须对照 FEATURES.md 跑一遍验收 SOP
**症状**：修了 zoom 不生效，但破坏了上下方向；改了上下方向，又破坏了别的功能。
**根因**：没有强制的回归清单，每次只盯眼前那个 bug，看不到其它功能也被踩坏了。
**正确做法**：[docs/FEATURES.md](FEATURES.md) 是验收锚点，**每次 commit 前对每条 F-xxx 都过一遍**。任何一条退化为 ❌ 不允许 push。

### P-702 · 不要凭代码逻辑「应该对」就声称修好
**症状**：代码看上去对，但运行时数据跟代码逻辑不符 —— 反复改反复"修好"反复 bug 复发。
**正确做法**：可疑场景必须**让数据自己说话**：
- 加屏幕可见的诊断标签（QH_DIAG=1）
- 标签里画运行时关键变量：zoom 值、crop 像素尺寸、物化后 CGImage 实际尺寸、绘制目标尺寸
- 让曲率截图 → 一眼看清「数学是否对、binary 是否新、物化是否成功」
- **数据 ✓ 才能算修好**，仅代码 review 通过不算

### P-703 · 改任何代码前必须先对照 PITFALLS.md
**症状**：每次新一轮改动，又重新触碰之前已经记录过的坑。
**正确做法**：每次准备动 `OverlayView.swift` / `ScreenCapturer.swift` / `HotkeyMonitor.swift` / `build_app.sh` 之前，**强制读一遍** [PITFALLS.md](PITFALLS.md) 索引，看看本次改动是否踩到已知坑域。

### P-704 · 不要在用户验收前自己宣称"修好了"
**症状**：阿良说「已修复」，实际曲率打开发现还是坏的，信任崩塌。
**正确做法**：阿良只能说「我改了 X，等曲率验收」，**不能**说「已修复」。验收通过 = 曲率明确说「OK」+ 至少一个回归功能也确认仍正常。

---

## §9 用户体验铁律（最高优先级 · 不可妥协）

> **2026-05-01 曲率震怒后定下的铁律。** 任何代码改动如果违反这一节，无论功能上看着多正确，都必须立刻撤回重做。

### P-901 · 抓帧失败永不阻塞用户使用
**症状**：屏幕抓帧链路失败时，曾在 lens 圈内填红底白字「✗ 屏幕未抓帧/请去系统设置勾选…」。曲率原话：「贴牛皮癣」「非常傻逼」「一点用户思维都没有」。
**根因**：开发视角把「让 fail 暴露给用户」当美德，无视用户视角——用户只想用放大镜，不想被错误警告糊脸。
**正确做法**：
- 抓帧 nil 时，lens 内部保持透明（露出真实桌面 1× 画面），donut 暗化 + ring 高光照常画。用户依然能用激活键标记鼠标位置。
- 状态提示只走菜单栏图标轻量切换：`plus.magnifyingglass`（健康）↔ `magnifyingglass`（暂时不可用）+ tooltip。
- 抓帧链路恢复后自动渲染放大画面，无需用户操作。

**反模式**（永远不要）：
- ❌ 在 lens 内部画任何错误文字 / 图标 / 红底
- ❌ 弹 NSAlert 告知「屏幕录制权限失效，请去系统设置…」
- ❌ 强制把用户引导到系统设置面板
- ❌ 用红色 / 警告色阻断用户视线

### P-902 · 权限二次失效（cdhash 漂移）不再二次打扰
**症状**：用户已经手动勾选屏幕录制权限，但 ad-hoc 重签后每次启动都被反复提示「需要授权屏幕录制」。
**根因**：ad-hoc 签名 cdhash 每次 build 都变，TCC 数据库里旧 cdhash 的授权对新 cdhash 无效，`CGPreflightScreenCaptureAccess()` 返回 false。代码盲目按 preflight 结果决定弹窗 → 反复打扰。
**正确做法**：
- 启动时绝不调用 `CGRequestScreenCaptureAccess()` —— 这函数本身会触发系统弹框。只用只读的 `CGPreflightScreenCaptureAccess()` 检测。
- preflight false 时直接跳过 SCStream，lens 内部透明，只画 donut + ring。
- 自动重试前再次 preflight；如果当前身份仍未授权，停止重试，避免系统反复弹窗。

### P-903 · Zoom 看似不生效时先确认有没有屏幕帧
**症状**：高光圈能出现，倍率标签也显示 `2.0×`，但圈里没有真实放大画面。
**根因**：当前 app 身份未通过屏幕录制预检，`latestFrame == nil`。没有屏幕帧时，Zoom 数学没有“原材料”可放大，只能显示透明 lens + donut/ring。
**正确做法**：preflight false 时启动只读权限轮询，不启动 SCStream；一旦用户在系统设置中给当前 `/Applications/快捷高光.app` 授权，自动重连抓帧，无需重启。
**反模式**：把这种状态误判成 crop/scale 公式错误，然后继续改 `OverlayView` 的几何数学。

### P-904 · 菜单栏 App 必须显式拒绝「最后窗口关闭即退出」
**症状**：APP 用着用着自动退出，尤其是关掉设置窗口之后。
**根因**：macOS 默认 `applicationShouldTerminateAfterLastWindowClosed` 返回 true。菜单栏类型 App 关掉设置窗口（唯一可见 NSWindow）就会触发自杀。
**正确做法**：
```swift
func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
}
```

### P-904 · SCStream 异常停止必须静默自愈
**症状**：APP 用一段时间后放大镜失灵，但进程没退出。
**根因**：`SCStreamDelegate.stream(_:didStopWithError:)` 留空，TCC 抖动 / 屏幕拓扑变化 / 系统 idle 等触发系统级 stop 后，stream 实例就废了，再也不恢复。
**正确做法**：
- `didStopWithError` 必须清理状态 + 通知调度层。
- 调度层（AppDelegate）做指数退避静默重启：1s → 2s → 4s → … 30s 封顶。
- 整个过程不弹窗、不通知中心打扰，只 NSLog + 菜单栏图标轻提示。

### P-905 · 默认状态下不展示任何调试 UI
**症状**：发布版用户在 lens 下方看到一堆 `BUILD vN-xxx / zoom=N× / crop=N×N px` 调试文字。
**根因**：开发期为方便排错把诊断模式默认开启，发布前忘记切回。
**正确做法**：
- 诊断 / 调试类 UI 默认 OFF。开发期通过环境变量 opt-in（`QH_DIAG=1`）。
- 任何「让我看到内部状态」的 UI 元素都得问一句：用户在终端产品里看到这个会爽吗？

### 灵魂检查（每次合 PR 前过一遍）
- [ ] 失败状态有没有阻塞用户使用？
- [ ] 有没有任何弹窗在告诉用户「你需要去做什么」？（除非真的是首次授权引导）
- [ ] 用户已经授权过的权限会不会被二次打扰？
- [ ] APP 用得久了会不会自己退出？
- [ ] 异常状态会不会自愈？还是要用户重启 APP 才好？
- [ ] 有没有任何调试文字 / 红色色块 / 警告图标默认开启？

> **任何一项不过，回去改完再来。这一节比 §1~§8 任何一条都更优先。**

---

## SOP：写代码前的自检清单

每次准备改 `OverlayView.swift` / `ScreenCapturer.swift` / `build_app.sh` 之前，对照过一遍：

- [ ] 即将动的代码区是否在本文档某条 PITFALL 范围内？
- [ ] 我有没有打算重新引入手动 Y 翻转？（看到 `scaleBy(x:1, y:-1)` 警觉）
- [ ] 我有没有打算用 `CGImage.cropping(to:)` 直接喂渲染？
- [ ] 改完后 zoom 数学是否还能通过：`captureSize_pt = lensSize_pt / zoom`?
- [ ] 改完后是否还能通过 [FEATURES.md](FEATURES.md) 全部 ✅ 项？

**任何一条没过，停下来想清楚再写。**
