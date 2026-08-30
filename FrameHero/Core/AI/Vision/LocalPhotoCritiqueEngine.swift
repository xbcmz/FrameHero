//
//  LocalPhotoCritiqueEngine.swift
//  FrameHero
//
//  本地 AI 点评引擎（零网络、Vision 框架离线分析）
//
//  ## 定位
//  拍后点评的"本地优先"一环：不需要配置云端 Key、不联网，
//  几百毫秒内即可产出结构化点评。用于：
//  - 图库「AI 点评」的默认首屏结果（云端到达前/未配置云端时展示）
//  - 从系统相册批量导入照片时的即时打分
//
//  ## 方法（均为启发式，非机器学习打分）
//  - 构图分：VNGenerateAttentionBasedSaliencyImageRequest 找到显著区域，
//    计算其中心到最近三分线交点的归一化距离，越近分越高
//  - 光线分：缩到 32×32 灰度采样，统计平均亮度与高光/阴影裁剪比例
//  - 主体分：显著区域置信度 + 是否检测到人脸的加成
//  - 标签/亮点/改进建议：基于以上信号的规则文案，不依赖 LLM
//

import Foundation
import Vision
import CoreGraphics
import UIKit

enum LocalPhotoCritiqueEngine {

    /// 同步执行（内部只做 Vision 请求 + 像素采样，量级为毫秒级；
    /// 调用方应在后台队列调用，避免占用主线程）
    static func analyze(_ image: UIImage) -> PhotoCritique? {
        guard let cgImage = image.cgImage else { return nil }

        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try? handler.perform([saliencyRequest, faceRequest])

        let salientObject = saliencyRequest.results?.first?.salientObjects?
            .max { $0.confidence < $1.confidence }
        let faceCount = faceRequest.results?.count ?? 0

        let compositionScore = compositionScore(for: salientObject?.boundingBox)
        let light = lightAnalysis(for: cgImage)
        let subjectScore = subjectScore(confidence: salientObject?.confidence, faceCount: faceCount)

        let overall = Int(
            (Double(compositionScore) * 0.4 + Double(light.score) * 0.3 + Double(subjectScore) * 0.3)
                .rounded()
        )

        var tags: [String] = []
        if faceCount > 0 { tags.append("检测到人脸") }
        if salientObject == nil { tags.append("主体不突出") }
        if compositionScore >= 80 { tags.append("三分构图") }
        if light.isBacklit { tags.append("逆光") }
        if light.isDark { tags.append("画面偏暗") }
        if light.isOverexposed { tags.append("曝光过度") }

        var strengths: [String] = []
        if compositionScore >= 75 { strengths.append("主体位置贴近三分构图交点，视觉重心舒服") }
        if light.score >= 75 { strengths.append("曝光均衡，明暗过渡自然") }
        if subjectScore >= 75 { strengths.append("主体清晰突出，一眼能找到重点") }
        if strengths.isEmpty { strengths.append("画面信息完整，基础曝光可用") }

        var improvements: [String] = []
        if compositionScore < 60 { improvements.append("尝试把主体挪到画面三分线交点附近，而不是正中央或边缘") }
        if light.isDark { improvements.append("画面偏暗，建议增加曝光或找光源补光") }
        if light.isOverexposed { improvements.append("高光区域过曝细节丢失，建议适当降低曝光") }
        if light.isBacklit { improvements.append("逆光导致主体偏暗，建议顺光拍摄或对主体测光") }
        if salientObject == nil && faceCount == 0 { improvements.append("画面主体不够突出，靠近主体或简化背景会更聚焦") }
        if improvements.isEmpty { improvements.append("整体已经不错，可以尝试更有想法的角度再拍一版") }

        return PhotoCritique(
            score: overall.clamped(to: 0...100),
            summary: summary(for: overall),
            strengths: strengths,
            improvements: improvements,
            compositionScore: compositionScore,
            lightScore: light.score,
            subjectScore: subjectScore,
            tags: tags,
            source: .local
        )
    }

    // MARK: - 构图分

    /// 显著区域中心到最近三分线交点的归一化距离 → 分数。
    /// Vision 的 boundingBox 是归一化坐标，原点在左下角。
    private static func compositionScore(for boundingBox: CGRect?) -> Int {
        guard let box = boundingBox else { return 55 }
        let center = CGPoint(x: box.midX, y: box.midY)
        let thirdPoints: [CGPoint] = [
            CGPoint(x: 1.0 / 3, y: 1.0 / 3), CGPoint(x: 1.0 / 3, y: 2.0 / 3),
            CGPoint(x: 2.0 / 3, y: 1.0 / 3), CGPoint(x: 2.0 / 3, y: 2.0 / 3)
        ]
        let minDistance = thirdPoints
            .map { hypot($0.x - center.x, $0.y - center.y) }
            .min() ?? 0.5
        // 经验参数：距离 0 → 100 分，距离 ≥0.32（约等于跑到画面正中心）→ 60 分兜底
        let normalized = min(minDistance / 0.32, 1.0)
        let score = 100.0 - normalized * 40.0
        return Int(score.rounded()).clamped(to: 40...100)
    }

