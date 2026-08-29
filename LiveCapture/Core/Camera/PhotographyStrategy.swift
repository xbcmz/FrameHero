//
//  PhotographyStrategy.swift
//  LiveCapture
//
//  摄影策略模型
//
//  ## 设计理念
//  AI 不直接输出 ISO=xxx / Shutter=xxx，
//  因为 AI 不知道当前设备的真实能力范围。
//
//  正确方式：
//  AI / 用户 → PhotographyStrategy（语义化偏好）
//  → CameraControlEngine → 实际硬件参数
//
//  ## 三态控制
//  每个参数独立支持：
//  - aiAuto: AI 自动调整
//  - manual: 用户手动调整（AI 可建议但不自动改）
//  - locked: 用户锁定，AI 完全不能碰
//

import Foundation
import AVFoundation

#if os(iOS)

// MARK: - 控制模式

/// 参数控制模式：每个相机参数独立的三态控制
enum ControlMode: String, CaseIterable, Equatable {
    case aiAuto     // AI 自动调整
    case manual     // 用户手动调整（AI 可建议但不自动改）
    case locked     // 用户锁定，AI 完全不能碰
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .aiAuto: return "AI 自动"
        case .manual: return "手动"
        case .locked: return "锁定"
        }
    }
    
    /// 图标
    var symbolName: String {
        switch self {
        case .aiAuto: return "sparkles"
        case .manual: return "slider.horizontal.3"
        case .locked: return "lock.fill"
        }
    }
}

// MARK: - 镜头策略

/// 镜头偏好
enum LensPreference: String, CaseIterable, Equatable {
    case auto            // AI 自动选择
    case ultraWide       // 固定超广角
    case wide            // 固定广角
    case telephoto       // 固定长焦
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .ultraWide: return "超广角"
        case .wide: return "广角"
        case .telephoto: return "长焦"
        }
    }
}

// MARK: - 曝光策略

/// 亮度偏好（语义化，由控制引擎翻译成具体 EV 值）
enum BrightnessPreference: String, CaseIterable, Equatable {
    case auto                // 自动
    case darker              // 压暗一点
    case brighter            // 提亮一点
    case preserveHighlights  // 保留高光（人像逆光等）
    case night               // 夜景优先
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .darker: return "压暗"
        case .brighter: return "提亮"
        case .preserveHighlights: return "保留高光"
        case .night: return "夜景"
        }
    }
    
    /// 对应的 EV 偏移量（仅作参考，最终由 CameraControlEngine 决定）
    var evBias: Float {
        switch self {
        case .auto: return 0
        case .darker: return -0.3
        case .brighter: return +0.3
        case .preserveHighlights: return -0.7
        case .night: return +1.0
        }
    }
}

/// 运动优先级（影响快门速度和 ISO 的权衡）
enum MotionPriority: String, CaseIterable, Equatable {
    case freezeMotion    // 凝固动作（优先高快门速度）
    case balanced        // 平衡
    case lowNoise        // 低噪点优先（优先低 ISO）
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .freezeMotion: return "凝固动作"
        case .balanced: return "平衡"
        case .lowNoise: return "低噪点"
        }
    }
}

// MARK: - 对焦策略

/// 对焦偏好
enum FocusPreference: String, CaseIterable, Equatable {
    case auto            // 自动追焦
    case subjectLock     // 锁定主体
    case manual          // 手动对焦
    case macro           // 微距模式
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .subjectLock: return "锁定主体"
        case .manual: return "手动"
        case .macro: return "微距"
        }
    }
}

// MARK: - 白平衡策略

/// 白平衡偏好
enum WhiteBalancePreference: String, CaseIterable, Equatable {
    case auto            // 自动
    case warm            // 暖色调
    case cool            // 冷色调
    case natural         // 自然真实
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .warm: return "暖色"
        case .cool: return "冷色"
        case .natural: return "自然"
        }
    }
    
    /// 对应的色温偏移（开尔文，仅作参考）
    var temperatureOffset: Float {
        switch self {
        case .auto: return 0
        case .warm: return +500
        case .cool: return -500
        case .natural: return -200
        }
    }
}

// MARK: - 景深策略

/// 景深偏好
enum DepthPreference: String, CaseIterable, Equatable {
    case auto            // 自动
    case shallow         // 浅景深（人像虚化）
    case deep            // 深景深（风景清晰）
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .auto: return "自动"
        case .shallow: return "浅景深"
        case .deep: return "深景深"
        }
    }
}

// MARK: - 摄影策略（核心模型）

/// 摄影策略
///
/// 语义化描述"想要什么样的照片"，不包含具体硬件参数。
/// 由 AI 建议 + 用户手动覆盖共同决定。
/// CameraControlEngine 负责将其翻译成当前设备的实际参数。
///
/// 每个维度独立控制，用户可以只锁定 ISO，
/// 让 AI 自由调整曝光、镜头、对焦等。
struct PhotographyStrategy: Equatable {
    
    // MARK: - 控制模式（每个参数独立）
    
    /// 镜头控制模式
    var lensControl: ControlMode = .aiAuto
    
    /// 曝光控制模式
    var exposureControl: ControlMode = .aiAuto
    
    /// 对焦控制模式
    var focusControl: ControlMode = .aiAuto
    
    /// 白平衡控制模式
    var whiteBalanceControl: ControlMode = .aiAuto
    
    // MARK: - 镜头策略
    
    /// 镜头偏好
    var lensPreference: LensPreference = .auto
    
    /// 手动变焦倍率（manual/locked 模式时使用）
    var manualZoomFactor: CGFloat? = nil
    
    // MARK: - 曝光策略
    
    /// 亮度偏好
    var brightnessPreference: BrightnessPreference = .auto
    
    /// 运动优先级
    var motionPriority: MotionPriority = .balanced
    
    /// 用户手动 EV 调整（manual 模式时使用）
    var manualExposureBias: Float = 0.0
    
    /// 手动锁定 ISO（locked 模式时使用）
    var manualISO: Float? = nil
    
    /// 手动锁定快门速度（locked 模式时使用）
    var manualShutter: CMTime? = nil
    
    // MARK: - 对焦策略
    
    /// 对焦偏好
    var focusPreference: FocusPreference = .auto
    
    /// 手动对焦位置 0.0...1.0（manual/locked 模式时使用）
    var manualFocusPosition: Float? = nil
    
    /// 用户点选的对焦位置（视图坐标）
    var focusPointOfInterest: CGPoint? = nil
    
    // MARK: - 白平衡策略
    
    /// 白平衡偏好
    var whiteBalancePreference: WhiteBalancePreference = .auto
    
    /// 手动色温（开尔文，manual/locked 模式时使用）
    var manualWhiteBalanceTemp: Float? = nil
    
    // MARK: - 景深偏好
    
    /// 景深偏好
    var depthPreference: DepthPreference = .auto
    
    // MARK: - 默认策略
    
    /// 默认策略：全部 AI 自动
    static let `default` = PhotographyStrategy()
    
    /// 全手动策略
    static var allManual: PhotographyStrategy {
        var strategy = PhotographyStrategy()
        strategy.lensControl = .manual
        strategy.exposureControl = .manual
        strategy.focusControl = .manual
        strategy.whiteBalanceControl = .manual
        return strategy
    }
}

#endif
