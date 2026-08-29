//
//  CameraManager+Control.swift
//  LiveCapture
//
//  相机手动控制扩展
//
//  ## 文件作用
//  封装 AVCaptureDevice 的手动控制 API，
//  包括曝光、对焦、白平衡等。
//
//  ## 设计原则
//  - 只做底层 API 封装，不做业务逻辑
//  - 业务逻辑（什么时候调、调多少）由 CameraControlEngine 决定
//  - 所有操作都在 sessionQueue 上执行
//
//  ## Phase 1 范围
//  - 曝光偏差 (EV) 调整
//  - 曝光模式切换（自动/锁定/自定义）
//
//  ## 后续 Phase 扩展
//  - 对焦控制
//  - 白平衡控制
//  - 手动 ISO/快门
//

import Foundation
import AVFoundation

#if os(iOS)

extension CameraManager {
    
    // MARK: - 曝光偏差 (EV) 控制
    
    /// 设置曝光偏差（Exposure Target Bias）
    ///
    /// - Parameters:
    ///   - bias: 曝光偏差值，单位 EV，范围由设备决定（通常 -2...+2）
    ///   - animated: 是否平滑过渡
    ///
    /// 这是最简单的手动曝光方式：
    /// 系统仍然自动调节 ISO 和快门，
    /// 但整体曝光会偏移指定的 EV 值。
    func setExposureBias(_ bias: Float, animated: Bool = true) {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.activeVideoDevice else { return }
            
            let clamped = min(
                max(bias, device.minExposureTargetBias),
                device.maxExposureTargetBias
            )
            
            do {
                try device.lockForConfiguration()
                if animated {
                    device.setExposureTargetBias(clamped)
                } else {
                    device.setExposureTargetBias(clamped, completionHandler: nil)
                }
                device.unlockForConfiguration()
            } catch {
                print("⚠️ 设置曝光偏差失败: \(error)")
            }
            
            // 更新环境状态
            self.updateCameraEnvironment(device: device, zoomState: self.zoomState)
        }
    }
    
    /// 重置曝光偏差为 0
    func resetExposureBias() {
        setExposureBias(0)
    }
    
    // MARK: - 曝光模式控制
    
    /// 曝光模式
    enum ExposureMode {
        case auto           // 连续自动曝光
        case autoLocked     // 自动曝光锁定（锁定当前值）
        case custom         // 自定义 ISO + 快门
    }
    
    /// 设置曝光模式
    ///
    /// - Parameter mode: 曝光模式
    ///
    /// auto: 系统持续自动调整曝光
    /// autoLocked: 锁定当前自动曝光值，不再调整
    /// custom: 需要配合 setCustomExposure(iso:shutter:) 使用
    func setExposureMode(_ mode: ExposureMode) {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.activeVideoDevice else { return }
            
            do {
                try device.lockForConfiguration()
                
                switch mode {
                case .auto:
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    } else if device.isExposureModeSupported(.autoExpose) {
                        device.exposureMode = .autoExpose
                    }
                    
                case .autoLocked:
                    if device.isExposureModeSupported(.locked) {
                        // 先触发一次自动曝光，然后锁定
                        if device.isExposureModeSupported(.autoExpose) {
                            device.exposureMode = .autoExpose
                        }
                        // 等曝光稳定后会变成 locked，但我们先主动设为 locked
                        // 实际使用中应该用 KVO 监听 isAdjustingExposure
                        device.exposureMode = .locked
                    }
                    
                case .custom:
                    // custom 模式需要配合 setCustomExposure 使用
                    // 这里先切到 locked，保持当前值
                    if device.isExposureModeSupported(.locked) {
                        device.exposureMode = .locked
                    }
                }
                
                device.unlockForConfiguration()
            } catch {
                print("⚠️ 设置曝光模式失败: \(error)")
            }
            
            self.updateCameraEnvironment(device: device, zoomState: self.zoomState)
        }
    }
    
    // MARK: - 自定义曝光（ISO + 快门速度）
    
    /// 设置自定义曝光参数（ISO + 快门速度）
    ///
    /// - Parameters:
    ///   - iso: ISO 值（必须在设备支持范围内）
    ///   - shutter: 快门速度（必须在设备支持范围内）
    ///   - animated: 是否平滑过渡
    ///
    /// 注意：调用此方法会自动将曝光模式切换为 .custom (locked)
    func setCustomExposure(
        iso: Float? = nil,
        shutter: CMTime? = nil,
        animated: Bool = true
    ) {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.activeVideoDevice else { return }
            
            let currentISO = device.iso
            let currentShutter = device.exposureDuration
            let targetISO = iso ?? currentISO
            let targetShutter = shutter ?? currentShutter
            
            // 钳位到设备支持范围
            let clampedISO = min(
                max(targetISO, device.activeFormat.minISO),
                device.activeFormat.maxISO
            )
            let minDuration = device.activeFormat.minExposureDuration
            let maxDuration = device.activeFormat.maxExposureDuration
            let clampedShutter = CMTimeMinimum(
                CMTimeMaximum(targetShutter, minDuration),
                maxDuration
            )
            
            do {
                try device.lockForConfiguration()
                
                if animated {
                    device.setExposureModeCustom(
                        duration: clampedShutter,
                        iso: clampedISO
                    ) { _ in
                        // 曝光设置完成
                    }
                } else {
                    device.setExposureModeCustom(
                        duration: clampedShutter,
                        iso: clampedISO,
                        completionHandler: nil
                    )
                }
                
                device.unlockForConfiguration()
            } catch {
                print("⚠️ 设置自定义曝光失败: \(error)")
            }
            
            self.updateCameraEnvironment(device: device, zoomState: self.zoomState)
        }
    }
    
    // MARK: - 恢复自动曝光
    
    /// 恢复全自动曝光模式（同时重置 EV 为 0）
    func resetExposureToAuto() {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.activeVideoDevice else { return }
            
            do {
                try device.lockForConfiguration()
                
                // 恢复连续自动曝光
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                
                // 重置 EV 为 0
                device.setExposureTargetBias(0, completionHandler: nil)
                
                device.unlockForConfiguration()
            } catch {
                print("⚠️ 恢复自动曝光失败: \(error)")
            }
            
            self.updateCameraEnvironment(device: device, zoomState: self.zoomState)
        }
    }
    
    // MARK: - 对焦控制
    
    /// 设置对焦模式
    ///
    /// - Parameter mode: 对焦模式
    func setFocusMode(_ mode: FocusMode) {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.activeVideoDevice else { return }
            
            do {
                try device.lockForConfiguration()
                
                switch mode {
                case .auto:
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    
                case .autoLocked:
                    if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                    
                case .locked:
                    if device.isFocusModeSupported(.locked) {
                        device.focusMode = .locked
                    }
                    
                case .manual:
                    if device.isFocusModeSupported(.locked) {
                        device.focusMode = .locked
                    }
                }
                
                device.unlockForConfiguration()
            } catch {
                print("⚠️ 设置对焦模式失败: \(error)")
            }
            
            self.updateCameraEnvironment(device: device, zoomState: self.zoomState)
        }
    }
    
    /// 设置对焦点（画面中的兴趣点）
    ///
    /// - Parameters:
    ///   - point: 对焦点，坐标范围 0...1（0,0 = 左上，1,1 = 右下）
    ///
    /// 调用后会自动切换到自动对焦模式，
    /// 并在指定点进行对焦。
    func setFocusPointOfInterest(_ point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.activeVideoDevice else { return }
            
            do {
                try device.lockForConfiguration()
                
                // 设置对焦兴趣点
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                }
                
                // 设置曝光兴趣点（联动）
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                }
                
                // 切换到自动对焦模式（触发一次对焦）
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                
                // 切换到连续自动曝光
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                
                device.unlockForConfiguration()
            } catch {
                print("⚠️ 设置对焦点失败: \(error)")
            }
            
            self.updateCameraEnvironment(device: device, zoomState: self.zoomState)
        }
    }
    
    /// 设置手动对焦位置
    ///
    /// - Parameters:
    ///   - position: 镜头位置 0.0...1.0
    ///     - 0.0 = 最近对焦距离
    ///     - 1.0 = 无穷远
    ///   - animated: 是否平滑过渡
    ///
    /// 调用后会自动切换对焦模式为 .locked
    func setManualFocusPosition(_ position: Float, animated: Bool = true) {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.activeVideoDevice else { return }
            
            let clamped = min(max(position, 0.0), 1.0)
            
            do {
                try device.lockForConfiguration()
                
                // 确保对焦模式是 locked
                if device.isFocusModeSupported(.locked) {
                    device.focusMode = .locked
                }
                
                // 设置自定义镜头位置
                if device.isLockingFocusWithCustomLensPositionSupported {
                    if animated {
                        device.setFocusModeLocked(lensPosition: clamped)
                    } else {
                        device.setFocusModeLocked(
                            lensPosition: clamped,
                            completionHandler: nil
                        )
                    }
                }
                
                device.unlockForConfiguration()
            } catch {
                print("⚠️ 设置手动对焦失败: \(error)")
            }
            
            self.updateCameraEnvironment(device: device, zoomState: self.zoomState)
        }
    }
    
    /// 锁定当前对焦位置
    func lockFocus() {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.activeVideoDevice else { return }
            
            do {
                try device.lockForConfiguration()
                
                if device.isFocusModeSupported(.locked) {
                    device.focusMode = .locked
                }
                
                device.unlockForConfiguration()
            } catch {
                print("⚠️ 锁定对焦失败: \(error)")
            }
            
            self.updateCameraEnvironment(device: device, zoomState: self.zoomState)
        }
    }
    
    /// 恢复自动对焦
    func resetFocusToAuto() {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.activeVideoDevice else { return }
            
            do {
                try device.lockForConfiguration()
                
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                
                // 重置对焦兴趣点为中心
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                
                device.unlockForConfiguration()
            } catch {
                print("⚠️ 恢复自动对焦失败: \(error)")
            }
            
            self.updateCameraEnvironment(device: device, zoomState: self.zoomState)
        }
    }
    
    // MARK: - 白平衡控制
    
    /// 设置白平衡模式
    func setWhiteBalanceMode(_ mode: WhiteBalanceMode) {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.activeVideoDevice else { return }
            
            do {
                try device.lockForConfiguration()
                
                switch mode {
                case .auto:
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                    
                case .locked:
                    if device.isWhiteBalanceModeSupported(.locked) {
                        device.whiteBalanceMode = .locked
                    }
                    
                case .manual:
                    if device.isWhiteBalanceModeSupported(.locked) {
                        device.whiteBalanceMode = .locked
                    }
                }
                
                device.unlockForConfiguration()
            } catch {
                print("⚠️ 设置白平衡模式失败: \(error)")
            }
            
            self.updateCameraEnvironment(device: device, zoomState: self.zoomState)
        }
    }
    
    /// 通过色温设置手动白平衡
    ///
    /// - Parameter temperature: 色温（开尔文），通常范围 2000K...10000K
    ///
    /// 调用后会自动切换到 locked 模式
    func setWhiteBalanceTemperature(_ temperature: Float) {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.activeVideoDevice else { return }
            
            do {
                try device.lockForConfiguration()
                
                // 关键：必须检查是否支持自定义增益锁定
                // 前置摄像头、较老设备可能不支持
                guard device.isLockingWhiteBalanceWithCustomDeviceGainsSupported else {
                    print("⚠️ 设备不支持自定义白平衡增益，跳过色温调节")
                    device.unlockForConfiguration()
                    return
                }
                
                // 将色温转换为白平衡增益
                // 简化实现：基于色温估算红/蓝增益比例
                let gains = self.whiteBalanceGains(forTemperature: temperature, device: device)
                
                device.setWhiteBalanceModeLocked(with: gains)
                
                device.unlockForConfiguration()
            } catch {
                print("⚠️ 设置白平衡色温失败: \(error)")
            }
            
            self.updateCameraEnvironment(device: device, zoomState: self.zoomState)
        }
    }
    
    /// 锁定当前白平衡
    func lockWhiteBalance() {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.activeVideoDevice else { return }
            
            do {
                try device.lockForConfiguration()
                
                if device.isWhiteBalanceModeSupported(.locked) {
                    device.whiteBalanceMode = .locked
                }
                
                device.unlockForConfiguration()
            } catch {
                print("⚠️ 锁定白平衡失败: \(error)")
            }
            
            self.updateCameraEnvironment(device: device, zoomState: self.zoomState)
        }
    }
    
    /// 恢复自动白平衡
    func resetWhiteBalanceToAuto() {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.activeVideoDevice else { return }
            
            do {
                try device.lockForConfiguration()
                
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                
                device.unlockForConfiguration()
            } catch {
                print("⚠️ 恢复自动白平衡失败: \(error)")
            }
            
            self.updateCameraEnvironment(device: device, zoomState: self.zoomState)
        }
    }
    
    // MARK: - 色温 → 白平衡增益转换
    
    /// 将色温（开尔文）转换为 AVCaptureDevice.WhiteBalanceGains
    ///
    /// 基于 Tanner-Helland 黑体辐射近似计算光源颜色，
    /// 再取倒数（中和该光源所需的增益）并归一化到最小增益 1.0。
    /// 注意：该公式的历史域是「百开尔文」（Kelvin/100），必须先换算。
    private func whiteBalanceGains(
        forTemperature temperature: Float,
        device: AVCaptureDevice
    ) -> AVCaptureDevice.WhiteBalanceGains {
        let temp = Double(min(max(temperature, 1500), 15000)) / 100.0

        // 光源的归一化 RGB（6500K ≈ 纯白）
        var r: Double
        var g: Double
        var b: Double
        if temp <= 66 {
            r = 1.0
            g = min(max(0.3900815787690196 * log(temp) - 0.6318414437886275, 0), 1)
            b = temp <= 19 ? 0 : min(max(0.5432067891400797 * log(temp - 10) - 1.19625408914, 0), 1)
        } else {
            r = min(max(1.292936186062745 * pow(temp - 60, -0.1332047592), 0), 1)
            g = min(max(1.129890870881635 * pow(temp - 60, -0.0755148492), 0), 1)
            b = 1.0
        }

        // 中和光源：增益与光源通道强度成反比，归一化使最小增益为 1
        var red = 1.0 / max(r, 0.05)
        var green = 1.0 / max(g, 0.05)
        var blue = 1.0 / max(b, 0.05)
        let minGain = min(red, green, blue)
        red /= minGain
        green /= minGain
        blue /= minGain

        let maxGain = Double(device.maxWhiteBalanceGain)
        return AVCaptureDevice.WhiteBalanceGains(
            redGain: Float(min(max(red, 1.0), maxGain)),
            greenGain: Float(min(max(green, 1.0), maxGain)),
            blueGain: Float(min(max(blue, 1.0), maxGain))
        )
    }
}

#endif
