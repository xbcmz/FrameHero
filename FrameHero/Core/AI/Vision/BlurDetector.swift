//
//  BlurDetector.swift
//  FrameHero
//
//  快门瞬间的本地清晰度预审（Laplacian 方差检测）
//
//  ## 设计目标
//  手抖/失焦导致的糊片是最容易让人沮丧的拍摄失败——现状是"存盘后才发现"。
//  本检测器在照片落盘的同时（后台队列，不阻塞保存流程）对刚拍的 JPEG 快速
//  抽一张小缩略图，跑一次经典的 3x3 拉普拉斯卷积算清晰度，几十毫秒内给出
//  "可能糊了"的信号，供 UI 提示用户当场重拍。
//
//  ## 实现要点
//  - 用 CGImageSource 的缩略图接口而非完整解码 UIImage，量级更小、更快
//  - 阈值是基于缩小后灰度图的经验值，需要结合真机样本继续标定
//  - 只做"提示"，不做任何拦截；判断失败（decode 失败等）直接放行不提示
//

import Foundation
import ImageIO
import CoreGraphics

enum BlurDetector {

    struct Result {
        /// 是否判定为模糊
        let isBlurry: Bool
        /// 拉普拉斯响应方差（仅供调试/后续调参参考）
        let variance: Double
    }

    /// 缩略图最大边长：足够判断整体清晰度，同时保证解码和卷积都是毫秒级
    private static let maxPixelSize = 480
    /// 方差低于该阈值判定为模糊；基于 480px 缩略图的经验值，需要真机样本继续标定
    private static let varianceThreshold = 12.0

    /// 从刚拍摄落盘的 JPEG 数据判断是否可能拍糊了
    static func evaluate(jpegData: Data) -> Result? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let gray = grayscaleBuffer(from: thumbnail) else {
            return nil
        }
        let variance = laplacianVariance(gray.pixels, width: gray.width, height: gray.height)
        return Result(isBlurry: variance < varianceThreshold, variance: variance)
    }

    /// 把缩略图渲染成纯灰度像素缓冲，供拉普拉斯卷积直接读取
    private static func grayscaleBuffer(from image: CGImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        let width = image.width
        let height = image.height
        guard width > 8, height > 8 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (pixels, width, height)
    }

    /// 经典 3x3 离散拉普拉斯核（[0,1,0;1,-4,1;0,1,0]）卷积后取响应方差；
    /// 方差越低代表画面边缘/纹理越少，越可能是糊的
    private static func laplacianVariance(_ pixels: [UInt8], width: Int, height: Int) -> Double {
        guard width > 2, height > 2 else { return .greatestFiniteMagnitude }

        var responses = [Double]()
        responses.reserveCapacity((width - 2) * (height - 2))

        for y in 1..<(height - 1) {
            let rowStart = y * width
            let upStart = (y - 1) * width
            let downStart = (y + 1) * width
            for x in 1..<(width - 1) {
                let center = Double(pixels[rowStart + x])
                let up = Double(pixels[upStart + x])
                let down = Double(pixels[downStart + x])
                let left = Double(pixels[rowStart + x - 1])
                let right = Double(pixels[rowStart + x + 1])
                responses.append(up + down + left + right - 4 * center)
            }
        }

        guard !responses.isEmpty else { return .greatestFiniteMagnitude }
        let mean = responses.reduce(0, +) / Double(responses.count)
        let variance = responses.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(responses.count)
        return variance
    }
}
