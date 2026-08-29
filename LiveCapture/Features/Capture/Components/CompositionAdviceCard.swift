//
//  CompositionAdviceCard.swift
//  LiveCapture
//
//  构图建议卡片 UI 组件
//
//  显示在相机预览界面上，展示：
//  - 构图总分
//  - 分项得分进度条
//  - AI 摄影建议文字
//  - 推荐拍摄风格
//

import SwiftUI

/// 构图建议卡片
struct CompositionAdviceCard: View {
    
    let result: PhotographyAnalysisResult
    let isLoading: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 顶部：总分 + 标题
            HStack(alignment: .top, spacing: 12) {
                // 分数圆环
                scoreRing
                    .frame(width: 52, height: 52)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(aiTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
            }
            
            // 分项得分
            scoreBreakdownView
            
            // AI 建议文字
            if let advice = result.aiAdvice, !advice.adviceText.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.2))
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)
                        Text("AI 建议")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Spacer()
                        
                        if !advice.isRealAI {
                            Text("模拟")
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.2))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(advice.adviceText)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            // 推荐风格
            if let style = result.aiAdvice?.suggestedStyle {
                HStack {
                    Image(systemName: "camera.filters")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                    Text("推荐风格：\(style)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            // AI 相机参数建议（Phase 4）
            cameraParamsRow
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - 子视图
    
    /// 分数圆环
    private var scoreRing: some View {
        let score = result.composition.score
        let progress = Double(score) / 100.0
        let color = scoreColor(for: score)
        
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 4)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            
            Text("\(score)")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    /// 分项得分
    private var scoreBreakdownView: some View {
        let breakdown = result.composition.scoreBreakdown
        
        return VStack(spacing: 6) {
            scoreBar(label: "位置", score: breakdown.positionScore, color: .blue)
            scoreBar(label: "完整", score: breakdown.subjectIntegrityScore, color: .green)
            scoreBar(label: "留白", score: breakdown.headRoomScore, color: .orange)
            scoreBar(label: "边距", score: breakdown.edgeDistanceScore, color: .purple)
            scoreBar(label: "大小", score: breakdown.sizeScore, color: .pink)
        }
    }
    
    private func scoreBar(label: String, score: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 32, alignment: .leading)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.9))
                        .frame(width: geo.size.width * CGFloat(score) / 100, height: 6)
                }
            }
            .frame(height: 6)
            
            Text("\(score)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 24, alignment: .trailing)
        }
    }
    
    // MARK: - 辅助属性
    
    private var aiTitle: String {
        if let advice = result.aiAdvice, !advice.title.isEmpty {
            return advice.title
        }
        return "构图分析中"
    }
    
    private var subtitle: String {
        let person = result.composition.person
        if !person.detected {
            return "未检测到人物"
        }
        
        let position = result.composition.subjectPosition.displayName
        let sizePercent = Int(person.heightRatio * 100)
        return "\(position) · 人物占比 \(sizePercent)%"
    }
    
    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 85...: return .green
        case 70...: return .yellow
        case 55...: return .orange
        default:    return .red
        }
    }
    
    // MARK: - AI 相机参数建议（Phase 4）
    
    /// AI 相机参数建议行（4 个 icon + 文字）
    @ViewBuilder
    private var cameraParamsRow: some View {
        let strategy = result.cameraStrategy
        
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .background(Color.white.opacity(0.2))
            
            HStack(spacing: 4) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 12))
                    .foregroundColor(.blue.opacity(0.9))
                Text("AI 相机参数")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            HStack(spacing: 12) {
                // 镜头
                paramChip(
                    icon: "camera.viewfinder",
                    label: strategy.lensPreference.displayName
                )
                
                // 对焦
                paramChip(
                    icon: "focus",
                    label: strategy.focusPreference.displayName
                )
                
                // 白平衡
                paramChip(
                    icon: "thermometer",
                    label: strategy.whiteBalancePreference.displayName
                )
                
                // 景深
                paramChip(
                    icon: "square.stack.3d.down.forward.fill",
                    label: strategy.depthPreference.displayName
                )
            }
        }
    }
    
    private func paramChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 11))
        }
        .foregroundColor(.white.opacity(0.7))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - 预览

struct CompositionAdviceCard_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray
            CompositionAdviceCard(
                result: PhotographyAnalysisResult(
                    composition: CompositionResult(
                        score: 76,
                        person: PersonInfo(
                            detected: true,
                            centerX: 0.35,
                            centerY: 0.45,
                            widthRatio: 0.3,
                            heightRatio: 0.7,
                            headRoom: 0.15,
                            isFullBody: true,
                            confidence: 0.95
                        ),
                        faceCount: 1,
                        bodyCount: 1,
                        subjectPosition: .leftThird,
                        compositionType: .ruleOfThirds,
                        recommendedMove: .moveRight,
                        recommendedLens: .telephoto2x,
                        recommendedCameraHeight: .eyeLevel
                    ),
                    target: CompositionTarget(
                        targetCenterX: 0.667,
                        targetCenterY: 0.58,
                        targetWidthRatio: 0.4,
                        targetHeightRatio: 0.75,
                        targetHeadRoom: 0.12,
                        preferredLens: .telephoto2x,
                        compositionStyle: .ruleOfThirds,
                        targetScore: 88,
                        adviceTitle: "往右移一点",
                        adviceText: "人物往右移\n换 2x 长焦",
                        suggestedStyle: "电影感"
                    ),
                    aiAdvice: AIAdviceResult(
                        adviceText: "人物稍微往右一点，把左侧的建筑留出来。\n建议使用 2x，人物和背景的层次会更自然。",
                        suggestedStyle: "电影感",
                        title: "构图不错",
                        isRealAI: false
                    )
                ),
                isLoading: false
            )
        }
        .previewLayout(.sizeThatFits)
    }
}