    // MARK: - 光线分

    private struct LightAnalysis {
        let score: Int
        let isDark: Bool
        let isOverexposed: Bool
        let isBacklit: Bool
    }

    /// 32×32 灰度下采样后统计亮度分布：
    /// - 平均亮度过低/过高扣分
    /// - 高光/阴影裁剪比例过大扣分
    /// - 画面边框亮度显著高于中心区域 → 判定逆光
    private static func lightAnalysis(for cgImage: CGImage) -> LightAnalysis {
        let size = 32
        guard let samples = grayscaleSamples(cgImage, size: size) else {
            return LightAnalysis(score: 65, isDark: false, isOverexposed: false, isBacklit: false)
        }

        let total = samples.count
        let mean = samples.reduce(0.0) { $0 + Double($1) } / Double(total)
        let shadowClipped = samples.filter { $0 < 12 }.count
        let highlightClipped = samples.filter { $0 > 244 }.count
        let shadowRatio = Double(shadowClipped) / Double(total)
        let highlightRatio = Double(highlightClipped) / Double(total)

        // 中心 16×16 区域 vs 四角区域的均值对比，粗判逆光（主体暗、背景亮）
        let centerMean = regionMean(samples, size: size, rect: (8, 8, 16, 16))
        let borderMean = regionMean(samples, size: size, rect: (0, 0, size, size), excluding: (8, 8, 16, 16))
        let isBacklit = borderMean - centerMean > 45

        let isDark = mean < 70
        let isOverexposed = highlightRatio > 0.22

        var score = 100.0
        // 亮度偏离理想区间 [95, 175] 的惩罚
        let idealRange: ClosedRange<Double> = 95...175
        if !idealRange.contains(mean) {
            let distance = mean < idealRange.lowerBound ? idealRange.lowerBound - mean : mean - idealRange.upperBound
            score -= min(distance / 2.0, 40)
        }
        score -= shadowRatio * 60
        score -= highlightRatio * 60
        if isBacklit { score -= 10 }

        return LightAnalysis(
            score: Int(score.rounded()).clamped(to: 20...100),
            isDark: isDark,
            isOverexposed: isOverexposed,
            isBacklit: isBacklit
        )
    }

    private static func grayscaleSamples(_ cgImage: CGImage, size: Int) -> [UInt8]? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: size * size)
        return Array(UnsafeBufferPointer(start: buffer, count: size * size))
    }

    /// 矩形区域内像素均值，可选排除一个内部子矩形（用于取"边框"区域）
    private static func regionMean(
        _ samples: [UInt8], size: Int,
        rect: (x: Int, y: Int, w: Int, h: Int),
        excluding inner: (x: Int, y: Int, w: Int, h: Int)? = nil
    ) -> Double {
        var sum = 0.0
        var count = 0
        for y in rect.y..<(rect.y + rect.h) {
            for x in rect.x..<(rect.x + rect.w) {
                if let inner, x >= inner.x, x < inner.x + inner.w, y >= inner.y, y < inner.y + inner.h {
                    continue
                }
                sum += Double(samples[y * size + x])
                count += 1
            }
        }
        return count > 0 ? sum / Double(count) : 0
    }

    // MARK: - 主体分

    private static func subjectScore(confidence: Float?, faceCount: Int) -> Int {
        var score: Double
        if let confidence {
            score = Double(confidence) * 100
        } else {
            score = faceCount > 0 ? 70 : 45
        }
        if faceCount > 0 { score += 10 }
        return Int(score.rounded()).clamped(to: 30...100)
    }

    // MARK: - 总评文案

    private static func summary(for overall: Int) -> String {
        switch overall {
        case 85...: return "构图、光线、主体表达都在线，是一张能直接发的好照片"
        case 70..<85: return "整体不错，构图或光线还有一点提升空间"
        case 55..<70: return "基础可用，构图/曝光其中一项拖了后腿"
        default: return "建议重新构思一下构图和光线再拍一版"
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        // Int 扩展内需显式 Swift. 前缀：unqualified min/max 会被
        // FixedWidthInteger 的静态属性 Int.min/Int.max 遮蔽
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
