//
//  WhiteBalanceControlView.swift
//  FrameHero
//
//  白平衡控制面板
//
//  ## 功能
//  - 色温滑块（暖 ↔ 冷）
//  - 白平衡模式切换（AI Auto / Manual / Locked）
//  - 显示当前色温值
//

import SwiftUI

#if os(iOS)

/// 白平衡控制面板
struct WhiteBalanceControlView: View {
    
    // MARK: - 绑定
    
    /// 当前色温（开尔文）
    @Binding var temperature: Float
    
    /// 白平衡控制模式
    @Binding var controlMode: ControlMode
    
    /// 是否支持手动白平衡
    let supportsManualWB: Bool
    
    /// 色温范围
    let temperatureRange: ClosedRange<Float>
    
    /// 模式切换回调
    var onModeChange: (ControlMode) -> Void
    
    /// 色温变化回调
    var onTemperatureChange: (Float) -> Void
    
    // MARK: - 状态
    
    @State private var isDragging: Bool = false
    
    // MARK: - 计算属性
    
    /// 色温显示文本
    private var temperatureLabel: String {
        "\(Int(temperature))K"
    }
    
    /// 滑块高度
    private let sliderHeight: CGFloat = 100
    
    /// 色温对应的滑块位置（0 = 底部暖色，1 = 顶部冷色）
    private var sliderPosition: CGFloat {
        let range = temperatureRange.upperBound - temperatureRange.lowerBound
        guard range > 0 else { return 0.5 }
        return CGFloat((temperature - temperatureRange.lowerBound) / range)
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 8) {
            // 色温显示
            Text(temperatureLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 18)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.5))
                )
            
            // 色温滑块（垂直，暖色在下方，冷色在上方）
            ZStack(alignment: .bottom) {
                // 渐变色轨道（暖→冷）
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 1.0, green: 0.6, blue: 0.3),  // 暖橙
                                Color.white,                              // 中性白
                                Color(red: 0.4, green: 0.6, blue: 1.0)   // 冷蓝
                            ]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 6, height: sliderHeight)
                    .opacity(0.8)
                
                // 滑块
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .offset(y: -sliderHeight * sliderPosition - 8)
                    .scaleEffect(isDragging ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isDragging)
            }
            .frame(width: 22, height: sliderHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        updateTemperature(from: value.location.y)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .opacity(supportsManualWB ? 1.0 : 0.5)
            .disabled(!supportsManualWB)
            
            // 模式切换（纵向）
            VStack(spacing: 4) {
                ForEach(ControlMode.allCases, id: \.self) { mode in
                    modeButton(mode)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 5)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.4))
        )
    }
    
    // MARK: - 更新色温
    
    private func updateTemperature(from yPosition: CGFloat) {
        let position = 1 - (yPosition / sliderHeight)
        let clamped = min(max(position, 0), 1)
        let range = temperatureRange.upperBound - temperatureRange.lowerBound
        let newTemp = temperatureRange.lowerBound + Float(clamped) * range
        
        // 四舍五入到 100K
        let rounded = (newTemp / 100).rounded() * 100
        
        if abs(rounded - temperature) > 50 {
            temperature = rounded
            onTemperatureChange(rounded)
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
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isActive ? .black : .white)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isActive ? Color.orange : Color.white.opacity(0.2))
                )
        }
    }
}

// MARK: - 预览

struct WhiteBalanceControlView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray
            WhiteBalanceControlView(
                temperature: .constant(5500),
                controlMode: .constant(.aiAuto),
                supportsManualWB: true,
                temperatureRange: 2000...10000,
                onModeChange: { _ in },
                onTemperatureChange: { _ in }
            )
        }
    }
}

#endif
