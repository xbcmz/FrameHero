import SwiftUI

/// 首页：AI 摄影工作台
///
/// 定位是"每次打开都能用的仪表盘"，不是产品介绍页：
/// 问候语 → 大型拍摄入口 → AI 助手实时状态 → 最近拍摄 → 今日数据。
/// 所有状态来自真实数据源（AIConfigurationStore / PhotoStorageService /
/// AIUsageCounter），跨 Tab 导航走 AppRouter。
struct HomeView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject private var aiConfig = AIConfigurationStore.shared
    @AppStorage("aiAdviceEnabled") private var aiAdviceEnabled: Bool = false
    @AppStorage("detectionMode") private var detectionMode: DetectionMode = .fast

    @State private var adviceCountToday: Int = 0
    @State private var adviceCountTotal: Int = 0
    @State private var selectedPhotoIndex: Int?

    /// 日期显示（统计卡头部），固定中文格式
    private static let todayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                    headerSection

                    captureHeroCard

                    assistantStatusCard

                    if !viewModel.records.isEmpty {
                        recentPhotosSection
                    }

                    todayStatsCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedPhotoIndex) { index in
                PhotoBrowserView(
                    records: viewModel.records,
                    initialIndex: index,
                    photoProvider: { [weak viewModel] id in
                        viewModel?.fullPhoto(for: id)
                    }
                )
            }
        }
        .onAppear {
            refreshUsageStats()
        }
        .onChange(of: viewModel.records.count) { _, _ in
            refreshUsageStats()
        }
    }

    private func refreshUsageStats() {
        adviceCountToday = AIUsageCounter.adviceCountToday
        adviceCountTotal = AIUsageCounter.adviceCountTotal
    }

    // MARK: - 顶部问候

    private var greetingText: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return "早上好"
        case 11..<13: return "中午好"
        case 13..<18: return "下午好"
        default: return "晚上好"
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(greetingText) 👋")
                .font(DesignSystem.Typography.subheadline)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            Text("FrameHero")
                .font(DesignSystem.Typography.largeTitle)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            Text("让 AI 帮你拍出更好的照片")
                .font(DesignSystem.Typography.subheadline)
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
        .padding(.top, 8)
    }

    // MARK: - 开始拍摄入口

    private var captureHeroCard: some View {
        Button {
            HapticManager.shared.medium()
            router.openCamera()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .fill(DesignSystem.Colors.primaryGradient)

                // 装饰性光斑，让主入口有"活"的感觉
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 160, height: 160)
                    .offset(x: 130, y: -60)
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 110, height: 110)
                    .offset(x: 60, y: 70)

                HStack(spacing: DesignSystem.Spacing.medium) {
                    VStack(alignment: .leading, spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.22))
                                .frame(width: 46, height: 46)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("开始 AI 拍摄")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("AI 构图 · 人物检测 · 实时建议")
                                .font(DesignSystem.Typography.footnote)
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.22)))
                }
                .padding(20)
            }
            .frame(height: 150)
        }
        .buttonStyle(.plain)
    }

    // MARK: - AI 助手状态

    private var assistantStatusCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AI 拍摄助手")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Spacer()
                Button {
                    HapticManager.shared.light()
                    router.openSettings()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, 12)

            Divider()
                .background(DesignSystem.Colors.backgroundSecondary)

            assistantStatusRow(
                icon: "sparkles",
                title: "AI 构图引导",
                status: aiAdviceEnabled ? "已开启" : "已关闭",
                isActive: aiAdviceEnabled
            )

            Divider()
                .background(DesignSystem.Colors.backgroundSecondary)

            assistantStatusRow(
                icon: "wand.and.rays.inverse",
                title: "场景识别",
                status: aiAdviceEnabled ? "已开启" : "已关闭",
                isActive: aiAdviceEnabled
            )

            Divider()
                .background(DesignSystem.Colors.backgroundSecondary)

            assistantStatusRow(
                icon: "person.fill.viewfinder",
                title: "人物检测",
                status: detectionEngineText,
                isActive: true
            )
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.backgroundSecondary)
        )
    }

    /// AI 构图入口状态（场景识别 + 实时引导均为本地推理，零延迟）
    private var aiAdviceStatus: String {
        aiAdviceEnabled ? "已开启" : "已关闭"
    }

    /// 人物检测引擎名（跟随设置页的构图引擎选择）
    private var detectionEngineText: String {
        switch detectionMode {
        case .vision: return "Vision 引擎"
        case .fast: return "Fast 引擎"
        case .pro: return "Pro 引擎"
        }
    }

    private func assistantStatusRow(icon: String, title: String, status: String, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(isActive ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
                .frame(width: 24)

            Text(title)
                .font(DesignSystem.Typography.subheadline)
                .foregroundColor(DesignSystem.Colors.textPrimary)

            Spacer()

            // 状态点 + 状态文字：绿色 = 已开启/可用，灰色 = 关闭
            Circle()
                .fill(isActive ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(status)
                .font(DesignSystem.Typography.footnote)
                .foregroundColor(isActive ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, 12)
    }

    // MARK: - 最近拍摄

    private var recentPhotosSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack {
                Text("最近拍摄")
                    .font(DesignSystem.Typography.title3)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Spacer()
                Button {
                    router.openGallery()
                } label: {
                    HStack(spacing: 2) {
                        Text("查看全部")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(DesignSystem.Typography.footnote)
                    .foregroundColor(DesignSystem.Colors.primary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.recentRecords.enumerated()), id: \.element.id) { index, record in
                        Button {
                            selectedPhotoIndex = index
                        } label: {
                            recentPhotoCard(record)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func recentPhotoCard(_ record: PhotoRecord) -> some View {
        ZStack(alignment: .topTrailing) {
            PhotoCard(
                record: record,
                thumbnailProvider: { [weak viewModel] id in
                    viewModel?.thumbnail(for: id)
                }
            )
            .frame(width: 108, height: 144)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))

            if let score = record.compositionScore {
                Text("\(score)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(scoreColor(score).opacity(0.92))
                    )
                    .padding(6)
            }
        }
    }

    /// 评分配色：≥80 绿（好）· ≥60 黄（一般）· 其余灰（待改进）
    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return DesignSystem.Colors.success }
        if score >= 60 { return DesignSystem.Colors.warning }
        return DesignSystem.Colors.textTertiary
    }

    // MARK: - 今日数据

    private var todayStatsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("今天")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Spacer()
                Text(Self.todayFormatter.string(from: Date()))
                    .font(DesignSystem.Typography.caption1)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, 12)

            Divider()
                .background(DesignSystem.Colors.backgroundSecondary)

            HStack(spacing: 0) {
                statColumn(
                    value: "\(viewModel.todayPhotoCount)",
                    label: "拍摄照片"
                )

                Divider()
                    .frame(height: 36)
                    .background(DesignSystem.Colors.backgroundSecondary)

                statColumn(
                    value: "\(adviceCountToday)",
                    label: "AI 建议"
                )

                Divider()
                    .frame(height: 36)
                    .background(DesignSystem.Colors.backgroundSecondary)

                statColumn(
                    value: viewModel.todayAverageScore.map { "\($0)" } ?? "—",
                    label: "平均评分"
                )
            }
            .padding(.vertical, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.backgroundSecondary)
        )
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
            Text(label)
                .font(DesignSystem.Typography.caption1)
                .foregroundColor(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
