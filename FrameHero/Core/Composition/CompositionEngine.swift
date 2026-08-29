//
//  CompositionEngine.swift
//  FrameHero
//
//  构图引擎
//
//  ## 文件作用
//  接收原始的检测数据（人脸、人体、显著性区域），
//  通过可解释的规则计算构图评分和调整建议，输出 CompositionResult。
//
//  ## 设计原则
//  1. 纯计算，无副作用（不依赖相机、不依赖 UI、不依赖网络）
//  2. 所有评分逻辑可解释、可调整
//  3. 坐标全部使用归一化值 [0, 1]
//  4. 评分范围：每项 0~100，总分 0~100
//
//  ## 评分维度及权重
//  参考 CADB（构图评价）、FG-IAA（美学评价）、PPC（视角推荐）的思路：
//
//  | 维度 | 权重 | 说明 | 参考来源 |
//  |------|------|------|---------|
//  | 主体位置 | 30% | 人物在画面中的位置是否合理 | CADB 主体位置 + FG-IAA 构图因素 |
//  | 主体完整度 | 25% | 人物是否被边缘裁切、是否完整 | CADB 主体完整度 |
//  | 头顶留白 | 15% | 头顶空间是否舒适 | CADB 人物位置 + 人像摄影常识 |
//  | 边缘距离 | 15% | 人物是否太靠近画面边缘 | CADB 边缘距离 |
//  | 人物大小 | 15% | 人物在画面中的占比是否合适 | FG-IAA 主体比例 + PPC 视角因素 |
//
//  权重选择理由：
//  - 位置最重要（30%）：构图首先看"主体放在哪里"
//  - 完整度第二（25%）：人物被裁切是最影响观感的问题
//  - 头顶留白、边缘距离、大小各占 15%：都是重要但权重稍低的因素
//
//  ## 推荐逻辑
//  根据各维度的失分情况，给出最需要调整的方向：
//  - 位置不对 → 推荐移动方向
//  - 大小不对 → 推荐镜头（变焦）
//  - 头顶留白不对 → 推荐相机高度
//  - 边缘距离不对 → 推荐远离边缘的方向
//
//  ## 使用方式
//  let engine = CompositionEngine()
//  let result = engine.analyze(detections: rawDetections, zoomFactor: 1.0)
//

import Foundation
import CoreGraphics

#if os(iOS)

// MARK: - 原始检测数据（输入）

/// 单个检测目标的 bounding box
/// 所有坐标为归一化值 [0, 1]
struct DetectedObject {
    /// 中心点 X（0=左，1=右）
    var centerX: CGFloat
    /// 中心点 Y（0=下，1=上）
    var centerY: CGFloat
    /// 宽度比例（相对于画面宽度）
    var width: CGFloat
    /// 高度比例（相对于画面高度）
    var height: CGFloat
    /// 检测置信度 0~1
    var confidence: Float

    /// 左边位置（归一化）
    var minX: CGFloat { centerX - width / 2 }
    /// 右边位置（归一化）
    var maxX: CGFloat { centerX + width / 2 }
    /// 下边位置（归一化）
    var minY: CGFloat { centerY - height / 2 }
    /// 上边位置（归一化）
    var maxY: CGFloat { centerY + height / 2 }
}

/// 原始检测数据集合（Vision / CoreML 检测后的原始输出）
struct RawDetections {
    /// 检测到的人脸列表
    var faces: [DetectedObject] = []
    /// 检测到的人体列表
    var bodies: [DetectedObject] = []
    /// 显著性区域列表（可选）
    var saliencyRegions: [DetectedObject] = []
}

// MARK: - 评分权重配置

/// 评分权重配置
/// 所有权重之和应为 1.0
struct CompositionScoreWeights {
    var position: Double = 0.30      // 主体位置 30%
    var subjectIntegrity: Double = 0.25 // 主体完整度 25%
    var headRoom: Double = 0.15      // 头顶留白 15%
    var edgeDistance: Double = 0.15  // 边缘距离 15%
    var size: Double = 0.15          // 人物大小 15%

