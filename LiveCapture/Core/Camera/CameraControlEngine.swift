//
//  CameraControlEngine.swift
//  LiveCapture
//
//  相机控制引擎
//
//  ## 设计理念
//  AI 不直接输出 ISO=xxx / Shutter=xxx，
//  因为 AI 不知道当前设备的真实能力范围。
//
//  CameraControlEngine 是中间翻译层：
//  输入：PhotographyStrategy（语义化偏好）
//  输出：实际硬件参数调用
//
//  ## 三态控制
//  每个参数独立支持：
//  - aiAuto: AI 自动调整 → Engine 计算并应用
//  - manual: 用户手动 → 直接用用户的值，AI 不改
//  - locked: 用户锁定 → 完全不动
//
//  ## Phase 1 范围
//  - 曝光控制（EV 偏差 + 曝光模式）
//
//  ## 后续扩展
//  - 对焦控制
//  - 白平衡控制
//  - 镜头/变焦控制
//

import Foundation
import AVFoundation

#if os(iOS)

/// 相机控制引擎
///
/// 负责将语义化的 PhotographyStrategy
/// 转换成当前设备实际支持的硬件参数，
/// 并调用 CameraManager 应用到相机。
final class CameraControlEngine {
    
    // MARK: - 属性
    
    /// 设备能力（决定参数范围）
    private var capability: CameraCapability
    
    /// 当前环境状态（用于计算最佳参数）
    private var environment: CameraEnvironment
    
    /// 相机管理器引用（弱引用避免循环）
    private weak var camera: CameraManager?

    // MARK: - 已下发状态（避免重复向硬件重放相同指令）
    // 反复 lockForConfiguration / 重设相同值会导致对焦 hunting、
    // 白平衡闪烁和曝光抖动——只在值真正变化时才下发。
    private var lastAppliedEV: Float?
    private var lastAppliedCustomISO: Float?
    private var lastAppliedCustomShutter: CMTime?
    private var lastAppliedFocusPOI: CGPoint?
    private var lastAppliedFocusAutoMode: Bool?
    private var lastAppliedFocusLens: Float?
    private var lastAppliedMacro: Bool = false
    private var lastAppliedWBTemp: Float?
    private var lastAppliedWBManual: Bool = false
    private var lastAppliedWBAuto: Bool = false
    private var lastAppliedZoom: CGFloat?
    /// AI 变焦切换的最小间隔：无滞回的连续切换会让画面忽大忽小
    private var lastLensApplyTime: Date?
    
    // MARK: - 初始化
    
    init(
        capability: CameraCapability = .empty,
        environment: CameraEnvironment = .empty,
        camera: CameraManager? = nil
    ) {
        self.capability = capability
        self.environment = environment
        self.camera = camera
    }
    
    // MARK: - 更新上下文
    
    /// 更新设备能力（切换摄像头时调用）
    func updateCapability(_ capability: CameraCapability) {
        self.capability = capability
    }
    
    /// 更新环境状态（参数变化时调用）
    func updateEnvironment(_ environment: CameraEnvironment) {
        self.environment = environment
    }
    
    /// 更新相机管理器引用
    func setCamera(_ camera: CameraManager) {
        self.camera = camera
    }
    
    // MARK: - 应用策略
    
    /// 应用摄影策略到相机
    ///
    /// 根据每个参数的 ControlMode 决定如何处理：
    /// - locked: 什么都不做
    /// - manual: 应用用户手动设置的值
    /// - aiAuto: 根据偏好计算并应用
    func applyStrategy(_ strategy: PhotographyStrategy) {
        guard let camera = camera else { return }
        
        // Phase 1: 曝光控制
        applyExposureStrategy(strategy, camera: camera)
        
        // Phase 2: 对焦控制
        applyFocusStrategy(strategy, camera: camera)
        
        // Phase 3: 白平衡控制
        applyWhiteBalanceStrategy(strategy, camera: camera)
        
        // Phase 4: 镜头/变焦策略
        applyLensStrategy(strategy, camera: camera)
    }
    
    // MARK: - 曝光策略实现
    
