//
//  CompositionResult.swift
//  FrameHero
//
//  构图分析结果数据模型
//
//  ## 文件作用
//  定义统一的构图分析结果数据结构，作为 Vision 检测 → 构图引擎 → AI 建议 → UI 显示之间的通用数据模型。
//  本模型与具体 UI 框架、AI API 完全解耦，只负责数据承载。
//
//  ## 设计原则
//  1. 纯数据模型，不包含业务逻辑
//  2. 所有坐标使用归一化值 [0, 1]，便于在不同分辨率间复用
//  3. 可选值（Optional）表示该信息可能不存在（例如没检测到人）
//  4. 分项评分都在 0~100 范围内，总分也在 0~100 范围内
//
//  ## 主要类型
//
//  ### CompositionResult
//  完整的构图分析结果，包含：
//  - 总分与各分项得分
//  - 人物检测信息
//  - 构图类型判断
//  - 推荐调整方向
//
//  ### CompositionScore
//  分项评分明细，便于解释"为什么这个分数"
//
//  ### PersonInfo
//  人物检测的详细信息
//
//  ### 各种枚举
//  SubjectPosition / CompositionType / MoveDirection / LensRecommendation
//
//  ## 使用流程
//  VisionAnalyzer → 生成原始检测数据
//      ↓
//  CompositionEngine → 计算生成 CompositionResult
//      ↓
//  DeepSeekService / MockPhotographer → 基于此生成自然语言建议
//      ↓
//  UI → 展示评分和建议
//

import Foundation
import CoreGraphics

#if os(iOS)

// MARK: - 主体位置枚举

/// 主体在画面中的大致位置
enum SubjectPosition: String, CaseIterable, Identifiable {
    case center           // 正中心
    case leftThird        // 左三分线
    case rightThird       // 右三分线
    case topThird         // 上三分线
    case bottomThird      // 下三分线
    case topLeft          // 左上
    case topRight         // 右上
    case bottomLeft       // 左下
    case bottomRight      // 右下
    case leftEdge         // 靠左边缘
    case rightEdge        // 靠右边缘
    case unknown          // 无法判断

    var id: String { rawValue }

    /// 人类可读的中文描述
    var displayName: String {
        switch self {
        case .center:       return "画面中心"
        case .leftThird:    return "左侧三分线"
        case .rightThird:   return "右侧三分线"
        case .topThird:     return "上方三分线"
        case .bottomThird:  return "下方三分线"
        case .topLeft:      return "左上角"
        case .topRight:     return "右上角"
        case .bottomLeft:   return "左下角"
        case .bottomRight:  return "右下角"
        case .leftEdge:     return "靠左边缘"
        case .rightEdge:    return "靠右边缘"
        case .unknown:      return "未知"
        }
    }
}

// MARK: - 构图类型枚举

/// 大致的构图类型判断
enum CompositionType: String, CaseIterable, Identifiable {
    case center           // 中心构图
    case ruleOfThirds     // 三分法构图
    case symmetry         // 对称构图
    case leadingRoom      // 前视空间（人物朝向一侧留白更多）
    case headroomIssue    // 头顶留白问题（太多或太少）
    case edgeCropping     // 边缘裁切问题（人物太靠边）
    case unknown          // 无法判断

    var id: String { rawValue }

    /// 人类可读的中文描述
    var displayName: String {
        switch self {
        case .center:          return "中心构图"
        case .ruleOfThirds:    return "三分法构图"
        case .symmetry:        return "对称构图"
        case .leadingRoom:     return "前视空间"
        case .headroomIssue:   return "头顶留白问题"
        case .edgeCropping:    return "边缘裁切问题"
        case .unknown:         return "未知构图"
        }
    }
}

// MARK: - 移动方向枚举

/// 推荐的手机移动方向
enum MoveDirection: String, CaseIterable, Identifiable {
    case moveUp           // 手机往上移（画面往下移）
    case moveDown         // 手机往下移（画面往上移）
    case moveLeft         // 手机往左移（画面往右移）
    case moveRight        // 手机往右移（画面往左移）
    case moveCloser       // 靠近一点（放大）
    case moveFarther      // 远离一点（缩小）
    case stay             // 保持不动
    case unknown          // 未知

    var id: String { rawValue }

    /// 人类可读的中文描述
    var displayName: String {
        switch self {
        case .moveUp:       return "手机往上一点"
        case .moveDown:     return "手机往下一点"
        case .moveLeft:     return "手机往左一点"
        case .moveRight:    return "手机往右一点"
        case .moveCloser:   return "靠近一点"
        case .moveFarther:  return "再退一点"
        case .stay:         return "保持不动"
        case .unknown:      return "待分析"
        }
    }
}

// MARK: - 推荐镜头枚举

/// 推荐使用的镜头/焦段
enum LensRecommendation: String, CaseIterable, Identifiable {
    case ultraWide        // 超广角 0.5x
    case wide             // 广角 1x
    case telephoto2x      // 2x 长焦
    case telephoto3x      // 3x 长焦
    case telephoto5x      // 5x 长焦
    case keepCurrent      // 保持当前镜头
    case unknown          // 未知

