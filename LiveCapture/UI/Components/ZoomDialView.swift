//
//  ZoomDialView.swift
//  LiveCapture
//
//  原生相机风格变焦控件
//
//  ## 交互设计（与系统相机一致）
//  - 收起态：深色胶囊 + 均匀分布的焦段按钮（.5 / 1 / 2）
//    - 点按：直接切到该焦段
//    - 非整数倍率时，最近焦段槽位显示当前倍率（如 1.8）
//  - 展开态（按住不放或横向拖动唤出）：全宽细分变焦盘
//    - 真实比例排布的刻度与焦段标签，最近值放大高亮
//    - 横向滑动无级变焦，指尖上方悬浮当前倍率
//    - 松手提交并收回胶囊
//

import SwiftUI

#if os(iOS)

/// 原生相机风格的变焦胶囊 + 细分变焦盘
struct ZoomDialView: View {
    // MARK: - 输入

    let presets: [CameraManager.ZoomPreset]
    let range: ClosedRange<CGFloat>
    let currentFactor: CGFloat
    /// 点按焦段按钮
    let onPresetTap: (CameraManager.ZoomPreset) -> Void
    /// 变焦盘拖动中的无级变焦
    let onLiveZoom: (CGFloat) -> Void
    /// 松手提交最终倍率
    let onCommitZoom: (CGFloat) -> Void

    // MARK: - 状态

    @State private var isDialActive = false
    @State private var dialStartFactor: CGFloat = 1.0
    @State private var dialFactor: CGFloat = 1.0
    @State private var gestureStartDate = Date()
    @State private var hitPreset: CameraManager.ZoomPreset?
    @State private var lastTickStep = 0
    @State private var fingerX: CGFloat = 0

    // MARK: - 常量

    private let controlHeight: CGFloat = 48
    private let pillWidth: CGFloat = 190
    private let edgePadding: CGFloat = 26

    /// 按倍率排序的焦段
    private var sortedPresets: [CameraManager.ZoomPreset] {
        presets.sorted { $0.zoomFactor < $1.zoomFactor }
    }