    /// 默认配置
    static let `default` = CompositionScoreWeights()
}

// MARK: - 构图引擎

/// 构图分析引擎
///
/// 输入原始检测数据，输出结构化的构图分析结果。
/// 纯计算类，无副作用，便于测试和复用。
final class CompositionEngine {

    // MARK: - 配置

    /// 评分权重
    private let weights: CompositionScoreWeights

    /// 理想的人物高度占画面比例（人像摄影通常 0.6~0.8）
    private let idealPersonHeightRatio: CGFloat = 0.75

    /// 理想的头顶留白比例（头顶到画面顶部 / 画面高度）
    private let idealHeadRoomRatio: CGFloat = 0.12

    /// 可接受的头顶留白范围
    private let acceptableHeadRoomRange: ClosedRange<CGFloat> = 0.05...0.25

    /// 理想的边缘距离（人物边缘到画面边缘的最小比例）
    private let idealEdgeMargin: CGFloat = 0.08

    /// 可接受的最小边缘距离
    private let minAcceptableEdgeMargin: CGFloat = 0.02

    /// 理想的人物宽度占画面比例
    private let idealPersonWidthRatio: CGFloat = 0.4

    /// 可接受的人物宽度范围
    private let acceptableWidthRange: ClosedRange<CGFloat> = 0.2...0.7

    // MARK: - 初始化

    init(weights: CompositionScoreWeights = .default) {
        self.weights = weights
    }

    // MARK: - 主入口

    /// 分析构图，输出完整结果
    /// - Parameters:
    ///   - detections: 原始检测数据
    ///   - zoomFactor: 当前变焦倍率（用于记录）
    ///   - focalLength: 当前等效焦距（用于记录）
    ///   - detectionMode: 检测模式名称（用于调试）
    /// - Returns: 构图分析结果
    func analyze(
        detections: RawDetections,
        zoomFactor: CGFloat = 1.0,
        focalLength: Int = 24,
        detectionMode: String = "Vision"
    ) -> CompositionResult {
        var result = CompositionResult()
        result.currentZoomFactor = zoomFactor
        result.currentFocalLength = focalLength
        result.detectionMode = detectionMode

        // 1. 提取主主体（优先用人体，其次用人脸）
        guard let mainSubject = extractMainSubject(from: detections) else {
            // 没有检测到人，返回低分结果
            result.score = 0
            result.person.detected = false
            result.subjectPosition = .unknown
            result.compositionType = .unknown
            result.recommendedMove = .unknown
            result.recommendedLens = .unknown
            result.recommendedCameraHeight = .unknown
            result.confidence = 0
            return result
        }

        result.person.detected = true
        result.person.centerX = mainSubject.centerX
        result.person.centerY = mainSubject.centerY
        result.person.widthRatio = mainSubject.width
        result.person.heightRatio = mainSubject.height
        result.person.confidence = mainSubject.confidence

        // 如果有人脸，补充人脸信息
        if let mainFace = findMainFace(in: detections, forBody: mainSubject) {
            result.person.faceCenterX = mainFace.centerX
            result.person.faceCenterY = mainFace.centerY
            result.person.faceWidthRatio = mainFace.width
            result.faceCount = detections.faces.count
            // 基于人脸位置计算头顶留白
            result.person.headRoom = 1.0 - mainFace.maxY
        } else {
            // 没有人脸的话，用人体顶部估算头顶留白
            result.person.headRoom = 1.0 - mainSubject.maxY
        }
        result.bodyCount = detections.bodies.count

        // 2. 判断主体是否完整
        result.person.isFullBody = isSubjectFullyVisible(subject: mainSubject)

        // 3. 判断主体位置
        result.subjectPosition = calculateSubjectPosition(subject: mainSubject)

        // 4. 判断构图类型
        result.compositionType = calculateCompositionType(
            subject: mainSubject,
            face: findMainFace(in: detections, forBody: mainSubject)
        )

        // 5. 计算各项评分
        let positionScore = calculatePositionScore(subject: mainSubject)
        let sizeScore = calculateSizeScore(subject: mainSubject)
        let headRoomScore = calculateHeadRoomScore(
            person: mainSubject,
            face: findMainFace(in: detections, forBody: mainSubject)
        )
        let edgeScore = calculateEdgeDistanceScore(subject: mainSubject)
        let integrityScore = calculateSubjectIntegrityScore(subject: mainSubject)

        result.scoreBreakdown = CompositionScore(
            total: 0, // 下面算
            positionScore: positionScore,
            sizeScore: sizeScore,
            headRoomScore: headRoomScore,
            edgeDistanceScore: edgeScore,
            subjectIntegrityScore: integrityScore
        )

        // 6. 计算加权总分
        let total = Double(positionScore) * weights.position
            + Double(sizeScore) * weights.size
            + Double(headRoomScore) * weights.headRoom
            + Double(edgeScore) * weights.edgeDistance
            + Double(integrityScore) * weights.subjectIntegrity
        result.score = Int(round(total))
        result.scoreBreakdown.total = result.score

        // 7. 计算推荐调整方向
        result.recommendedMove = calculateRecommendedMove(
            subject: mainSubject,
            positionScore: positionScore,
            edgeScore: edgeScore
        )
        result.recommendedLens = calculateRecommendedLens(
            subject: mainSubject,
            sizeScore: sizeScore,
            currentZoom: zoomFactor
        )
        result.recommendedCameraHeight = calculateRecommendedCameraHeight(
            person: mainSubject,
            face: findMainFace(in: detections, forBody: mainSubject),
            headRoomScore: headRoomScore
        )

        // 8. 置信度（基于检测置信度和评分可靠度）
        result.confidence = mainSubject.confidence

        return result
    }

