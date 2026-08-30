//
//  CompositionPlan.swift
//  FrameHero
//
//  构图方案（Composition Plan）—— AI 摄影师的核心输出
//
//  ## 设计（MVP 方案）
//  AI 不输出自然语言，输出**结构化方案**：
//  标题 / 风格词 / 构图类型 / 目标主体位置 / 距离建议 / 焦段建议 / 置信度
//
//  ## AI 与本地分工
//  - `CompositionPlanProviding` 协议：方案从哪来
//    - MVP：`LocalHeuristicPlanProvider`（本地启发式，基于场景 + 主体快照，
//      零网络零延迟，离线可用）
//    - 后续：接入 VLM（Qwen-VL 等）时实现同一协议，用一次图片请求
//      换取更懂场景的方案（AI 只在用户点「AI 构图」时调用一次）
//  - 实时跟踪/完成判断/Overlay 全部本地，不依赖 AI
//
//  ## 坐标约定
//  subjectTarget 采用「屏幕直觉」坐标：x 0=左 1=右，y 0=顶 1=底。
//  构图引擎内部是 y 向上（0=下），选中方案时做 1-y 转换。
//

import Foundation
import CoreGraphics

// MARK: - 构图类型

/// MVP 支持的构图类型
enum PlanCompositionStyle: String, Codable, CaseIterable {
    case ruleOfThirds       = "rule_of_thirds"       // 三分法
    case centerSymmetry     = "center_symmetry"      // 居中对称
    case leadingLines       = "leading_lines"        // 引导线
    case framing            = "framing"              // 框架构图
    case foregroundLayering = "foreground_layering"  // 前景层次
    case negativeSpace      = "negative_space"       // 留白
    case environmentPortrait = "environment_portrait" // 人物环境构图

    /// 方案标题里的构图描述
    var displayName: String {
        switch self {
        case .ruleOfThirds: return "三分法构图"
        case .centerSymmetry: return "居中对称"
        case .leadingLines: return "引导线构图"
        case .framing: return "框架构图"
        case .foregroundLayering: return "前景层次"
        case .negativeSpace: return "留白构图"
        case .environmentPortrait: return "人物环境构图"
        }
    }
}

// MARK: - 方案距离

/// 相对当前的距离建议
enum PlanDistance: String, Codable {
    case closer     // 靠近
    case keep       // 保持
    case farther    // 远离
}

// MARK: - 跟踪方式

/// 方案的实时跟踪方式（本地执行）
enum PlanTracking: String, Codable {
    case person     // 人物检测跟踪（Vision 人脸/人体）
    case saliency   // 显著性区域跟踪（Vision 注意力显著性）
    case none       // 无跟踪（静态目标，如正对文档）
}

// MARK: - 构图方案

struct CompositionPlan: Identifiable, Equatable {
    let id: UUID

    /// 方案标题（如"人物与建筑"）
    var title: String
    /// 风格词（如"电影感"/"突出人物"/"空间感"）
    var styleWord: String
    /// 一句话说明（如"让人物与建筑形成层次感"）
    var detail: String

    /// 构图类型
    var composition: PlanCompositionStyle
    /// 目标主体位置（x 0=左 1=右；y 0=顶 1=底）
    var subjectTarget: CGPoint
    /// 距离建议
    var distance: PlanDistance
    /// 焦段建议（展示 + 变焦盘高亮，如 "2x"/"0.5x"；nil = 保持当前）
    var focalHint: String?
    /// 实时跟踪方式
    var tracking: PlanTracking
    /// 置信度 0~1
    var confidence: Double
}

// MARK: - 方案提供协议

/// 构图方案提供方。
/// 实时跟踪不在此协议内——方案确定后，跟踪/完成判断全部本地执行。
protocol CompositionPlanProviding {
    /// 基于一次场景快照生成 1~3 个构图方案（按推荐度排序）
    func generatePlans(scene: SceneClassifier.SceneKind,
                       person: PersonInfo?,
                       zoomFactor: CGFloat,
                       hasTelephoto: Bool,
                       hasUltraWide: Bool) -> [CompositionPlan]
}

