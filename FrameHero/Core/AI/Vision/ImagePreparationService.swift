//
//  ImagePreparationService.swift
//  FrameHero
//
//  视觉请求的图片预处理（Phase 0.4）
//
//  ## 管线
//  相机帧(CVPixelBuffer) → 方向校正 → 降采样(最长边≤1024) →
//  JPEG 压缩(~0.65) → Data → base64 data URL
//
//  ## 为什么要预处理
//  相机原始帧（如 1080×1440 BGRA）直接 base64 会产生数 MB 的请求体，
//  上行慢、计费重、模型也不需要。压缩到 ~100-300KB 即可保留
//  构图分析所需的全部信息。
//

import Foundation
import UIKit
import CoreImage
import CoreVideo

enum ImagePreparationService {

    /// 共享 CIContext（避免每次请求重建 GPU 上下文）
    private static let ciContext = CIContext()

    /// 默认参数：构图理解场景下 1024 边长 + 0.65 质量足够
    static func prepareVisionPayload(from pixelBuffer: CVPixelBuffer,
                                     orientation: CGImagePropertyOrientation,
                                     maxDimension: CGFloat = 1024,
                                     jpegQuality: CGFloat = 0.65) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        return prepareVisionPayload(from: ciImage, maxDimension: maxDimension, jpegQuality: jpegQuality)
    }

    static func prepareVisionPayload(from image: UIImage,
                                     maxDimension: CGFloat = 1024,
                                     jpegQuality: CGFloat = 0.65) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        return prepareVisionPayload(from: ciImage, maxDimension: maxDimension, jpegQuality: jpegQuality)
    }

    private static func prepareVisionPayload(from ciImage: CIImage,
                                             maxDimension: CGFloat,
                                             jpegQuality: CGFloat) -> Data? {
        let longEdge = max(ciImage.extent.width, ciImage.extent.height)
        guard longEdge > 0 else { return nil }

        // 等比降采样（只缩不放）
        let scale = min(1.0, maxDimension / longEdge)
        let scaled = scale < 1.0
            ? ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : ciImage

        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: jpegQuality)
    }

    /// JPEG Data → data URL（多模态消息的 image_url 字段格式）
    static func dataURL(from jpegData: Data) -> String {
        "data:image/jpeg;base64," + jpegData.base64EncodedString()
    }
}