    var id: String { rawValue }

    /// 人类可读的中文描述
    var displayName: String {
        switch self {
        case .ultraWide:    return "0.5× 超广角"
        case .wide:         return "1× 广角"
        case .telephoto2x:  return "2× 长焦"
        case .telephoto3x:  return "3× 长焦"
        case .telephoto5x:  return "5× 长焦"
        case .keepCurrent:  return "保持当前焦段"
        case .unknown:      return "待分析"
        }
    }
}

// MARK: - 相机高度建议

/// 推荐的相机高度调整
enum CameraHeightAdjustment: String, CaseIterable, Identifiable {
    case lower            // 放低一点（仰拍视角）
    case higher           // 举高一点（俯拍视角）
    case eyeLevel         // 保持视线水平
    case unknown          // 未知

    var id: String { rawValue }

    /// 人类可读的中文描述
    var displayName: String {
        switch self {
        case .lower:      return "放低一点"
        case .higher:     return "举高一点"
        case .eyeLevel:   return "保持水平"
        case .unknown:    return "待分析"
        }
    }
}

// MARK: - 人物信息

/// 检测到的人物信息
/// 所有坐标均为归一化值 [0, 1]，相对于画面尺寸
struct PersonInfo {
    /// 是否检测到人物
    var detected: Bool = false

    /// 人物 bounding box 中心点 X（归一化 0~1，0=左，1=右）
    var centerX: CGFloat = 0

    /// 人物 bounding box 中心点 Y（归一化 0~1，0=下，1=上）
    var centerY: CGFloat = 0

    /// 人物宽度占画面宽度的比例（归一化 0~1）
    var widthRatio: CGFloat = 0

    /// 人物高度占画面高度的比例（归一化 0~1）
    var heightRatio: CGFloat = 0

    /// 人脸 bounding box 中心点 X（归一化，未检测到则为 nil）
    var faceCenterX: CGFloat?

    /// 人脸 bounding box 中心点 Y（归一化，未检测到则为 nil）
    var faceCenterY: CGFloat?

    /// 人脸宽度比例（归一化，未检测到则为 nil）
    var faceWidthRatio: CGFloat?

    /// 头顶留白比例（头顶到画面顶部的距离 / 画面高度）
    /// 值越大，头顶留白越多
    var headRoom: CGFloat = 0

    /// 人物是否完整（没有被画面边缘裁切）
    var isFullBody: Bool = false

    /// 检测置信度 0~1
    var confidence: Float = 0
}

// MARK: - 分项评分

/// 构图分项评分明细，每项 0~100 分
struct CompositionScore {
    /// 总分 0~100
    var total: Int = 0

    /// 人物位置得分 0~100（人物在画面中的位置是否合理）
    var positionScore: Int = 0

    /// 人物大小得分 0~100（人物在画面中的占比是否合适）
    var sizeScore: Int = 0

    /// 头顶留白得分 0~100（头顶空间是否舒适）
    var headRoomScore: Int = 0

    /// 边缘距离得分 0~100（人物是否太靠近画面边缘）
    var edgeDistanceScore: Int = 0

    /// 主体完整度得分 0~100（人物是否被边缘裁切）
    var subjectIntegrityScore: Int = 0
}

// MARK: - 完整构图结果

/// 完整的构图分析结果
///
/// 这是 Vision 检测 + 构图引擎计算后的最终输出，
/// 可以直接传给 UI 展示，也可以传给 AI 服务生成自然语言建议。
struct CompositionResult {

    // MARK: - 评分

    /// 综合评分（0~100）
    var score: Int = 0

    /// 分项评分明细
    var scoreBreakdown = CompositionScore()

    // MARK: - 人物信息

    /// 人物检测信息
    var person = PersonInfo()

    /// 检测到的人脸数量
    var faceCount: Int = 0

    /// 检测到的人体数量
    var bodyCount: Int = 0

    // MARK: - 构图判断

    /// 主体位置
    var subjectPosition: SubjectPosition = .unknown

    /// 构图类型判断
    var compositionType: CompositionType = .unknown

    // MARK: - 推荐调整

    /// 推荐移动方向（手机应该怎么移）
    var recommendedMove: MoveDirection = .unknown

    /// 推荐使用的镜头
    var recommendedLens: LensRecommendation = .unknown

    /// 推荐相机高度调整
    var recommendedCameraHeight: CameraHeightAdjustment = .unknown

    // MARK: - 其他信息

    /// 整体置信度 0~1
    var confidence: Float = 0

    /// 当前使用的检测模式（用于调试显示）
    var detectionMode: String = ""

    /// 当前变焦倍率（例如 1.0, 2.0）
    var currentZoomFactor: CGFloat = 1.0

    /// 当前等效焦距（例如 24mm）
    var currentFocalLength: Int = 0

    /// 时间戳（用于调试和性能分析）
    var timestamp: TimeInterval = Date().timeIntervalSince1970
}

#endif