    private func applyExposureStrategy(
        _ strategy: PhotographyStrategy,
        camera: CameraManager
    ) {
        switch strategy.exposureControl {
        case .locked:
            // 用户锁定了曝光，什么都不做
            // （锁定状态下参数保持不变）
            break

        case .manual:
            // 用户手动模式：应用用户设置的 EV 值
            // 如果用户设置了自定义 ISO/快门，也一并应用
            if strategy.manualISO != nil || strategy.manualShutter != nil {
                let isoChanged = strategy.manualISO != lastAppliedCustomISO
                let shutterChanged = strategy.manualShutter != lastAppliedCustomShutter
                if isoChanged || shutterChanged {
                    camera.setCustomExposure(
                        iso: strategy.manualISO,
                        shutter: strategy.manualShutter
                    )
                    lastAppliedCustomISO = strategy.manualISO
                    lastAppliedCustomShutter = strategy.manualShutter
                    lastAppliedEV = nil
                }
            } else {
                // 仅手动 EV 偏移
                let bias = strategy.manualExposureBias
                if lastAppliedEV != bias {
                    camera.setExposureBias(bias)
                    lastAppliedEV = bias
                    lastAppliedCustomISO = nil
                    lastAppliedCustomShutter = nil
                }
            }

        case .aiAuto:
            // AI 自动模式：根据亮度偏好 + 环境计算最佳 EV
            let targetEV = calculateTargetEV(for: strategy)
            if lastAppliedEV != targetEV {
                camera.setExposureBias(targetEV)
                lastAppliedEV = targetEV
            }
        }
    }
    
    // MARK: - EV 计算
    
    /// 根据亮度偏好和当前环境计算目标 EV 偏移
    private func calculateTargetEV(for strategy: PhotographyStrategy) -> Float {
        var baseEV: Float = 0
        
        // 基础亮度偏好
        switch strategy.brightnessPreference {
        case .auto:
            baseEV = 0
        case .darker:
            baseEV = -0.3
        case .brighter:
            baseEV = +0.3
        case .preserveHighlights:
            // 保留高光：压暗曝光防止过曝
            baseEV = -0.7
        case .night:
            // 夜景模式：提亮，但要注意噪点
            baseEV = +1.0
        }
        
        // 根据当前环境微调
        // 如果已经是低光且 ISO 很高，夜景模式不要提太亮（避免噪点爆炸）
        if strategy.brightnessPreference == .night && environment.currentISO > 1600 {
            baseEV = min(baseEV, 0.5)
        }
        
        // 如果要保留高光但画面已经很暗，不要压太暗
        if strategy.brightnessPreference == .preserveHighlights && environment.brightness < 0.3 {
            baseEV = max(baseEV, -0.3)
        }
        
        // 钳位到设备支持范围
        let minEV = capability.minExposureBias
        let maxEV = capability.maxExposureBias
        return min(max(baseEV, minEV), maxEV)
    }
    
    // MARK: - 对焦策略实现
    
    private func applyFocusStrategy(
        _ strategy: PhotographyStrategy,
        camera: CameraManager
    ) {
        switch strategy.focusControl {
        case .locked:
            // 用户锁定了对焦，什么都不做
            break

        case .manual:
            // 用户手动模式：应用手动对焦位置
            if let position = strategy.manualFocusPosition {
                let rounded = (position * 200).rounded() / 200  // 0.5% 步进去抖
                if lastAppliedFocusLens != rounded {
                    camera.setManualFocusPosition(Float(rounded))
                    lastAppliedFocusLens = rounded
                    lastAppliedFocusPOI = nil
                    lastAppliedFocusAutoMode = nil
                    lastAppliedMacro = false
                }
            }

        case .aiAuto:
            // AI 自动模式：根据对焦偏好调整
            switch strategy.focusPreference {
            case .auto:
                // 自动追焦
                if lastAppliedFocusAutoMode != true {
                    camera.setFocusMode(.auto)
                    lastAppliedFocusAutoMode = true
                    lastAppliedFocusPOI = nil
                    lastAppliedMacro = false
                }

            case .subjectLock:
                // 锁定主体（如果有指定对焦点则锁定在那里）
                // 只在对焦点变化或刚进入该模式时下发，避免反复触发对焦
                let poi = strategy.focusPointOfInterest
                if poi != lastAppliedFocusPOI || lastAppliedFocusAutoMode != false {
                    if let poi = poi {
                        camera.setFocusPointOfInterest(poi)
                    }
                    camera.setFocusMode(.autoLocked)
                    lastAppliedFocusPOI = poi
                    lastAppliedFocusAutoMode = false
                    lastAppliedMacro = false
                }

            case .manual:
                // AI 偏好手动（一般不会出现，但做个 fallback）
                break

            case .macro:
                // 微距模式：对焦到最近（只下发一次）
                if !lastAppliedMacro {
                    camera.setManualFocusPosition(0.1)
                    lastAppliedMacro = true
                    lastAppliedFocusLens = 0.1
                    lastAppliedFocusPOI = nil
                    lastAppliedFocusAutoMode = nil
                }
            }
        }
    }
    
    // MARK: - 白平衡策略实现
    
