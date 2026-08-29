import SwiftUI

struct HomeView: View {
    @Environment(\.openURL) private var openURL
    @State private var selectedFeature: FeatureType?
    
    enum FeatureType: String, Identifiable {
        case vision, composition, deepseek, motion, multiLens
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.large) {
                    heroSection
                    
                    featuresSection
                    
                    howItWorksSection
                    
                    techStackSection
                    
                    roadmapSection
                    
                    aboutSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarHidden(true)
        }
    }
    
    // MARK: - Hero 顶部
    
    private var heroSection: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            Spacer().frame(height: 40)
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.primary.opacity(0.3),
                                DesignSystem.Colors.primary.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)
                
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            .frame(width: 100, height: 100)
            
            Text("AI 摄影助手")
                .font(DesignSystem.Typography.largeTitle)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Text("让每一张照片，都更出片")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Spacer().frame(height: 8)
            
            // 快速入口
            HStack(spacing: 12) {
                quickActionButton(
                    icon: "camera.fill",
                    title: "开始拍摄",
                    color: DesignSystem.Colors.primary
                ) {
                    NotificationCenter.default.post(name: .startCapture, object: nil)
                }
                
                quickActionButton(
                    icon: "photo.on.rectangle",
                    title: "查看照片",
                    color: DesignSystem.Colors.textSecondary
                ) {
                    NotificationCenter.default.post(name: .showGallery, object: nil)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func quickActionButton(
        icon: String,
        title: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(DesignSystem.Typography.subheadline)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(color)
            )
        }
    }
    
    // MARK: - 核心功能
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            SectionHeader(icon: "sparkles", title: "核心功能")
            
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                spacing: 12
            ) {
                FeatureCard(
                    icon: "person.fill.viewfinder",
                    title: "人物检测",
                    desc: "识别人脸与人体位置",
                    color: .blue
                )
                FeatureCard(
                    icon: "chart.bar.fill",
                    title: "构图评分",
                    desc: "五维度实时打分",
                    color: .purple
                )
                FeatureCard(
                    icon: "message.badge.waveform.fill",
                    title: "AI 建议",
                    desc: "DeepSeek 智能指导",
                    color: .green
                )
                FeatureCard(
                    icon: "gyroscope",
                    title: "陀螺仪追踪",
                    desc: "物理级运动感知",
                    color: .orange
                )
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .background(cardBackground)
    }
    
    // MARK: - 工作原理
    
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            SectionHeader(icon: "arrow.triangle.2.circlepath", title: "工作原理")
            
            VStack(spacing: 0) {
                workStepRow(
                    number: "1",
                    title: "实时取景",
                    desc: "相机捕捉画面，每秒 30 帧",
                    icon: "camera"
                )
                Divider().background(DesignSystem.Colors.backgroundSecondary)
                workStepRow(
                    number: "2",
                    title: "Vision 分析",
                    desc: "Apple 原生框架检测人脸与人体",
                    icon: "eye"
                )
                Divider().background(DesignSystem.Colors.backgroundSecondary)
                workStepRow(
                    number: "3",
                    title: "构图引擎",
                    desc: "五维度评分 + 推荐方向计算",
                    icon: "square.grid.2x2"
                )
                Divider().background(DesignSystem.Colors.backgroundSecondary)
                workStepRow(
                    number: "4",
                    title: "AI 建议",
                    desc: "DeepSeek 生成自然语言指导",
                    icon: "brain"
                )
            }
            .background(cardBackground)
        }
    }
    
    private func workStepRow(number: String, title: String, desc: String, icon: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.primary.opacity(0.15))
                    .frame(width: 32, height: 32)
                Text(number)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text(desc)
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
        .padding(DesignSystem.Spacing.medium)
    }
    
    // MARK: - 技术栈
    
    private var techStackSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            SectionHeader(icon: "gearshape.2", title: "技术栈")
            
            VStack(spacing: 0) {
                techRow("swift", "SwiftUI + AVFoundation",
                        "原生相机框架，高性能低延迟")
                Divider().background(DesignSystem.Colors.backgroundSecondary)
                techRow("eye", "Apple Vision",
                        "人脸/人体/显著性区域检测，完全离线运行")
                Divider().background(DesignSystem.Colors.backgroundSecondary)
                techRow("cpu.fill", "CoreML",
                        "AdaCrop 美学裁切模型，端侧推理")
                Divider().background(DesignSystem.Colors.backgroundSecondary)
                techRow("gyroscope", "CoreMotion",
                        "陀螺仪 + 加速度计，物理级运动追踪")
                Divider().background(DesignSystem.Colors.backgroundSecondary)
                techRow("cloud.fill", "DeepSeek API",
                        "大语言模型生成自然语言摄影建议")
            }
            .background(cardBackground)
        }
    }
    
    private func techRow(_ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(DesignSystem.Colors.primary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text(desc)
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .lineSpacing(3)
            }
        }
        .padding(DesignSystem.Spacing.medium)
    }
    
    // MARK: - 路线图
    
    private var roadmapSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            SectionHeader(icon: "map", title: "版本规划")
            
            VStack(alignment: .leading, spacing: 12) {
                roadmapItem(version: "V1", title: "AI 构图助手", status: "已完成", done: true)
                roadmapItem(version: "V2", title: "实时构图指导", status: "规划中", done: false)
                roadmapItem(version: "V3", title: "ARKit 机位推荐", status: "规划中", done: false)
                roadmapItem(version: "V4", title: "视觉大模型", status: "规划中", done: false)
                roadmapItem(version: "V5", title: "本地美学模型", status: "规划中", done: false)
                roadmapItem(version: "V6", title: "个人审美学习", status: "规划中", done: false)
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .background(cardBackground)
    }
    
    private func roadmapItem(version: String, title: String, status: String, done: Bool) -> some View {
        HStack(spacing: 12) {
            Text(version)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(done ? .white : DesignSystem.Colors.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(done ? DesignSystem.Colors.primary : DesignSystem.Colors.backgroundTertiary)
                )
            
            Text(title)
                .font(DesignSystem.Typography.subheadline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Spacer()
            
            Text(status)
                .font(DesignSystem.Typography.caption2)
                .foregroundColor(done ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
            
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundColor(done ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
        }
    }
    
    // MARK: - 关于
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            SectionHeader(icon: "info.circle", title: "关于")
            
            VStack(alignment: .leading, spacing: 8) {
                Text("基于开源项目 LiveCompose/LiveCapture 二次开发，仅供个人学习与使用。")
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .lineSpacing(3)
                
                Link(destination: URL(string: "https://github.com/LiveCompose/LiveCapture")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("LiveCapture on GitHub")
                            .font(DesignSystem.Typography.caption1)
                            .underline()
                    }
                    .foregroundColor(DesignSystem.Colors.primary)
                }
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .background(cardBackground)
    }
    
    // MARK: - Helpers
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
            .fill(DesignSystem.Colors.backgroundSecondary)
    }
}

// MARK: - Shared Components

private struct SectionHeader: View {
    let icon: String
    let title: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.primary)
            Text(title)
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.textPrimary)
        }
    }
}

private struct FeatureCard: View {
    let icon: String
    let title: String
    let desc: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text(desc)
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                .fill(DesignSystem.Colors.backgroundTertiary)
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let startCapture = Notification.Name("startCapture")
    static let showGallery = Notification.Name("showGallery")
}
