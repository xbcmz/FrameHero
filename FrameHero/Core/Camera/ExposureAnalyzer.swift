//
//  ExposureAnalyzer.swift
//  FrameHero
//
//  预览帧的轻量曝光风险检测（过曝/欠曝）
//
//  ## 设计目标
//  过曝欠曝是最常见但最容易被忽视的拍摄失败原因，现状是"拍完才在点评里
//  看到光线分低"。本检测器直接在相机预览帧上跑，节流到 1Hz 左右，供
//  CaptureViewModel 实时弹出提示 + 一键曝光补偿。
//
//  ## 实现要点
//  - 不跑 CoreImage/Vision，直接读 CVPixelBuffer 的 Y（亮度）平面内存，
//    稀疏采样后统计高光/阴影裁剪比例，单次调用开销 <1ms
//  - 只在 videoOutputQueue 上做纯内存读取，不需要额外的队列调度
//  - 阈值是经验值：裁剪像素占采样点比例超过 35% 才报警，避免小光源/
//    纯色背景误报
//

import Foundation
import CoreVideo

/// 实时曝光风险提示的两种状态
enum ExposureWarning: Equatable {
    case overexposed
    case underexposed
}

enum ExposureAnalyzer {
    /// 高光裁剪判定阈值（亮度 0-255，YCbCr 全范围）
    private static let highlightThreshold: UInt8 = 250
    /// 阴影裁剪判定阈值
    private static let shadowThreshold: UInt8 = 8
    /// 裁剪像素占采样点比例超过该值才报警
    private static let clippingRatioThreshold: Double = 0.35
    /// 采样步长（每隔 N 个像素采一次，控制采样点在几千量级）
    private static let sampleStride = 6

    /// 评估一帧画面是否存在明显的过曝/欠曝风险；无风险或格式不支持时返回 nil
    static func evaluate(_ pixelBuffer: CVPixelBuffer) -> ExposureWarning? {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        guard width > 0, height > 0, bytesPerRow > 0 else { return nil }

        let buffer = base.assumingMemoryBound(to: UInt8.self)
        var highlightCount = 0
        var shadowCount = 0
        var sampleCount = 0

        var y = 0
        while y < height {
            let rowStart = y * bytesPerRow
            var x = 0
            while x < width {
                let value = buffer[rowStart + x]
                if value >= highlightThreshold {
                    highlightCount += 1
                } else if value <= shadowThreshold {
                    shadowCount += 1
                }
                sampleCount += 1
                x += sampleStride
            }
            y += sampleStride
        }

        guard sampleCount > 0 else { return nil }
        let highlightRatio = Double(highlightCount) / Double(sampleCount)
        let shadowRatio = Double(shadowCount) / Double(sampleCount)

        if highlightRatio >= clippingRatioThreshold { return .overexposed }
        if shadowRatio >= clippingRatioThreshold { return .underexposed }
        return nil
    }
}