    // MARK: - 主体提取

    /// 提取主要主体
    /// 优先级：人体 > 人脸（人体通常更能代表完整的人物位置）
    private func extractMainSubject(from detections: RawDetections) -> DetectedObject? {
        // 优先取最大的人体
        if let largestBody = detections.bodies.max(by: { $0.height < $1.height }) {
            return largestBody
        }
        // 其次取置信度最高的人脸
        if let bestFace = detections.faces.max(by: { $0.confidence < $1.confidence }) {
            return bestFace
        }
        return nil
    }

    /// 找到与人体对应的主要人脸
    private func findMainFace(in detections: RawDetections, forBody body: DetectedObject?) -> DetectedObject? {
        guard let body = body else {
            return detections.faces.max(by: { $0.confidence < $1.confidence })
        }
        // 找到在人体上半部分且最接近人体中心 X 的人脸
        let candidateFaces = detections.faces.filter { face in
            // 人脸应该在人体的上半部分
            return face.centerY > body.centerY
                && abs(face.centerX - body.centerX) < body.width * 0.8
        }
        return candidateFaces.max(by: { $0.confidence < $1.confidence })
            ?? detections.faces.first
    }

    // MARK: - 完整度判断

    /// 判断主体是否完整（没有被画面边缘裁切）
    private func isSubjectFullyVisible(subject: DetectedObject) -> Bool {
        let margin: CGFloat = 0.01 // 允许 1% 的误差
        return subject.minX >= -margin
            && subject.maxX <= 1.0 + margin
            && subject.minY >= -margin
            && subject.maxY <= 1.0 + margin
    }

    // MARK: - 主体位置判断