// MARK: - 本地启发式方案生成器（MVP 默认实现）

/// 本地启发式「AI 摄影师」：
/// 用场景类型 + 主体快照（有无人物、占比、朝向）推导构图方案。
/// 规则来自经典摄影法（三分/留白/景别），确定性输出、可离线。
struct LocalHeuristicPlanProvider: CompositionPlanProviding {

    func generatePlans(scene: SceneClassifier.SceneKind,
                       person: PersonInfo?,
                       zoomFactor: CGFloat,
                       hasTelephoto: Bool,
                       hasUltraWide: Bool) -> [CompositionPlan] {
        if let person, person.detected {
            return plansForPerson(person: person, hasTelephoto: hasTelephoto)
        }
        return plansForScene(scene, hasUltraWide: hasUltraWide)
    }

    // MARK: 有人物：按人物占比分景别出方案

    private func plansForPerson(person: PersonInfo, hasTelephoto: Bool) -> [CompositionPlan] {
        let height = person.heightRatio
        var plans: [CompositionPlan] = []

        // 方案一：三分法 / 前视空间（尊重脸朝向选边，与目标锁定规则一致）
        let thirdX = leadingRoomThirdX(for: person)
        plans.append(CompositionPlan(
            id: UUID(),
            title: "人物与环境",
            styleWord: "空间感",
            detail: "把人物放在三分点上，画面更透气",
            composition: height < 0.45 ? .environmentPortrait : .ruleOfThirds,
            subjectTarget: CGPoint(x: thirdX, y: 0.46),
            distance: .keep,
            focalHint: nil,
            tracking: .person,
            confidence: 0.92
        ))

        // 方案二：特写（占比较小时才有意义）
        if height < 0.62 {
            plans.append(CompositionPlan(
                id: UUID(),
                title: "人物特写",
                styleWord: "突出人物",
                detail: "靠近一些，让人物撑满画面重心",
                composition: .centerSymmetry,
                subjectTarget: CGPoint(x: 0.5, y: 0.44),
                distance: .closer,
                focalHint: hasTelephoto ? "2x" : nil,
                tracking: .person,
                confidence: 0.82
            ))
        }

        // 方案三：留白（人物偏一侧，另一侧大面积留白）
        let opposite: CGFloat = thirdX < 0.5 ? 2.0 / 3.0 : 1.0 / 3.0
        plans.append(CompositionPlan(
            id: UUID(),
            title: "大面积留白",
            styleWord: "极简",
            detail: "人物靠边，让另一侧留白呼吸",
            composition: .negativeSpace,
            subjectTarget: CGPoint(x: opposite, y: 0.42),
            distance: .farther,
            focalHint: nil,
            tracking: .person,
            confidence: 0.74
        ))

        return plans
    }

    /// 前视空间三分点：脸朝右 → 左三分点（留视线空间）
    private func leadingRoomThirdX(for person: PersonInfo) -> CGFloat {
        if let faceX = person.faceCenterX {
            let facing = faceX - person.centerX
            if facing > 0.015 { return 1.0 / 3.0 }
            if facing < -0.015 { return 2.0 / 3.0 }
        }
        if abs(person.centerX - 0.5) < 0.05 { return 2.0 / 3.0 }
        let left = 1.0 / 3.0, right = 2.0 / 3.0
        return abs(person.centerX - left) <= abs(person.centerX - right) ? left : right
    }

    // MARK: 无人物：按场景出方案（显著性跟踪）

