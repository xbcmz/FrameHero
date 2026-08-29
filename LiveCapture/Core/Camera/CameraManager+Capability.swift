//
//  CameraManager+Capability.swift
//  LiveCapture
//
//  相机设备能力读取扩展
//
//  ## 文件作用
//  从 AVCaptureDevice 读取硬件能力范围，
//  封装为 CameraCapability 结构体供上层使用。
//
//  ## 设计原则
//  - 只读，不修改任何设备配置
//  - 在设备切换时调用一次
//  - 结果缓存到 CameraManager 的属性中
//

import Foundation
import AVFoundation

#if os(iOS)

extension CameraManager {
    
    // MARK: - 读取设备能力
    
    /// 从 AVCaptureDevice 读取硬件能力并更新 cameraCapability
    /// - Parameters:
    ///   - device: 当前相机设备
    ///   - position: 摄像头位置
    ///   - availableLenses: 可用镜头列表（从 Zoom 模块传入）
    ///   - zoomRange: 变焦范围（从 Zoom 模块传入）
    func updateCameraCapability(
        for device: AVCaptureDevice,
        position: AVCaptureDevice.Position,
        availableLenses: [LensKind],
        zoomRange: ClosedRange<CGFloat>
    ) {
        // MARK: 曝光能力
        
        // ISO 范围
        let minISO = device.activeFormat.minISO
        let maxISO = device.activeFormat.maxISO
        let isoRange = minISO...maxISO
        
        // 曝光时长范围
        let minDuration = device.activeFormat.minExposureDuration
        let maxDuration = device.activeFormat.maxExposureDuration
        let exposureDurationRange = minDuration...maxDuration
        
        // 曝光偏差范围
        let minEV = device.minExposureTargetBias
        let maxEV = device.maxExposureTargetBias
        let exposureBiasRange = minEV...maxEV
        
        // MARK: 对焦能力
        
        let supportsFocusLock = device.isFocusModeSupported(.locked)
        let supportsManualFocus = device.isFocusModeSupported(.locked)
            && device.isLockingFocusWithCustomLensPositionSupported
        let focusPositionRange: ClosedRange<Float>? = supportsManualFocus
            ? 0.0...1.0
            : nil
        
        // MARK: 白平衡能力
        
        let supportsWBLock = device.isWhiteBalanceModeSupported(.locked)
        // 注意：手动调节色温需要"自定义增益锁定"能力，而不仅仅是锁定模式
        // 前置摄像头和较老设备可能只支持锁定当前值，不支持自定义增益
        let supportsManualWB = device.isLockingWhiteBalanceWithCustomDeviceGainsSupported
        let wbGainRange: ClosedRange<Float>? = supportsManualWB
            ? 1.0...4.0  // iOS 设备典型范围
            : nil
        
        // MARK: 低光
        
        let supportsLowLight = device.isLowLightBoostSupported
            && device.activeFormat.isVideoHDRSupported
        
        // 构建能力描述
        let capability = CameraCapability(
            availableLenses: availableLenses,
            zoomRange: zoomRange,
            isoRange: isoRange,
            exposureDurationRange: exposureDurationRange,
            exposureBiasRange: exposureBiasRange,
            supportsFocusLock: supportsFocusLock,
            supportsManualFocus: supportsManualFocus,
            focusPositionRange: focusPositionRange,
            supportsWhiteBalanceLock: supportsWBLock,
            supportsManualWhiteBalance: supportsManualWB,
            whiteBalanceGainRange: wbGainRange,
            supportsLowLightBoost: supportsLowLight
        )
        
        updateCameraCapability(capability)
    }
    
    // MARK: - 更新环境状态
    
    /// 从 AVCaptureDevice 读取当前参数并更新 cameraEnvironment
    ///
    /// 可以在需要时调用（如参数变化时、拍照前），
    /// 不需要每帧调用（避免浪费性能）。
    func updateCameraEnvironment(
        device: AVCaptureDevice,
        zoomState: ZoomState
    ) {
        // 计算亮度估算值（基于 ISO 和快门速度）
        // 这是一个简化估算，后续可以用直方图精确计算
        let brightness = estimateBrightness(
            iso: device.iso,
            exposureDuration: device.exposureDuration
        )
        
        // 对焦模式映射
        let focusMode: FocusMode
        switch device.focusMode {
        case .continuousAutoFocus:
            focusMode = .auto
        case .autoFocus:
            focusMode = .autoLocked
        case .locked:
            focusMode = device.isLockingFocusWithCustomLensPositionSupported
                ? .manual
                : .locked
        @unknown default:
            focusMode = .auto
        }
        
        // 白平衡模式映射
        let wbMode: WhiteBalanceMode
        switch device.whiteBalanceMode {
        case .continuousAutoWhiteBalance:
            wbMode = .auto
        case .autoWhiteBalance:
            wbMode = .locked
        case .locked:
            wbMode = .manual
        @unknown default:
            wbMode = .auto
        }
        
        // 估算色温（从白平衡增益反推，简化处理）
        let estimatedTemp = estimateColorTemperature(from: device.deviceWhiteBalanceGains)
        
        let environment = CameraEnvironment(
            currentLens: zoomState.activeLens,
            currentZoomFactor: zoomState.currentFactor,
            currentFocalLength: zoomState.focalLength,
            currentISO: device.iso,
            currentExposureDuration: device.exposureDuration,
            currentExposureBias: device.exposureTargetBias,
            brightness: brightness,
            focusMode: focusMode,
            focusLensPosition: device.lensPosition,
            isFocusAdjusting: device.isAdjustingFocus,
            whiteBalanceMode: wbMode,
            estimatedColorTemperature: estimatedTemp
        )
        
        updateCameraEnvironment(environment)
    }
    
    // MARK: - 亮度估算
    
    /// 基于 ISO 和曝光时长估算画面亮度（简化版）
    ///
    /// 返回 0.0...1.0，值越大越亮。
    /// 这是一个粗略估算，精确值应该用图像直方图。
    private func estimateBrightness(iso: Float, exposureDuration: CMTime) -> Float {
        // 简化的曝光值 (EV) 计算
        // EV = log2(ISO/100) - log2(快门速度)
        let isoEV = log2(iso / 100.0)
        let shutterSeconds = Float(CMTimeGetSeconds(exposureDuration))
        let shutterEV = shutterSeconds > 0 ? -log2(shutterSeconds) : 10
        
        let evValue = isoEV + shutterEV
        
        // 将 EV 值映射到 0...1
        // EV -4 (很暗) → 0.0
        // EV 12 (很亮) → 1.0
        let normalized = (evValue + 4.0) / 16.0
        return min(1.0, max(0.0, normalized))
    }
    
    // MARK: - 色温估算
    
    /// 从白平衡增益估算色温（简化版）
    ///
    /// 真正的色温计算需要复杂的色彩空间转换，
    /// 这里用红绿蓝增益的比例做粗略估算。
    private func estimateColorTemperature(from gains: AVCaptureDevice.WhiteBalanceGains) -> Float {
        // 简化：根据红/蓝增益比例估算色温
        // 红光强 → 暖光（低色温）
        // 蓝光强 → 冷光（高色温）
        let ratio = gains.redGain / gains.blueGain
        
        // 经验公式：ratio 1.0 → 5500K, ratio 2.0 → 3000K, ratio 0.5 → 8000K
        if ratio > 0 {
            let temp = 5500 / Double(ratio)
            return Float(min(10000, max(2000, temp)))
        }
        return 5500
    }
}

#endif
