//
//  SceneClassifier.swift
//  FrameHero
//
//  场景识别器：AI 构图的"场景脑"
//
//  ## 设计
//  - 用 Vision 系统分类器 VNClassifyImageRequest（1030+ 类、离线、零延迟）
//    对取景帧做粗粒度场景分类
//  - 多帧投票 + 置信度阈值 + 滞回：单帧误判不会抖动场景结论，
//    场景切换需要连续证据才成立
//  - 识别结果驱动：构图配方选择 + 相机参数预设 + 引导文案
//
//  ## 后续演进
//  需要更细的场景粒度（樱花 vs 玫瑰）时，把 VNClassifyImageRequest
//  换成专用 CoreML 场景模型即可，上层接口不变
//

import Foundation
import Vision
import CoreVideo

#if os(iOS)

final class SceneClassifier {

    // MARK: - 场景类型

    enum SceneKind: String, Equatable {
        case portrait       // 人像
        case food           // 美食
        case night          // 夜景
        case landscape      // 风景
        case street         // 街拍/建筑
        case document       // 文档/白板
        case generic        // 通用

        /// 场景显示名（建议 chip 前缀）
        var displayName: String {
            switch self {
            case .portrait: return "人像场景"
            case .food: return "美食场景"
            case .night: return "夜景场景"
            case .landscape: return "风景场景"
            case .street: return "街拍场景"
            case .document: return "文档场景"
            case .generic: return ""
            }
        }

        /// 场景默认构图指令（没有主体检测数据时也有的兜底建议）
        var defaultInstruction: String {
            switch self {
            case .portrait: return "把人物放在三分线交叉点附近"
            case .food: return "试试 45° 俯拍，突出食物质感"
            case .night: return "稳住手机，让画面充分曝光"
            case .landscape: return "用水平线作参照，保持画面平稳"
            case .street: return "寻找前景与纵深感，主体避开边缘"
            case .document: return "正对文档，保持边框平直"
            case .generic: return "把主体放在三分线交叉点附近"
            }
        }
    }

    struct Decision: Equatable {
        let kind: SceneKind
        let confidence: Float
    }

    // MARK: - 配置

    /// 单帧识别置信度门槛
    private let perFrameThreshold: Float = 0.25
    /// 投票窗口内的最少帧数（达到后才产出结论）
    private let minVotesToDecide = 4
    /// 投票窗口大小（滑动窗口，超出即丢弃）
    private let windowSize = 8
    /// 场景结论切换滞回：新场景票数需超过当前场景票数的该比例才切换
    private let switchHysteresis: Float = 1.5

    // MARK: - 状态

    /// votes / currentDecision 专属串行队列：
    /// classify() 跑在相机帧回调的 videoOutputQueue 上，reset() 由主线程 UI 操作触发，
    /// 两者必须通过同一条队列互斥，否则对 votes/currentDecision 的并发读写是数据竞争。
    private let stateQueue = DispatchQueue(label: "framehero.sceneclassifier.state")

    /// 滑动投票窗口：(场景, 时间戳)，仅在 stateQueue 上读写
    private var votes: [(kind: SceneKind, time: TimeInterval)] = []
    /// 当前稳定结论（滞回锚点），仅在 stateQueue 上读写
    private var currentDecision: Decision?

    // MARK: - 识别

    /// 对单帧做分类并累积投票。
    /// - Parameter completion: 主线程回调；窗口未成熟时传 nil
    func classify(_ pixelBuffer: CVPixelBuffer,
                  orientation: CGImagePropertyOrientation,
                  completion: @escaping (Decision?) -> Void) {
        let request = VNClassifyImageRequest { [weak self] vnRequest, error in
            guard let self else { return }
            guard error == nil,
                  let observations = vnRequest.results as? [VNClassificationObservation] else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let decision = self.stateQueue.sync { self.accumulate(observations: observations) }
            DispatchQueue.main.async { completion(decision) }
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            DispatchQueue.main.async { completion(nil) }
        }
    }

    /// 会话重置（重新开始一轮识别），可能从主线程调用，必须与 classify() 互斥
    func reset() {
        stateQueue.sync {
            votes.removeAll()
            currentDecision = nil
        }
    }

    // MARK: - 投票

    private func accumulate(observations: [VNClassificationObservation]) -> Decision? {
        let now = Date().timeIntervalSince1970

        // 单帧：取置信度最高且过了门槛的映射场景
        var best: (SceneKind, Float)?
        for obs in observations where obs.confidence >= perFrameThreshold {
            if let kind = Self.sceneKind(for: obs.identifier) {
                if best == nil || obs.confidence > best!.1 {
                    best = (kind, obs.confidence)
                }
            }
        }
        if let best {
            votes.append((best.0, now))
        }

        // 裁剪滑动窗口（按条数 + 3 秒有效期）
        while votes.count > windowSize { votes.removeFirst() }
        votes.removeAll { now - $0.time > 3.0 }

        guard votes.count >= minVotesToDecide else { return currentDecision }

        // 统计票数
        var counts: [SceneKind: Int] = [:]
        for v in votes { counts[v.kind, default: 0] += 1 }
        let ranked = counts.sorted { $0.value > $1.value }
        guard let top = ranked.first else { return currentDecision }

        // 滞回：与当前结论不同时，需要明显占优才切换
        if let current = currentDecision {
            if top.key == current.kind { return current }
            let currentVotes = counts[current.kind] ?? 0
            if Float(top.value) >= Float(currentVotes) * switchHysteresis {
                let decision = Decision(kind: top.key,
                                        confidence: Float(top.value) / Float(votes.count))
                currentDecision = decision
                return decision
            }
            return current
        }

        let decision = Decision(kind: top.key,
                                confidence: Float(top.value) / Float(votes.count))
        currentDecision = decision
        return decision
    }

    // MARK: - 类别映射

    /// Vision 分类标识 → 场景类型（关键词匹配，从粗到细）
    private static func sceneKind(for identifier: String) -> SceneKind? {
        let id = identifier.lowercased()

        // 文档类
        if id.contains("document") || id.contains("whiteboard") || id.contains("text")
            || id.contains("receipt") || id.contains("menu_") {
            return .document
        }
        // 美食类
        if id.contains("food") || id.contains("dish") || id.contains("cuisine")
            || id.contains("dessert") || id.contains("fruit") || id.contains("coffee")
            || id.contains("tea") || id.contains("meal") {
            return .food
        }
        // 夜景类（ supplemented by brightness heuristics at the caller side）
        if id.contains("night") || id.contains("neon") || id.contains("starry") {
            return .night
        }
        // 人像类
        if id.contains("people") || id.contains("person") || id.contains("portrait")
            || id.contains("face") || id.contains("crowd") || id.contains("child")
            || id.contains("selfie") {
            return .portrait
        }
        // 风景类
        if id.contains("mountain") || id.contains("sea") || id.contains("ocean")
            || id.contains("sky") || id.contains("sunset") || id.contains("sunrise")
            || id.contains("beach") || id.contains("lake") || id.contains("forest")
            || id.contains("field") || id.contains("landscape") || id.contains("valley")
            || id.contains("waterfall") || id.contains("snow") {
            return .landscape
        }
        // 街拍/建筑类
        if id.contains("building") || id.contains("street") || id.contains("city")
            || id.contains("architecture") || id.contains("bridge") || id.contains("road")
            || id.contains("urban") || id.contains("alley") {
            return .street
        }
        return nil
    }
}

#endif
