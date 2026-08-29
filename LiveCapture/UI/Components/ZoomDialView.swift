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
//    - 分段非线性刻度（0.5~2× 占近半宽度，2×~25× 压缩到右半段），
//      与原生相机的比例手感一致；变焦盘上限 25×（与原生一致，
//      更高的数码变焦仍可通过捏合手势到达）
//    - 横向滑动无级变焦，指尖上方悬浮当前倍率
//    - 松手提交并收回胶囊
//
//  ## 流畅度
//  - 拖动中视图状态全速更新，但下发给相机的指令节流到 ~30Hz
//    且步长小于 0.01 时跳过，避免 120Hz 手势打满 sessionQueue
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
    @State private var lastHapticStep = 0
    @State private var fingerX: CGFloat = 0
    @State private var lastSentFactor: CGFloat = 0
    @State private var lastSentTime = Date.distantPast

    // MARK: - 常量

    private let controlHeight: CGFloat = 48
    private let pillWidth: CGFloat = 216
    private let pillHeight: CGFloat = 40
    private let edgePadding: CGFloat = 26

    /// 变焦盘上限（与原生相机一致；捏合手势仍可到硬件上限）
    private var dialMax: CGFloat { min(range.upperBound, 25) }
    /// 分段刻度边界：[lower, 2] 占 midFraction 宽度，[2, dialMax] 占其余
    private var midPoint: CGFloat { max(2.0, range.lowerBound * 2) }
    private let midFraction: CGFloat = 0.45

    /// 按倍率排序的焦段
    private var sortedPresets: [CameraManager.ZoomPreset] {
        presets.sorted { $0.zoomFactor < $1.zoomFactor }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack {
                if isDialActive {
                    dialView(width: width)
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .center)))
                } else {
                    pillView(width: width)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .center)))
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

        return ZStack {
            Capsule()
                .fill(Color.black.opacity(0.55))
                .frame(width: pillWidth, height: pillHeight)

            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { _, preset in
                    slotLabel(for: preset)
                        .frame(width: slotWidth)
                        .contentShape(Rectangle())
                }
            }
            .frame(width: pillWidth, height: pillHeight)
        }
        .position(x: width / 2, y: controlHeight / 2)
    }

    /// 胶囊槽位标签：整数倍贴齐时高亮该焦段；非整数倍率时最近槽位显示当前值
    private func slotLabel(for preset: CameraManager.ZoomPreset) -> some View {
        let isExact = abs(preset.zoomFactor - currentFactor) < 0.05
        let isNearest = nearestPresetToCurrent?.id == preset.id
        let isCurrentSlot = isExact || (isNearest && !isAtExactPreset)

        return Text(isCurrentSlot && !isExact ? zoomText(currentFactor) : compactLabel(preset))
            .font(.system(size: isCurrentSlot ? 17 : 16, weight: .bold, design: .rounded))
            .foregroundColor(isCurrentSlot ? .white : .white.opacity(0.75))
            .background(
                Group {
                    if isCurrentSlot {
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 44, height: 30)
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

    // MARK: - 展开态：细分变焦盘（分段非线性刻度）

    /// 倍率 → 归一化刻度位置 0...1
    private func factorToUnit(_ f: CGFloat) -> CGFloat {
        let lo = range.lowerBound
        if f <= midPoint {
            let a = (f - lo) / max(midPoint - lo, 0.001)
            return a * midFraction
        }
        let b = (f - midPoint) / max(dialMax - midPoint, 0.001)
        return midFraction + b * (1 - midFraction)
    }

    /// 归一化位置 → 倍率
    private func unitToFactor(_ u: CGFloat) -> CGFloat {
        let lo = range.lowerBound
        if u <= midFraction {
            return lo + (u / midFraction) * (midPoint - lo)
        }
        return midPoint + ((u - midFraction) / (1 - midFraction)) * (dialMax - midPoint)
    }

    private func xFor(_ factor: CGFloat, width: CGFloat) -> CGFloat {
        edgePadding + factorToUnit(factor) * (width - 2 * edgePadding)
    }

    private func factorAt(x: CGFloat, width: CGFloat) -> CGFloat {
        let u = (x - edgePadding) / max(width - 2 * edgePadding, 1)
        return min(max(unitToFactor(u), range.lowerBound), dialMax)
    }

    private func dialView(width: CGFloat) -> some View {
        // 刻度：0.5~2 区间每 0.5 一格，2 以上每 1 一格
        var ticks: [CGFloat] = []
        var t = range.lowerBound
        while t <= midPoint + 0.001 {
            ticks.append(t)
            t += 0.5
        }
        t = midPoint + 1
        while t <= dialMax + 0.001 {
            ticks.append(min(t, dialMax))
            t += 1
        }

        // 远端稀疏标注（近端已有焦段标签）；
        // 与焦段标签或其他数字距离 <16pt 时跳过，避免窄盘上文字互相压叠
        let presetXs = sortedPresets.map { xFor($0.zoomFactor, width: width) }
        var placedXs = presetXs
        var farLabels: [CGFloat] = []
        for value in [5.0, 10.0, 15.0, 20.0, 25.0] where CGFloat(value) <= dialMax {
            let x = xFor(CGFloat(value), width: width)
            if placedXs.allSatisfy({ abs($0 - x) >= 16 }) {
                farLabels.append(CGFloat(value))
                placedXs.append(x)
            }
        }

        return ZStack {
            RoundedRectangle(cornerRadius: controlHeight / 2, style: .continuous)
                .fill(Color.black.opacity(0.6))
                .frame(height: controlHeight)

            // 刻度点
            ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                let isInteger = tick.rounded() == tick
                Circle()
                    .fill(Color.white.opacity(isInteger ? 0.5 : 0.22))
                    .frame(width: isInteger ? 4 : 3, height: isInteger ? 4 : 3)
                    .position(x: xFor(tick, width: width), y: controlHeight / 2)
            }

            // 焦段标签（最近的放大）
            ForEach(sortedPresets, id: \.id) { preset in
                let isNear = abs(preset.zoomFactor - dialFactor) < 0.15
                Text(compactLabel(preset))
                    .font(.system(size: isNear ? 19 : 13, weight: .bold, design: .rounded))
                    .foregroundColor(isNear ? .white : .white.opacity(0.55))
                    .position(x: xFor(preset.zoomFactor, width: width), y: controlHeight / 2)
            }

            // 远端数字（整数格式，避免 CGFloat 插值渲染成 "5.0" 这种长文本）
            ForEach(farLabels, id: \.self) { value in
                let isNear = abs(value - dialFactor) < 0.5
                Text("\(Int(value))")
                    .font(.system(size: isNear ? 19 : 13, weight: .bold, design: .rounded))
                    .foregroundColor(isNear ? .white : .white.opacity(0.55))
                    .position(x: xFor(value, width: width), y: controlHeight / 2)
            }

            // 当前位置指示
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
                .position(x: xFor(dialFactor, width: width), y: controlHeight / 2)

            // 指尖上方的当前倍率
            Text(zoomText(dialFactor))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.92)))
                .position(x: min(max(fingerX, edgePadding + 18), width - edgePadding - 18),
                          y: -8)
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
                        dialFactor = min(max(currentFactor, range.lowerBound), dialMax)
                        lastSentFactor = dialFactor
                        lastSentTime = Date()
                        lastHapticStep = hapticStep(for: dialFactor)
                        HapticManager.shared.soft()
                    } else if hitPreset == nil {
                        hitPreset = presetAt(x: value.location.x, width: width)
                    }
                    return
                }

                // 相对起点的分段线性映射（拖动不跳变）
                let startUnit = factorToUnit(min(max(dialStartFactor, range.lowerBound), dialMax))
                let pxPerUnit = max(width - 2 * edgePadding, 1)
                let unit = startUnit + value.translation.width / pxPerUnit
                dialFactor = min(max(unitToFactor(unit), range.lowerBound), dialMax)

                // 每 0.25×（近段）/ 1×（远段）一次选择触觉反馈
                let step = hapticStep(for: dialFactor)
                if step != lastHapticStep {
                    lastHapticStep = step
                    HapticManager.shared.selection()
                }

                // 下发节流：≥30ms 且步长 ≥0.01，视觉更新不受影响
                let now = Date()
                if now.timeIntervalSince(lastSentTime) >= 0.03,
                   abs(dialFactor - lastSentFactor) >= 0.01 {
                    lastSentFactor = dialFactor
                    lastSentTime = now
                    onLiveZoom(dialFactor)
                }
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
                        HapticManager.shared.soft()
                        onPresetTap(preset)
                    }
                }
                hitPreset = nil
            }
    }

    /// 触觉步进：近段每 0.25× 一档，远段每 1× 一档
    private func hapticStep(for factor: CGFloat) -> Int {
        factor < midPoint ? Int(factor * 4) : Int(factor) + 1000
    }

    // MARK: - 文案

    /// 命中测试：胶囊上指下的焦段槽位（与 pillView 的等分槽位布局一致）。
    /// 命中区向外扩 12pt，减少"点在按钮附近却没反应"的情况
    private func presetAt(x: CGFloat, width: CGFloat) -> CameraManager.ZoomPreset? {
        let items = sortedPresets
        guard !items.isEmpty else { return nil }
        let pillX0 = (width - pillWidth) / 2
        let slotW = pillWidth / CGFloat(items.count)
        let localX = min(max(x, pillX0 - 12), pillX0 + pillWidth + 12) - pillX0
        let index = min(max(Int(localX / slotW), 0), items.count - 1)
        return items[index]
    }

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