    /// 判断主体在画面中的位置
    private func calculateSubjectPosition(subject: DetectedObject) -> SubjectPosition {
        let x = subject.centerX
        let y = subject.centerY

        // 定义三分线位置
        let leftThird: CGFloat = 1.0 / 3.0
        let rightThird: CGFloat = 2.0 / 3.0
        let topThird: CGFloat = 2.0 / 3.0  // Y 轴向上为正
        let bottomThird: CGFloat = 1.0 / 3.0

        // 中心容差
        let centerToleranceX: CGFloat = 0.08
        let centerToleranceY: CGFloat = 0.08

        // 判断是否在中心
        let isCenterX = abs(x - 0.5) < centerToleranceX
        let isCenterY = abs(y - 0.5) < centerToleranceY

        if isCenterX && isCenterY {
            return .center
        }

        // 判断是否在三分线附近
        let nearLeftThird = abs(x - leftThird) < centerToleranceX
        let nearRightThird = abs(x - rightThird) < centerToleranceX
        let nearTopThird = abs(y - topThird) < centerToleranceY
        let nearBottomThird = abs(y - bottomThird) < centerToleranceY

        if nearLeftThird && isCenterY { return .leftThird }
        if nearRightThird && isCenterY { return .rightThird }
        if isCenterX && nearTopThird { return .topThird }
        if isCenterX && nearBottomThird { return .bottomThird }

        // 判断四角
        let nearLeft = x < leftThird
        let nearRight = x > rightThird
        let nearTop = y > topThird
        let nearBottom = y < bottomThird

        if nearLeft && nearTop { return .topLeft }
        if nearRight && nearTop { return .topRight }
        if nearLeft && nearBottom { return .bottomLeft }
        if nearRight && nearBottom { return .bottomRight }

        // 判断是否靠边
        if subject.minX < 0.03 { return .leftEdge }
        if subject.maxX > 0.97 { return .rightEdge }

        return .unknown
    }

    // MARK: - 构图类型判断

    /// 判断构图类型
    private func calculateCompositionType(subject: DetectedObject, face: DetectedObject?) -> CompositionType {
        let position = calculateSubjectPosition(subject: subject)

        // 先检查问题类型
        if !isSubjectFullyVisible(subject: subject) {
            return .edgeCropping
        }

        let headRoom = face != nil ? (1.0 - face!.maxY) : (1.0 - subject.maxY)
        if headRoom < acceptableHeadRoomRange.lowerBound || headRoom > acceptableHeadRoomRange.upperBound {
            return .headroomIssue
        }

        // 再检查正面类型
        switch position {
        case .center:
            return .center
        case .leftThird, .rightThird, .topThird, .bottomThird,
             .topLeft, .topRight, .bottomLeft, .bottomRight:
            return .ruleOfThirds
        default:
            return .unknown
        }
    }

    // MARK: - 评分：主体位置

    /// 计算主体位置得分 0~100
    /// 评分逻辑：
    /// - 在三分线位置：高分
    /// - 在中心：中等偏上（中心构图也是一种好构图）
    /// - 太靠边：低分
    private func calculatePositionScore(subject: DetectedObject) -> Int {
        let x = subject.centerX
        let y = subject.centerY

        // 计算到最近三分点的距离（用于三分法评分）
        let leftThird: CGFloat = 1.0 / 3.0
        let rightThird: CGFloat = 2.0 / 3.0
        let topThird: CGFloat = 2.0 / 3.0
        let bottomThird: CGFloat = 1.0 / 3.0

        let thirdPointsX = [leftThird, rightThird, 0.5]
        let thirdPointsY = [bottomThird, topThird, 0.5]

        let minDistX = thirdPointsX.map { abs(x - $0) }.min() ?? 0.5
        let minDistY = thirdPointsY.map { abs(y - $0) }.min() ?? 0.5

        // 距离越近得分越高（满分 100）
        let xScore = max(0, 1.0 - minDistX / 0.35) * 100
        let yScore = max(0, 1.0 - minDistY / 0.35) * 100

        // 综合位置分（X 和 Y 各占一半）
        let positionScore = (xScore + yScore) / 2.0

        return Int(round(positionScore))
    }

    // MARK: - 评分：人物大小

    /// 计算人物大小得分 0~100
    /// 评分逻辑：
    /// - 高度在理想值附近：高分
    /// - 太小或太大：低分
    private func calculateSizeScore(subject: DetectedObject) -> Int {
        let height = subject.height
        let ideal = idealPersonHeightRatio

        // 计算偏差比例
        let deviation = abs(height - ideal) / ideal

        // 偏差 0% → 100 分，偏差 50% → 0 分
        let score = max(0, 1.0 - deviation / 0.5) * 100

        return Int(round(score))
    }