    private func plansForScene(_ scene: SceneClassifier.SceneKind, hasUltraWide: Bool) -> [CompositionPlan] {
        switch scene {
        case .food:
            return [
                plan("45° 俯拍", "食欲感", "从上往下 45°，食物质感最突出",
                     .centerSymmetry, CGPoint(x: 0.5, y: 0.55), .closer, nil, confidence: 0.9),
                plan("桌面层次", "前景层次", "让前景餐具入画，与食物拉开层次",
                     .foregroundLayering, CGPoint(x: 0.36, y: 0.6), .keep, nil, confidence: 0.78),
                plan("特写质感", "微距", "贴近拍食物质地，虚化背景",
                     .centerSymmetry, CGPoint(x: 0.5, y: 0.5), .closer, nil, confidence: 0.72),
            ]

        case .landscape:
            var plans = [
                plan("水平线三分", "开阔", "让地平线压在三分线上，天空与地面取舍分明",
                     .ruleOfThirds, CGPoint(x: 0.5, y: 0.62), .keep, nil, confidence: 0.88),
                plan("前景层次", "纵深", "找一株草或一块石头做前景，画面立刻立体",
                     .foregroundLayering, CGPoint(x: 0.34, y: 0.68), .keep,
                     hasUltraWide ? "0.5x" : nil, confidence: 0.76),
            ]
            plans.append(plan("居中安定", "对称", "主体居中，画面平稳安静",
                              .centerSymmetry, CGPoint(x: 0.5, y: 0.5), .keep, nil, confidence: 0.68))
            return plans

        case .street:
            return [
                plan("引导线纵深", "电影感", "顺着街道/建筑线条把视线引向主体",
                     .leadingLines, CGPoint(x: 0.62, y: 0.52), .keep, nil, confidence: 0.86),
                plan("三分抓拍", "纪实", "主体放三分点，环境讲故事",
                     .ruleOfThirds, CGPoint(x: 0.34, y: 0.5), .keep, nil, confidence: 0.8),
                plan("框架构图", "聚焦", "借门窗/拱廊做框，把主体框进去",
                     .framing, CGPoint(x: 0.5, y: 0.52), .keep, nil, confidence: 0.72),
            ]

        case .night:
            return [
                plan("光源层次", "氛围感", "以最亮的光源为视觉锚点",
                     .ruleOfThirds, CGPoint(x: 0.62, y: 0.42), .keep, nil, confidence: 0.84),
                plan("剪影三分", "戏剧感", "主体压暗成剪影，放三分点",
                     .ruleOfThirds, CGPoint(x: 0.34, y: 0.55), .keep, nil, confidence: 0.74),
                plan("居中光源", "对称", "让光源居中，反射对称",
                     .centerSymmetry, CGPoint(x: 0.5, y: 0.5), .keep, nil, confidence: 0.68),
            ]

        case .document:
            return [
                plan("正对文档", "清晰", "镜头正对文档，边框保持平直",
                     .centerSymmetry, CGPoint(x: 0.5, y: 0.5), .keep, nil, confidence: 0.92),
                plan("填满画面", "饱满", "靠近让文档占满画面，减少杂物入镜",
                     .centerSymmetry, CGPoint(x: 0.5, y: 0.5), .closer, nil, confidence: 0.8),
            ]

        case .portrait, .generic:
            return [
                plan("三分兴趣点", "经典", "把画面兴趣点放在三分交叉点",
                     .ruleOfThirds, CGPoint(x: 2.0 / 3.0, y: 0.44), .keep, nil, confidence: 0.8),
                plan("居中对称", "安定", "主体居中，强调对称与秩序",
                     .centerSymmetry, CGPoint(x: 0.5, y: 0.5), .keep, nil, confidence: 0.72),
                plan("大面积留白", "极简", "主体靠边，大面留白让画面安静",
                     .negativeSpace, CGPoint(x: 1.0 / 3.0, y: 0.42), .keep, nil, confidence: 0.66),
            ]
        }
    }

    private func plan(_ title: String, _ style: String, _ detail: String,
                      _ composition: PlanCompositionStyle, _ target: CGPoint,
                      _ distance: PlanDistance, _ focal: String?,
                      confidence: Double) -> CompositionPlan {
        CompositionPlan(
            id: UUID(),
            title: title,
            styleWord: style,
            detail: detail,
            composition: composition,
            subjectTarget: target,
            distance: distance,
            focalHint: focal,
            tracking: .saliency,
            confidence: confidence
        )
    }
}
