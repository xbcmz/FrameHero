//
//  ExposureControlView.swift
//  LiveCapture
//
//  曝光控制面板（EV 滑块 + 模式切换）
//
//  ## 设计
//  仿 iOS 原生相机的曝光调节体验：
//  - 垂直滑块，上下拖动调整 EV
//  - 顶部显示当前 EV 值
//  - 支持 AI Auto / Manual / Locked 三态切换
//
//  ## Phase 1 范围
//  - EV 滑块
//  - 三态模式切换按钮
//  - 当前 EV 值显示
//

import SwiftUI

#if os(iOS)

/// 曝光控制面板
struct ExposureControlView: View {
    
    // MARK: - 绑定
    
    /// 当前曝光偏差（EV）
    @Binding var exposureBias: Float
    
    /// 曝光控制模式
    @Binding var controlMode: ControlMode
    
    /// EV 范围（从设备能力读取）
    let evRange: ClosedRange<Float>
    
    /// 模式切换回调
    var onModeChange: (ControlMode) -> Void
    
    /// EV 值变化回调
    var onBiasChange: (Float) -> Void
    
    // MARK: - 状态
    
    @State private var isDragging: Bool = false
    @State private var dragOffset: CGFloat = 0
    
    // MARK: - 计算属性
    
    private var evDisplay: String {
        String(format: "%+.1f", exposureBias)
    }
    
    private var minEV: CGFloat { CGFloat(evRange.lowerBound) }
    private var maxEV: CGFloat { CGFloat(evRange.upperBound) }
    
    /// 滑块高度
    private let sliderHeight: CGFloat = 180
    
    /// EV 值对应的滑块位置（0 = 底部，1 = 顶部）
    private var sliderPosition: CGFloat {
        let range = maxEV - minEV
        guard range > 0 else { return 0.5 }
        return CGFloat((exposureBias - evRange.lowerBound)) / range
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 12) {
            // EV 值显示
            Text(evDisplay)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 50, height: 24)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.5))
                )
            
            // EV 滑块（垂直）
            ZStack(alignment: .bottom) {
                // 轨道
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 6, height: sliderHeight)
                
                // 已填充部分
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.yellow)
                    .frame(width: 6, height: sliderHeight * sliderPosition)
                
                // 0 刻度线
                HStack(spacing: 0) {
                    Spacer()
                        .frame(width: 10)
                    Rectangle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 8, height: 1)
                }
                .offset(y: -sliderHeight * zeroPosition)
                
                // 滑块
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .offset(y: -sliderHeight * sliderPosition - 10)
                    .scaleEffect(isDragging ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isDragging)
            }
            .frame(width: 28, height: sliderHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        updateBias(from: value.location.y)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            
            // 模式切换
            HStack(spacing: 6) {
                ForEach(ControlMode.allCases, id: \.self) { mode in
                    modeButton(mode)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.4))
        )
    }
    
    // MARK: - 0 刻度位置
    
    private var zeroPosition: CGFloat {
        let range = maxEV - minEV
        guard range > 0 else { return 0.5 }
        return CGFloat(0 - minEV) / range
    }
    
    // MARK: - 更新 EV 值
    
    private func updateBias(from yPosition: CGFloat) {
        let position = 1 - (yPosition / sliderHeight)
        let clamped = min(max(position, 0), 1)
        let range = maxEV - minEV
        let newBias = Float(minEV + clamped * range)
        
        // 四舍五入到 0.1
        let rounded = (newBias * 10).rounded() / 10
        
        if abs(rounded - exposureBias) > 0.05 {
            exposureBias = rounded
            onBiasChange(rounded)
        }
    }
    
    // MARK: - 模式按钮
    
    private func modeButton(_ mode: ControlMode) -> some View {
        let isActive = controlMode == mode
        
        return Button {
            controlMode = mode
            onModeChange(mode)
        } label: {
            Image(systemName: mode.symbolName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? .black : .white)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isActive ? Color.yellow : Color.white.opacity(0.2))
                )
        }
    }
}

// MARK: - 预览

struct ExposureControlView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray
            ExposureControlView(
                exposureBias: .constant(0.0),
                controlMode: .constant(.aiAuto),
                evRange: -2.0...2.0,
                onModeChange: { _ in },
                onBiasChange: { _ in }
            )
        }
    }
}

#endif