    // MARK: - 评分：头顶留白

    /// 计算头顶留白得分 0~100
    /// 评分逻辑：
    /// - 在理想值附近：高分
    /// - 太少（头顶贴顶）或太多（头顶太空）：低分
    private func calculateHeadRoomScore(person: DetectedObject, face: DetectedObject?) -> Int {
        let headRoom: CGFloat
        if let face = face {
            headRoom = 1.0 - face.maxY
        } else {
            headRoom = 1.0 - person.maxY
        }

        let ideal = idealHeadRoomRatio

        // 在可接受范围内：按距离理想值的程度给分
        if acceptableHeadRoomRange.contains(headRoom) {
            let deviation = abs(headRoom - ideal) / ideal
            let score = max(70, 100 - deviation * 100)
            return Int(round(score))
        } else {
            // 超出可接受范围：按超出程度扣分
            let excess: CGFloat
            if headRoom < acceptableHeadRoomRange.lowerBound {
                excess = acceptableHeadRoomRange.lowerBound - headRoom
            } else {
                excess = headRoom - acceptableHeadRoomRange.upperBound
            }
            let score = max(0, 70 - excess / 0.1 * 70)
            return Int(round(score))
        }
    }

    // MARK: - 评分：边缘距离

    /// 计算边缘距离得分 0~100
    /// 评分逻辑：
    /// - 四边都有足够留白：高分
    /// - 任意一边太近：低分
    private func calculateEdgeDistanceScore(subject: DetectedObject) -> Int {
        let leftMargin = subject.minX
        let rightMargin = 1.0 - subject.maxX
        let bottomMargin = subject.minY
        let topMargin = 1.0 - subject.maxY

        let margins = [leftMargin, rightMargin, bottomMargin, topMargin]
        let minMargin = margins.min() ?? 0

        if minMargin >= idealEdgeMargin {
            // 边距充足：满分附近
            return 95
        } else if minMargin >= minAcceptableEdgeMargin {
            // 边距在可接受范围内：线性插值
            let ratio = (minMargin - minAcceptableEdgeMargin) / (idealEdgeMargin - minAcceptableEdgeMargin)
            let score = 60 + ratio * 35
            return Int(round(score))
        } else {
            // 边距太小：快速下降
            let ratio = minMargin / minAcceptableEdgeMargin
            let score = ratio * 60
            return Int(round(score))
        }
    }

    // MARK: - 评分：主体完整度

    /// 计算主体完整度得分 0~100
    /// 评分逻辑：
    /// - 完全可见：100 分
    /// - 被边缘裁切：按裁切程度扣分
    private func calculateSubjectIntegrityScore(subject: DetectedObject) -> Int {
        if isSubjectFullyVisible(subject: subject) {
            return 100
        }

        // 计算被裁切的比例
        var croppedAmount: CGFloat = 0

        if subject.minX < 0 { croppedAmount += -subject.minX }
        if subject.maxX > 1 { croppedAmount += subject.maxX - 1 }
        if subject.minY < 0 { croppedAmount += -subject.minY }
        if subject.maxY > 1 { croppedAmount += subject.maxY - 1 }

        // 裁切总量（X 和 Y 方向），最多扣 80 分
        let penalty = min(croppedAmount * 4, 0.8) * 100
        let score = max(0, 100 - penalty)

        return Int(round(score))
    }

    // MARK: - 推荐：移动方向

