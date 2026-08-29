//
//  FocusControlView.swift
//  LiveCapture
//
//  对焦控制面板
//
//  ## 功能
//  - 手动对焦滑块（最近 ↔ 无穷远）
//  - 对焦模式切换（AI Auto / Manual / Locked）
//  - 显示当前对焦位置
//

import SwiftUI

#if os(iOS)

/// 对焦控制面板
struct FocusControlView: View {
    
    // MARK: - 绑定
    
    /// 手动对焦位置 0.0...1.0
    @Binding var focusPosition: Float
    
    /// 对焦控制模式
    @Binding var controlMode: ControlMode
    
    /// 是否支持手动对焦
    let supportsManualFocus: Bool
    
    /// 模式切换回调
    var onModeChange: (ControlMode) -> Void
    
    /// 对焦位置变化回调
    var onPositionChange: (Float) -> Void
    
    // MARK: - 状态
    
    @State private var isDragging: Bool = false
    
    // MARK: - 计算属性
    
    /// 对焦位置显示文本
    private var positionLabel: String {
        if focusPosition < 0.2 {
            return "微距"
        } else if focusPosition < 0.5 {
            return "近"
        } else if focusPosition < 0.8 {
            return "中"
        } else {
            return "∞"
        }
    }
    
    /// 滑块高度
    private let sliderHeight: CGFloat = 120
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 10) {
            // 对焦位置显示
            Text(positionLabel)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 20)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.5))
                )
            
            // 对焦滑块（垂直）
            ZStack(alignment: .bottom) {
                // 轨道
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 6, height: sliderHeight)
                
                // 已填充部分
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.blue)
                    .frame(width: 6, height: sliderHeight * CGFloat(focusPosition))
                
                // 滑块
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .offset(y: -sliderHeight * CGFloat(focusPosition) - 9)
                    .scaleEffect(isDragging ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isDragging)
            }
            .frame(width: 24, height: sliderHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        updatePosition(from: value.location.y)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .opacity(supportsManualFocus ? 1.0 : 0.5)
            .disabled(!supportsManualFocus)
            
            // 模式切换（纵向排列）
            VStack(spacing: 4) {
                ForEach(ControlMode.allCases, id: \.self) { mode in
                    modeButton(mode)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.4))
        )
    }
    
    // MARK: - 更新对焦位置
    
    private func updatePosition(from yPosition: CGFloat) {
        let position = 1 - (yPosition / sliderHeight)
        let clamped = min(max(position, 0), 1)
        let newPosition = Float(clamped)
        
        // 四舍五入到 0.01
        let rounded = (newPosition * 100).rounded() / 100
        
        if abs(rounded - focusPosition) > 0.005 {
            focusPosition = rounded
            onPositionChange(rounded)
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
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isActive ? .black : .white)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isActive ? Color.blue : Color.white.opacity(0.2))
                )
        }
    }
}

// MARK: - 预览

struct FocusControlView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray
            FocusControlView(
                focusPosition: .constant(0.5),
                controlMode: .constant(.aiAuto),
                supportsManualFocus: true,
                onModeChange: { _ in },
                onPositionChange: { _ in }
            )
        }
    }
}

#endif
