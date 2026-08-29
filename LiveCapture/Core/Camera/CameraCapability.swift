//
//  CameraCapability.swift
//  LiveCapture
//
//  相机设备能力模型
//
//  ## 设计理念
//  AI 不直接操作硬件参数，而是先了解"这台 iPhone 能做什么"。
//  CameraCapability 描述设备的硬件能力边界，
//  CameraControlEngine 根据能力将策略转换为实际参数。
//
//  ## 读取时机
//  - 启动相机时读取一次
//  - 切换前后置时重新读取
//  - 一般不会动态变化
//

import Foundation
import AVFoundation

#if os(iOS)

// MARK: - 相机设备能力

/// 相机设备能力描述
///
/// 描述当前 AVCaptureDevice 支持的所有硬件能力范围。
/// 在设备启动/切换时读取一次，供 AI 和 UI 参考。
struct CameraCapability: Equatable {
    
    // MARK: - 镜头与变焦
    
    /// 可用镜头列表
    let availableLenses: [CameraManager.LensKind]
    
    /// 变焦范围（视频变焦倍率）
    let zoomRange: ClosedRange<CGFloat>
    
    /// 最小变焦倍率
    var minZoom: CGFloat { zoomRange.lowerBound }
    
    /// 最大变焦倍率
    var maxZoom: CGFloat { zoomRange.upperBound }
    
    /// 是否有长焦镜头
    var hasTelephoto: Bool {
        availableLenses.contains(.telephoto)
    }
    
    /// 是否有超广角镜头
    var hasUltraWide: Bool {
        availableLenses.contains(.ultraWide)
    }
    
    // MARK: - 曝光
    
    /// ISO 范围（最小值...最大值）
    let isoRange: ClosedRange<Float>
    
    /// 曝光时长范围
    let exposureDurationRange: ClosedRange<CMTime>
    
    /// 曝光偏差范围（EV 值）
    let exposureBiasRange: ClosedRange<Float>
    
    /// 最小 ISO
    var minISO: Float { isoRange.lowerBound }
    
    /// 最大 ISO
    var maxISO: Float { isoRange.upperBound }
    
    /// 最短曝光时长
    var minExposureDuration: CMTime { exposureDurationRange.lowerBound }
    
    /// 最长曝光时长
    var maxExposureDuration: CMTime { exposureDurationRange.upperBound }
    
    /// 最小曝光偏差（EV）
    var minExposureBias: Float { exposureBiasRange.lowerBound }
    
    /// 最大曝光偏差（EV）
    var maxExposureBias: Float { exposureBiasRange.upperBound }
    
    // MARK: - 对焦
    
    /// 是否支持对焦锁定
    let supportsFocusLock: Bool
    
    /// 是否支持手动对焦
    let supportsManualFocus: Bool
    
    /// 对焦位置范围（0.0 = 最近，1.0 = 无穷远），nil 表示不支持
    let focusPositionRange: ClosedRange<Float>?
    
    // MARK: - 白平衡
    
    /// 是否支持白平衡锁定
    let supportsWhiteBalanceLock: Bool
    
    /// 是否支持手动白平衡增益
    let supportsManualWhiteBalance: Bool
    
    /// 白平衡增益范围（通常 1.0...4.0），nil 表示不支持
    let whiteBalanceGainRange: ClosedRange<Float>?
    
    // MARK: - 低光
    
    /// 是否支持低光增强（低光 Boost）
    let supportsLowLightBoost: Bool
    
    // MARK: - 便捷空值
    
    /// 空的能力描述（相机未就绪时使用）
    static let empty = CameraCapability(
        availableLenses: [],
        zoomRange: 1.0...1.0,
        isoRange: 0...0,
        exposureDurationRange: CMTime.zero...CMTime.zero,
        exposureBiasRange: 0...0,
        supportsFocusLock: false,
        supportsManualFocus: false,
        focusPositionRange: nil,
        supportsWhiteBalanceLock: false,
        supportsManualWhiteBalance: false,
        whiteBalanceGainRange: nil,
        supportsLowLightBoost: false
    )
}

