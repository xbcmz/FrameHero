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
//    计算其中心到最近三分线交点的归一化距离，越近分越高；对称构图会被
//    单独识别并回补分数，不再被三分法单一标准误判为低分
//  - 光线分：缩到 32×32 灰度采样，统计平均亮度与高光/阴影裁剪比例
//  - 主体分：显著区域置信度 + 是否检测到人脸的加成
//  - 构图原语（新增）：复用同一份 32×32 灰度采样，追加三个轻量几何信号——
//    左右镜像相似度（对称构图）、左右边缘密度比（视觉平衡）、水平/垂直/对角
//    梯度占比（引导线走向）、显著物体是否贴底大面积入画（前景层次候选）。
//    这组「构图原语」词汇参考了 CADB/SAMP-Net（BMVC 2021）的构图属性标注体系
//    （rule_of_thirds / balancing_elements / symmetry / object_emphasis），
//    用零依赖的启发式近似同一组信号，方便未来替换成真正的 CoreML 模型时
//    输出词汇不用大改
//  - 标签/亮点/改进建议：基于以上信号的规则文案，不依赖 LLM
//  - compositionPrimitivesSummary()：把这组原语渲染成一句话事实陈述，
//    供云端点评 prompt 引用，让 LLM 不必只凭像素重新猜测对称轴/引导线
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

        var compositionScore = compositionScore(for: salientObject?.boundingBox)
        let light = lightAnalysis(for: cgImage)
        let subjectScore = subjectScore(confidence: salientObject?.confidence, faceCount: faceCount)
        let structure = structureAnalysis(for: cgImage, salientBox: salientObject?.boundingBox)

        // 对称构图不应被"离三分交点远"误判为低分——识别到强对称时，
        // 用对称信号把分数托底到合理区间（而不是简单相加，避免和三分法信号叠加超标）
        if structure.isSymmetric {
            let symmetryFloor = 62 + Int((Double(structure.symmetryScore - 72) * 0.6).rounded())
            compositionScore = max(compositionScore, symmetryFloor.clamped(to: 62...94))
        }

        let overall = Int(
            (Double(compositionScore) * 0.4 + Double(light.score) * 0.3 + Double(subjectScore) * 0.3)
                .rounded()
        )

        var tags: [String] = []
        if faceCount > 0 { tags.append("检测到人脸") }
        if salientObject == nil { tags.append("主体不突出") }
        if structure.isSymmetric { tags.append("对称构图") }
        else if compositionScore >= 80 { tags.append("三分构图") }
        if structure.dominantOrientation == .diagonal { tags.append("引导线/对角线构图") }
        if structure.hasForegroundCandidate { tags.append("前景层次") }
        if structure.isImbalanced { tags.append("画面重心偏\(structure.heavierSide)") }
        if light.isBacklit { tags.append("逆光") }
        if light.isDark { tags.append("画面偏暗") }
        if light.isOverexposed { tags.append("曝光过度") }

        var strengths: [String] = []
        if structure.isSymmetric { strengths.append("画面左右对称，秩序感和稳定感很强") }
        else if compositionScore >= 75 { strengths.append("主体位置贴近三分构图交点，视觉重心舒服") }
        if structure.dominantOrientation == .diagonal { strengths.append("对角线走向明显，画面有引导视线的纵深感") }
        if structure.hasForegroundCandidate { strengths.append("下方有贴近镜头的前景元素，增加了空间层次") }
        if light.score >= 75 { strengths.append("曝光均衡，明暗过渡自然") }
        if subjectScore >= 75 { strengths.append("主体清晰突出，一眼能找到重点") }
        if strengths.isEmpty { strengths.append("画面信息完整，基础曝光可用") }

        var improvements: [String] = []
        if !structure.isSymmetric && compositionScore < 60 {
            improvements.append("尝试把主体挪到画面三分线交点附近，而不是正中央或边缘")
        }
        if structure.isImbalanced {
            improvements.append("画面\(structure.heavierSide)侧偏重，挪动主体或加/减一个前景元素找平衡")
        }
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

    // MARK: - 构图原语（对称/平衡/引导线/前景）

    private enum DominantOrientation: Equatable {
        case horizontal, vertical, diagonal, none
    }

    private struct StructureAnalysis {
        /// 左右镜像相似度 0-100，越高越对称
        let symmetryScore: Int
        let isSymmetric: Bool
        /// 左右边缘密度（视觉重量）均衡度 0-100
        let balanceScore: Int
        let isImbalanced: Bool
        /// 重的一侧（仅当 isImbalanced 时有意义）
        let heavierSide: String
        let dominantOrientation: DominantOrientation
        /// 显著物贴近画面下边缘且占比不小，像一个前景层次元素
        let hasForegroundCandidate: Bool
    }

    /// 复用 32×32 灰度采样，一次性计算对称/平衡/主导方向/前景四个信号。
    /// 均为启发式几何估算，不是语义级的构图模式识别（参见文件头注释中关于
    /// CADB/SAMP-Net 的说明）。
    private static func structureAnalysis(for cgImage: CGImage, salientBox: CGRect?) -> StructureAnalysis {
        let size = 32
        guard let samples = grayscaleSamples(cgImage, size: size) else {
            return StructureAnalysis(symmetryScore: 50, isSymmetric: false, balanceScore: 50,
                                      isImbalanced: false, heavierSide: "", dominantOrientation: .none,
                                      hasForegroundCandidate: false)
        }

        // 对称：每行左右镜像位的亮度差，差越小越对称
        var mirrorDiffSum = 0.0
        var mirrorCount = 0
        for y in 0..<size {
            for x in 0..<(size / 2) {
                let left = Double(samples[y * size + x])
                let right = Double(samples[y * size + (size - 1 - x)])
                mirrorDiffSum += abs(left - right)
                mirrorCount += 1
            }
        }
        let mirrorDiff = mirrorCount > 0 ? mirrorDiffSum / Double(mirrorCount) : 80
        // 经验参数：均差达到 ~70 视为完全不对称（0分），0 差异为完全对称（100分）
        let symmetryScore = Int((100.0 - min(mirrorDiff / 70.0, 1.0) * 100.0).rounded()).clamped(to: 0...100)
        let isSymmetric = symmetryScore >= 72

        // 视觉平衡：左右半边的相邻像素梯度幅度之和（近似“边缘/细节密度”，
        // 作为“视觉重量”的代用指标）
        var leftWeight = 0.0
        var rightWeight = 0.0
        var horizontalGrad = 0.0
        var verticalGrad = 0.0
        var diagonalGrad = 0.0
        for y in 0..<(size - 1) {
            for x in 0..<(size - 1) {
                let p00 = Double(samples[y * size + x])
                let p10 = Double(samples[y * size + x + 1])
                let p01 = Double(samples[(y + 1) * size + x])
                let p11 = Double(samples[(y + 1) * size + x + 1])
                let gx = abs(p10 - p00)
                let gy = abs(p01 - p00)
                let gDiag = abs(p11 - p00)
                horizontalGrad += gx
                verticalGrad += gy
                diagonalGrad += gDiag
                let weight = gx + gy
                if x < size / 2 { leftWeight += weight } else { rightWeight += weight }
            }
        }
        let totalWeight = leftWeight + rightWeight
        let balanceRatio = totalWeight > 0 ? min(leftWeight, rightWeight) / max(leftWeight, rightWeight, 1) : 1
        let balanceScore = Int((balanceRatio * 100).rounded()).clamped(to: 0...100)
        let isImbalanced = balanceScore < 55 && totalWeight > 200
        let heavierSide = leftWeight > rightWeight ? "左" : "右"

        // 主导方向：水平/垂直/对角梯度哪个显著高于其余二者，才视为“主导”，
        // 否则认为方向不明显（避免平均图像也被硬分到某个方向）
        let orientations: [(DominantOrientation, Double)] = [
            (.horizontal, horizontalGrad), (.vertical, verticalGrad), (.diagonal, diagonalGrad)
        ]
        let sorted = orientations.sorted { $0.1 > $1.1 }
        let dominantOrientation: DominantOrientation
        if sorted[0].1 > 0, sorted[0].1 > sorted[1].1 * 1.25 {
            dominantOrientation = sorted[0].0
        } else {
            dominantOrientation = .none
        }

        // 前景候选：Vision boundingBox 原点在左下，靠近 y=0 就是靠近画面下边缘，
        // 且高度够大时才视为可能的前景层次元素（而不是小点噪声）
        let hasForegroundCandidate: Bool
        if let box = salientBox {
            hasForegroundCandidate = box.minY <= 0.12 && box.height >= 0.28
        } else {
            hasForegroundCandidate = false
        }

        return StructureAnalysis(
            symmetryScore: symmetryScore, isSymmetric: isSymmetric,
            balanceScore: balanceScore, isImbalanced: isImbalanced, heavierSide: heavierSide,
            dominantOrientation: dominantOrientation, hasForegroundCandidate: hasForegroundCandidate
        )
    }

    // MARK: - 云端 prompt 用的构图原语提取

    /// 提取一组构图原语事实陈述（对称/视觉平衡/主导方向/前景），
    /// 供云端 LLM 的点评 prompt 引用——比让模型单凭像素自行猜测更具体、
    /// 也更省 token。失败时返回 nil，调用方应降级为不带此上下文。
    static func compositionPrimitivesSummary(_ image: UIImage) -> String? {
        guard let cgImage = image.cgImage else { return nil }

        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try? handler.perform([saliencyRequest])
        let salientObject = saliencyRequest.results?.first?.salientObjects?
            .max { $0.confidence < $1.confidence }

        let structure = structureAnalysis(for: cgImage, salientBox: salientObject?.boundingBox)

        var facts: [String] = []
        facts.append(structure.isSymmetric ? "画面接近左右对称" : "画面非对称布局")
        facts.append(structure.isImbalanced
            ? "视觉重心偏向\(structure.heavierSide)侧"
            : "左右视觉重量大致均衡")
        switch structure.dominantOrientation {
        case .diagonal: facts.append("存在明显的对角线走向，可利用作引导线")
        case .horizontal: facts.append("画面以水平线条为主")
        case .vertical: facts.append("画面以垂直线条为主")
        case .none: break
        }
        if structure.hasForegroundCandidate {
            facts.append("画面下方有贴近镜头的前景元素")
        }
        if let box = salientObject?.boundingBox {
            let thirdPoints: [CGPoint] = [
                CGPoint(x: 1.0 / 3, y: 1.0 / 3), CGPoint(x: 1.0 / 3, y: 2.0 / 3),
                CGPoint(x: 2.0 / 3, y: 1.0 / 3), CGPoint(x: 2.0 / 3, y: 2.0 / 3)
            ]
            let center = CGPoint(x: box.midX, y: box.midY)
            let minDistance = thirdPoints.map { hypot($0.x - center.x, $0.y - center.y) }.min() ?? 1
            facts.append(minDistance < 0.1 ? "主体已较接近三分线交点" : "主体未处在三分线交点附近")
        }
        return facts.isEmpty ? nil : facts.joined(separator: "；")
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
