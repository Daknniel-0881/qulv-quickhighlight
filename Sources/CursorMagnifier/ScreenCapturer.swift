import Cocoa
import ScreenCaptureKit
import CoreVideo
import CoreImage

/// 用 ScreenCaptureKit 持续抓主屏帧。CGWindowListCreateImage 在 macOS 15+ 已废弃，
/// 权限缺失时只返回桌面壁纸 —— 这是"只显示桌面"问题的根因。
@MainActor
final class ScreenCapturer: NSObject {
    static let shared = ScreenCapturer()

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "com.curvature.cursormagnifier.capture", qos: .userInteractive)

    /// 最新一帧 CGImage（含整个主屏内容）。OverlayView crop 后绘制。
    /// 读写都在 @MainActor 上，不需要锁。
    private(set) var latestFrame: CGImage?

    /// 主屏物理像素尺寸 — crop 时换算 backingScaleFactor 用
    private(set) var displayPixelSize: CGSize = .zero
    /// 主屏点尺寸（NSScreen.frame）
    private(set) var displayPointSize: CGSize = .zero

    /// SCStream 意外停止时的回调（系统 stop / 错误）。
    /// AppDelegate 用来调度静默重启 + 切换菜单栏图标，不打扰用户。
    var onStreamStopped: ((Error?) -> Void)?

    /// 启动 stream。excludingWindowIDs 用于排除 overlay 自身（不然会拍到自己造成无限放大）。
    func start(excludingWindowIDs: [CGWindowID]) async throws {
        if stream != nil { return }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        )

        // 选主屏（含原点的那个）
        guard let display = content.displays.first(where: { $0.frame.origin == .zero })
                ?? content.displays.first else {
            throw NSError(
                domain: "ScreenCapturer", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "未找到可用显示器"]
            )
        }

        // 排除自己的覆盖窗口。
        //
        // 注意：overlay 默认是隐藏的，按住热键才 orderFront。如果这里用
        // onScreenWindowsOnly=true，SCShareableContent 启动时看不到这个隐藏窗口，
        // excluded 会变成空数组；配合 window.sharingType=.readOnly 后，我们自己的
        // 抓帧就会拍到 overlay 本身，形成递归，用户体感就是 zoom 又“失效”了。
        let excluded = content.windows.filter { excludingWindowIDs.contains(CGWindowID($0.windowID)) }

        let filter: SCContentFilter
        if !excluded.isEmpty {
            filter = SCContentFilter(display: display, excludingWindows: excluded)
        } else if let currentApp = content.applications.first(where: {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }) {
            // 兜底：如果系统没有把隐藏 overlay 窗口列出来，就排除整个当前 App。
            // 这只影响本 App 自己的 ScreenCaptureKit 流，不影响 OBS/系统录屏捕获 overlay。
            NSLog("[快捷高光] 未匹配到 overlay windowID，改用排除当前 App 防止自抓帧递归。")
            filter = SCContentFilter(display: display, excludingApplications: [currentApp], exceptingWindows: [])
        } else {
            NSLog("[快捷高光] 未匹配到 overlay windowID/currentApp，继续启动抓帧但可能出现自抓帧递归。")
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        // ⚠️ 重要：SCDisplay.width / .height 已经是物理像素（不是点）。
        // 之前写 `display.width * 2` 实际造成了 4×超采样，scaleX 算成 4.0，
        // 让 crop 区域过大，把 zoom 参数视觉化抵消掉了 —— 这是「放大倍率不生效」的真凶。
        //
        // 正确做法：用主屏 NSScreen 的「点尺寸 × backingScaleFactor」给 SCStream 配置
        // 物理像素，让 frame.width / pointSize.width == backingScaleFactor，crop 数学才对得上。
        let mainScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
        let pointSize: CGSize = mainScreen?.frame.size ?? CGSize(width: display.width, height: display.height)
        let backingScale: CGFloat = mainScreen?.backingScaleFactor ?? 2.0
        let pixelW = Int((pointSize.width * backingScale).rounded())
        let pixelH = Int((pointSize.height * backingScale).rounded())

        let config = SCStreamConfiguration()
        config.width = pixelW
        config.height = pixelH
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)  // 60fps 上限
        config.queueDepth = 3
        // 抓帧不渲染鼠标 — 圈内画面不会被鼠标光标挡住文字（用户体验更干净）
        // 圈外的真实鼠标依然由 macOS 系统层渲染，不受影响
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB

        displayPointSize = pointSize
        displayPixelSize = CGSize(width: pixelW, height: pixelH)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream = stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
        latestFrame = nil
    }
}

extension ScreenCapturer: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        // SCStream 系统级停止：常见原因包括 TCC 权限抖动、屏幕拓扑变化、系统 idle。
        // 之前留空 → 一旦 stream 挂了就再也不恢复，用户体感是「APP 用着用着就废了」。
        // 现在主动清理状态 + 通知 AppDelegate 触发静默重启（指数退避，不打扰用户）。
        let nsErr = error as NSError
        NSLog("[快捷高光] SCStream stopped: %@ (code=%d)", nsErr.localizedDescription, nsErr.code)
        Task { @MainActor in
            ScreenCapturer.shared.stream = nil
            ScreenCapturer.shared.latestFrame = nil
            ScreenCapturer.shared.onStreamStopped?(error)
        }
    }
}

extension ScreenCapturer: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }

        // CIImage 路径（IOSurface-backed CVPixelBuffer 高效）
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContextCache.shared.context
        guard let cgImage = context.createCGImage(ci, from: ci.extent) else { return }

        Task { @MainActor in
            ScreenCapturer.shared.latestFrame = cgImage
        }
    }
}

/// 复用 CIContext，不要每帧 new
private final class CIContextCache {
    static let shared = CIContextCache()
    let context: CIContext
    private init() {
        self.context = CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false
        ])
    }
}