    private func applyWhiteBalanceStrategy(
        _ strategy: PhotographyStrategy,
        camera: CameraManager
    ) {
        // 50K 步进取整，避免环境估算的微小抖动反复触发白平衡锁定
        func quantized(_ temp: Float) -> Float { (temp / 50).rounded() * 50 }

        switch strategy.whiteBalanceControl {
        case .locked:
            // 用户锁定了白平衡，什么都不做
            break

        case .manual:
            // 用户手动模式：应用手动色温
            if let temp = strategy.manualWhiteBalanceTemp {
                let rounded = quantized(temp)
                if lastAppliedWBTemp != rounded || !lastAppliedWBManual {
                    camera.setWhiteBalanceTemperature(rounded)
                    lastAppliedWBTemp = rounded
                    lastAppliedWBManual = true
                    lastAppliedWBAuto = false
                }
            }

        case .aiAuto:
            // AI 自动模式：根据白平衡偏好调整
            // 如果设备不支持自定义白平衡增益，所有非 auto 偏好都回退到 auto
            guard capability.supportsManualWhiteBalance else {
                if !lastAppliedWBAuto {
                    camera.setWhiteBalanceMode(.auto)
                    lastAppliedWBAuto = true
                    lastAppliedWBManual = false
                }
                return
            }

            switch strategy.whiteBalancePreference {
            case .auto:
                if !lastAppliedWBAuto {
                    camera.setWhiteBalanceMode(.auto)
                    lastAppliedWBAuto = true
                    lastAppliedWBManual = false
                }

            case .warm:
                // 暖色调：在自动基础上增加色温偏移
                applyAIColorTemperature(
                    quantized(environment.estimatedColorTemperature + 500),
                    camera: camera
                )

            case .cool:
                // 冷色调：在自动基础上减少色温偏移
                applyAIColorTemperature(
                    max(2500, quantized(environment.estimatedColorTemperature - 500)),
                    camera: camera
                )

            case .natural:
                // 自然真实：略微偏冷，让肤色更自然
                applyAIColorTemperature(
                    max(2500, quantized(environment.estimatedColorTemperature - 200)),
                    camera: camera
                )
            }
        }
    }

    /// AI 偏好下的色温下发（带去重）
    private func applyAIColorTemperature(_ temp: Float, camera: CameraManager) {
        if lastAppliedWBTemp != temp || lastAppliedWBAuto {
            camera.setWhiteBalanceTemperature(temp)
            lastAppliedWBTemp = temp
            lastAppliedWBManual = false
            lastAppliedWBAuto = false
        }
    }
    
    // MARK: - 镜头/变焦策略实现
    
    private func applyLensStrategy(
        _ strategy: PhotographyStrategy,
        camera: CameraManager
    ) {
        switch strategy.lensControl {
        case .locked:
            // 用户锁定了镜头/变焦，什么都不做
            break

        case .manual:
            // 用户手动模式：应用手动变焦倍率
            if let factor = strategy.manualZoomFactor {
                if lastAppliedZoom != factor {
                    camera.finalizeInteractiveZoom(at: factor, smooth: true)
                    lastAppliedZoom = factor
                }
            }

        case .aiAuto:
            // AI 自动模式：根据镜头偏好选择。
            // .auto = 保持当前变焦，绝不下发指令
            guard strategy.lensPreference != .auto else { return }

            // 冷却期：两次 AI 变焦至少间隔 3 秒。没有这个滞回，
            // "推长焦→人在画面里变大→建议拉广角→人变小"会形成振荡
            if let last = lastLensApplyTime,
               Date().timeIntervalSince(last) < 3.0 {
                return
            }

            let targetFactor = calculateTargetZoom(for: strategy)

            // 只有当目标倍率与当前差距较大时才切换（避免频繁抖动）
            if abs(targetFactor - environment.currentZoomFactor) > 0.3 {
                lastLensApplyTime = Date()
                camera.finalizeInteractiveZoom(at: targetFactor, smooth: true)
                lastAppliedZoom = targetFactor
            }
        }
    }
    
    /// 根据镜头偏好计算目标变焦倍率
    private func calculateTargetZoom(for strategy: PhotographyStrategy) -> CGFloat {
        switch strategy.lensPreference {
        case .auto:
            return environment.currentZoomFactor  // 保持当前
            
        case .ultraWide:
            return capability.minZoom  // 最广
        case .wide:
            return 1.0  // 广角
        case .telephoto:
            // 返回长焦的最小光学倍率
            if let telePreset = capability.availableLenses.first(where: { $0 == .telephoto }) {
                return telePreset.opticalZoomFactor
            }
            return min(capability.maxZoom, 3.0)
        }
    }
}

#endif