    /// 计算推荐的移动方向
    /// 找出最需要调整的维度，给出对应建议
    private func calculateRecommendedMove(
        subject: DetectedObject,
        positionScore: Int,
        edgeScore: Int
    ) -> MoveDirection {

        // 如果得分已经很高（>85），建议保持不动
        let avgScore = (Double(positionScore) + Double(edgeScore)) / 2
        if avgScore >= 85 {
            return .stay
        }

        let x = subject.centerX
        let y = subject.centerY

        // 方向语义统一为「手机应该往哪移」（与 MoveDirection.displayName 一致）：
        // 手机往右移 → 画面内容相对往左移；要主体在画面中右移，手机需往左移。
        // 判断主要调整方向
        // 优先看边缘距离问题（太靠边的话先解决）
        if subject.minX < minAcceptableEdgeMargin {
            return .moveLeft   // 人物太靠左 → 手机往左移，画面内容右移把人物带回来
        }
        if subject.maxX > 1.0 - minAcceptableEdgeMargin {
            return .moveRight  // 人物太靠右 → 手机往右移
        }
        if subject.minY < minAcceptableEdgeMargin {
            return .moveDown   // 人物太靠下（脚被裁）→ 手机往下移，画面内容上移
        }
        if subject.maxY > 1.0 - minAcceptableEdgeMargin {
            return .moveUp     // 人物太靠上（头被裁）→ 手机往上移
        }

        // 边缘没问题，看位置优化
        // 向最近的三分点方向移动
        let leftThird: CGFloat = 1.0 / 3.0
        let rightThird: CGFloat = 2.0 / 3.0
        let topThird: CGFloat = 2.0 / 3.0
        let bottomThird: CGFloat = 1.0 / 3.0

        let distToLeftThird = abs(x - leftThird)
        let distToRightThird = abs(x - rightThird)
        let distToTopThird = abs(y - topThird)
        let distToBottomThird = abs(y - bottomThird)
        let distToCenterX = abs(x - 0.5)
        let distToCenterY = abs(y - 0.5)

        // 找出偏差最大的方向
        let xDeviation = min(distToLeftThird, distToRightThird, distToCenterX)
        let yDeviation = min(distToTopThird, distToBottomThird, distToCenterY)

        if xDeviation > yDeviation {
            // X 方向偏差更大
            if x < 0.5 {
                return .moveLeft   // 人物偏左 → 手机左移
            } else {
                return .moveRight  // 人物偏右 → 手机右移
            }
        } else {
            // Y 方向偏差更大（注意：检测坐标 Y 轴向上，y 小 = 画面下方）
            if y < 0.5 {
                return .moveDown   // 人物偏下 → 手机下移，内容上移
            } else {
                return .moveUp     // 人物偏上 → 手机上移，内容下移
            }
        }
    }

    // MARK: - 推荐：镜头

    /// 计算推荐的镜头/焦段
    private func calculateRecommendedLens(
        subject: DetectedObject,
        sizeScore: Int,
        currentZoom: CGFloat
    ) -> LensRecommendation {

        let height = subject.height
        let ideal = idealPersonHeightRatio

        // 如果大小得分已经很高，保持当前
        if sizeScore >= 85 {
            return .keepCurrent
        }

        // 人物太小 → 推荐更大的变焦（长焦）
        // 阈值留出 ±30% 滞回带：太贴近理想值会在"推长焦/拉广角"之间来回振荡
        if height < ideal * 0.7 {
            if currentZoom < 1.5 {
                return .telephoto2x
            } else if currentZoom < 2.5 {
                return .telephoto3x
            } else {
                return .telephoto5x
            }
        }

        // 人物太大 → 推荐更小的变焦（广角）
        if height > ideal * 1.3 {
            if currentZoom > 2.5 {
                return .telephoto2x
            } else if currentZoom > 1.5 {
                return .wide
            } else {
                return .ultraWide
            }
        }

        return .keepCurrent
    }

    // MARK: - 推荐：相机高度

    /// 计算推荐的相机高度调整
    private func calculateRecommendedCameraHeight(
        person: DetectedObject,
        face: DetectedObject?,
        headRoomScore: Int
    ) -> CameraHeightAdjustment {

        // 如果头顶留白得分已经很高，保持水平
        if headRoomScore >= 85 {
            return .eyeLevel
        }

        let headRoom: CGFloat
        if let face = face {
            headRoom = 1.0 - face.maxY
        } else {
            headRoom = 1.0 - person.maxY
        }

        // 头顶留白太少（头顶快顶到画面上沿了）
        // → 相机往上抬一点（或者说手机举高），让人物往下一点，留白变多
        if headRoom < idealHeadRoomRatio * 0.6 {
            return .higher
        }

        // 头顶留白太多（画面上方太空了）
        // → 相机放低一点，让人物往上一点，留白变少
        if headRoom > idealHeadRoomRatio * 1.8 {
            return .lower
        }
        
        return .eyeLevel
    }
    