// MARK: - 相机环境状态

/// 相机当前环境状态（只读，实时更新）
///
/// 描述当前的拍摄环境和相机参数状态，
/// 供 AI 决策时参考（如 "现在 ISO 已经 1600 了，噪点会比较重"）。
struct CameraEnvironment: Equatable {
    
    // MARK: - 当前镜头与变焦
    
    /// 当前镜头
    let currentLens: CameraManager.LensKind
    
    /// 当前变焦倍率
    let currentZoomFactor: CGFloat
    
    /// 当前等效焦距（mm）
    let currentFocalLength: Int
    
    // MARK: - 曝光参数
    
    /// 当前 ISO
    let currentISO: Float
    
    /// 当前曝光时长
    let currentExposureDuration: CMTime
    
    /// 当前曝光偏差（EV）
    let currentExposureBias: Float
    
    // MARK: - 环境感知
    
    /// 估算亮度 0.0...1.0（0 = 全黑，1 = 最亮）
    /// 基于 ISO 和快门速度估算，或从直方图获取
    let brightness: Float
    
    /// 是否处于低光环境
    var isLowLight: Bool {
        brightness < 0.3 || currentISO > 800
    }
    
    /// 低光等级
    var lowLightLevel: LowLightLevel {
        if brightness < 0.15 || currentISO > 1600 {
            return .veryLow
        } else if brightness < 0.3 || currentISO > 800 {
            return .low
        } else if brightness < 0.5 || currentISO > 400 {
            return .moderate
        }
        return .normal
    }
    
    // MARK: - 对焦状态
    
    /// 对焦模式
    let focusMode: FocusMode
    
    /// 镜头位置（0.0 = 最近，1.0 = 无穷远）
    let focusLensPosition: Float
    
    /// 是否正在调整对焦
    let isFocusAdjusting: Bool
    
    // MARK: - 白平衡
    
    /// 白平衡模式
    let whiteBalanceMode: WhiteBalanceMode
    
    /// 估算色温（开尔文）
    let estimatedColorTemperature: Float
    
    // MARK: - 便捷空值
    
    /// 空的环境状态（相机未就绪时使用）
    static let empty = CameraEnvironment(
        currentLens: .wide,
        currentZoomFactor: 1.0,
        currentFocalLength: 24,
        currentISO: 0,
        currentExposureDuration: CMTime.zero,
        currentExposureBias: 0,
        brightness: 0.5,
        focusMode: .auto,
        focusLensPosition: 0.5,
        isFocusAdjusting: false,
        whiteBalanceMode: .auto,
        estimatedColorTemperature: 5500
    )
}

// MARK: - 支持枚举

/// 低光等级
enum LowLightLevel: String, CaseIterable, Equatable {
    case normal         // 正常光线
    case moderate       // 中等低光
    case low            // 低光
    case veryLow        // 极弱光
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .normal: return "光线充足"
        case .moderate: return "光线一般"
        case .low: return "低光环境"
        case .veryLow: return "极弱光"
        }
    }
    
    /// 图标
    var symbolName: String {
        switch self {
        case .normal: return "sun.max.fill"
        case .moderate: return "sun.min.fill"
        case .low: return "moon.fill"
        case .veryLow: return "moon.stars.fill"
        }
    }
}

/// 对焦模式
enum FocusMode: String, CaseIterable, Equatable {
    case auto           // 自动对焦（连续）
    case autoLocked     // 自动对焦锁定
    case locked         // 手动锁定
    case manual         // 完全手动
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .auto: return "自动对焦"
        case .autoLocked: return "自动锁定"
        case .locked: return "对焦锁定"
        case .manual: return "手动对焦"
        }
    }
}

/// 白平衡模式
enum WhiteBalanceMode: String, CaseIterable, Equatable {
    case auto           // 自动白平衡
    case locked         // 锁定当前白平衡
    case manual         // 手动白平衡
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .auto: return "自动白平衡"
        case .locked: return "白平衡锁定"
        case .manual: return "手动白平衡"
        }
    }
}

#endif