    private var span: CGFloat { max(range.upperBound - range.lowerBound, 0.001) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack {
                if isDialActive {
                    dialView(width: width)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .center)))
                } else {
                    pillView(width: width)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
                }
            }
            .frame(width: width, height: controlHeight)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: width))
        }
        .frame(height: controlHeight)
    }

    // MARK: - 收起态：胶囊

    private func pillView(width: CGFloat) -> some View {
        let items = sortedPresets
        let slotWidth = pillWidth / CGFloat(max(items.count, 1))
        let pillX0 = (width - pillWidth) / 2

        return ZStack {
            Capsule()
                .fill(Color.black.opacity(0.55))
                .frame(width: pillWidth, height: 36)

            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, preset in
                    slotLabel(for: preset)
                        .frame(width: slotWidth)
                }
            }
            .frame(width: pillWidth, height: 36)
        }
        .position(x: width / 2, y: controlHeight / 2)
    }

    /// 胶囊槽位标签：整数倍贴齐时高亮该焦段；非整数倍率时最近槽位显示当前值
    private func slotLabel(for preset: CameraManager.ZoomPreset) -> some View {
        let isExact = abs(preset.zoomFactor - currentFactor) < 0.05
        let isNearest = nearestPresetToCurrent?.id == preset.id
        let isCurrentSlot = isExact || (isNearest && !isAtExactPreset)

        return Text(isCurrentSlot && !isExact ? zoomText(currentFactor) : compactLabel(preset))
            .font(.system(size: isCurrentSlot ? 15 : 14, weight: .bold, design: .rounded))
            .foregroundColor(isCurrentSlot ? .white : .white.opacity(0.75))
            .background(
                Group {
                    if isCurrentSlot {
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 40, height: 28)
                    }
                }
            )
    }

    private var isAtExactPreset: Bool {
        sortedPresets.contains { abs($0.zoomFactor - currentFactor) < 0.05 }
    }

    private var nearestPresetToCurrent: CameraManager.ZoomPreset? {
        sortedPresets.min { abs($0.zoomFactor - currentFactor) < abs($1.zoomFactor - currentFactor) }
    }

    // MARK: - 展开态：细分变焦盘

    private func dialView(width: CGFloat) -> some View {
        let pxPerFactor = (width - 2 * edgePadding) / span

        func xFor(_ factor: CGFloat) -> CGFloat {
            edgePadding + (factor - range.lowerBound) * pxPerFactor
        }

        // 0.5 步进刻度
        let tickCount = Int(span / 0.5) + 1
        let ticks: [CGFloat] = (0..<tickCount).map {
            min(range.lowerBound + CGFloat($0) * 0.5, range.upperBound)
        }

        return ZStack {
            RoundedRectangle(cornerRadius: controlHeight / 2, style: .continuous)
                .fill(Color.black.opacity(0.6))
                .frame(height: controlHeight)

            // 刻度点
            ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                Circle()
                    .fill(Color.white.opacity(tick.rounded() == tick ? 0.55 : 0.25))
                    .frame(width: tick.rounded() == tick ? 4 : 3,
                           height: tick.rounded() == tick ? 4 : 3)
                    .position(x: xFor(tick), y: controlHeight / 2)
            }

            // 焦段标签（最近的放大）
            ForEach(sortedPresets, id: \.id) { preset in
                let isNear = abs(preset.zoomFactor - dialFactor) < 0.12
                Text(compactLabel(preset))
                    .font(.system(size: isNear ? 18 : 12, weight: .bold, design: .rounded))
                    .foregroundColor(isNear ? .white : .white.opacity(0.55))
                    .position(x: xFor(preset.zoomFactor), y: controlHeight / 2)
            }

            // 当前位置指示
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
                .position(x: xFor(dialFactor), y: controlHeight / 2)

            // 指尖上方的当前倍率
            Text(zoomText(dialFactor))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.92)))
                .position(x: min(max(fingerX, edgePadding + 18), width - edgePadding - 18),
                          y: -6)
        }
        .animation(DesignSystem.Animation.quick, value: isDialActive)
    }

    // MARK: - 手势

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                fingerX = value.location.x

                if !isDialActive {
                    let dx = abs(value.translation.width)
                    let held = Date().timeIntervalSince(gestureStartDate) > 0.25

                    if dx > 12 || held {
                        // 唤出变焦盘：从当前倍率开始相对滑动
                        isDialActive = true
                        dialStartFactor = currentFactor
                        dialFactor = currentFactor
                        lastTickStep = Int(dialFactor * 2)
                        HapticManager.shared.soft()
                    } else if hitPreset == nil {
                        hitPreset = presetAt(x: value.location.x, width: width)
                    }
                    return
                }

                // 变焦盘拖动：相对起点的线性映射
                let pxPerFactor = (width - 2 * edgePadding) / span
                let factor = dialStartFactor + value.translation.width / pxPerFactor
                dialFactor = min(max(factor, range.lowerBound), range.upperBound)

                // 每 0.5 步一次轻微触觉反馈
                let step = Int(dialFactor * 2)
                if step != lastTickStep {
                    lastTickStep = step
                    HapticManager.shared.soft()
                }

                onLiveZoom(dialFactor)
            }
            .onEnded { value in
                if isDialActive {
                    onCommitZoom(dialFactor)
                    HapticManager.shared.light()
                    // 稍作停留再收回，让用户看到最终值
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isDialActive = false
                    }
                } else {
                    // 快速点按：切到指下的焦段
                    let moved = abs(value.translation.width) < 12
                    if moved, let preset = hitPreset ?? presetAt(x: value.location.x, width: width) {
                        onPresetTap(preset)
                    }
                }
                hitPreset = nil
            }
    }

    /// 命中测试：胶囊上指下的焦段槽位（与 pillView 的等分槽位布局一致）
    private func presetAt(x: CGFloat, width: CGFloat) -> CameraManager.ZoomPreset? {
        let items = sortedPresets
        guard !items.isEmpty else { return nil }
        let pillX0 = (width - pillWidth) / 2
        let slotW = pillWidth / CGFloat(items.count)
        let localX = x - pillX0
        guard localX >= 0, localX <= pillWidth else { return nil }
        let index = min(max(Int(localX / slotW), 0), items.count - 1)
        return items[index]
    }

    // MARK: - 文案

    /// 原生风格短标签：0.5 → ".5"、1 → "1"、2 → "2"
    private func compactLabel(_ preset: CameraManager.ZoomPreset) -> String {
        zoomText(preset.zoomFactor)
    }

    private func zoomText(_ factor: CGFloat) -> String {
        let rounded = (factor * 10).rounded() / 10
        if rounded < 1 {
            let s = String(format: "%.1f", rounded)
            return s.hasPrefix("0") ? String(s.dropFirst()) : s
        }
        if abs(rounded - rounded.rounded()) < 0.001 {
            return "\(Int(rounded.rounded()))"
        }
        return String(format: "%.1f", rounded)
    }
}

#endif