    // MARK: - 生成目标构图
    
    /// 根据当前构图结果，生成理想的目标构图
    /// - Parameter current: 当前构图结果
    /// - Returns: 目标构图状态
    ///
    /// 设计思路：
    /// 1. 位置：选最近的三分点（不是永远左三分，看哪边更合理）
    /// 2. 大小：理想高度 0.75，宽度 0.4
    /// 3. 头顶留白：理想 12%
    /// 4. 目标分数：预计可达 85~90 分
    func generateTarget(from current: CompositionResult) -> CompositionTarget {
        let person = current.person
        
        // 如果没检测到人，给一个默认的中心构图目标
        guard person.detected else {
            return CompositionTarget(
                targetCenterX: 0.5,
                targetCenterY: 0.5,
                targetWidthRatio: 0,
                targetHeightRatio: 0,
                targetHeadRoom: idealHeadRoomRatio,
                preferredLens: .keepCurrent,
                compositionStyle: .center,
                targetScore: 80,
                adviceTitle: "等待主体",
                adviceText: "将人物纳入画面",
                suggestedStyle: "风景"
            )
        }
        
        // 1. 计算目标位置（选最近的三分点）
        let targetX = nearestThirdX(for: person.centerX)
        let targetY = idealVerticalPosition(personCenterY: person.centerY)
        
        // 2. 目标大小
        let targetHeight = idealPersonHeightRatio
        let targetWidth = idealPersonWidthRatio
        
        // 3. 目标头顶留白
        let targetHeadRoom = idealHeadRoomRatio
        
        // 4. 推荐镜头
        let recommendedLens = current.recommendedLens
        
        // 5. 目标构图风格
        let targetStyle: CompositionType
        if abs(targetX - 0.5) < 0.06 {
            targetStyle = .center
        } else {
            targetStyle = .ruleOfThirds
        }
        
        // 6. 预计目标分数（理想状态下的分数）
        let targetScore = 88
        
        return CompositionTarget(
            targetCenterX: targetX,
            targetCenterY: targetY,
            targetWidthRatio: targetWidth,
            targetHeightRatio: targetHeight,
            targetHeadRoom: targetHeadRoom,
            preferredLens: recommendedLens,
            compositionStyle: targetStyle,
            targetScore: targetScore,
            adviceTitle: "调整构图",
            adviceText: "移动手机对齐目标",
            suggestedStyle: "电影感"
        )
    }
    
    /// 找到最近的三分线 X 坐标
    private func nearestThirdX(for currentX: CGFloat) -> CGFloat {
        let leftThird: CGFloat = 1.0 / 3.0
        let rightThird: CGFloat = 2.0 / 3.0
        let center: CGFloat = 0.5
        
        let dLeft = abs(currentX - leftThird)
        let dRight = abs(currentX - rightThird)
        let dCenter = abs(currentX - center)
        
        // 如果已经很接近某个点了，就保持那个点
        if min(dLeft, dRight, dCenter) < 0.06 {
            if dLeft < dRight && dLeft < dCenter { return leftThird }
            if dRight < dLeft && dRight < dCenter { return rightThird }
            return center
        }
        
        // 否则选最近的
        if dLeft < dRight && dLeft < dCenter { return leftThird }
        if dRight < dLeft && dRight < dCenter { return rightThird }
        return center
    }
    
    /// 计算理想的垂直位置
    private func idealVerticalPosition(personCenterY: CGFloat) -> CGFloat {
        // 人像通常眼睛在画面上 1/3 处
        // 人物中心大约在 0.55~0.6 之间
        return 0.58
    }
}

#endif
