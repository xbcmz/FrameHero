import SwiftUI
import PhotosUI

struct GalleryView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var selectedPhotoIndex: Int?
    @State private var isSelectionMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showDeleteConfirm = false
    /// 从系统相册导入的选择结果（PhotosPicker 不需要完整相册权限，选什么给什么）
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // 顶部栏
                    HStack {
                        Text("图库")
                            .font(DesignSystem.Typography.largeTitle)
                            .foregroundColor(DesignSystem.Colors.textPrimary)

                        Spacer()

                        if isSelectionMode {
                            // 已选计数
                            Text("已选 \(selectedIDs.count)")
                                .font(DesignSystem.Typography.footnote)
                                .foregroundColor(DesignSystem.Colors.textTertiary)

                            // 全选
                            Button("全选") {
                                selectedIDs = Set(viewModel.records.map(\.id))
                            }
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundColor(DesignSystem.Colors.primary)
                            .disabled(selectedIDs.count == viewModel.records.count)

                            // 删除（带确认）
                            Button("删除") {
                                showDeleteConfirm = true
                            }
                            .font(DesignSystem.Typography.subheadline.weight(.semibold))
                            .foregroundColor(selectedIDs.isEmpty ? DesignSystem.Colors.textTertiary : .red)
                            .disabled(selectedIDs.isEmpty)

                            Button("取消") {
                                isSelectionMode = false
                                selectedIDs.removeAll()
                            }
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        } else {
                            if !viewModel.records.isEmpty {
                                Text("\(viewModel.records.count) 张照片")
                                    .font(DesignSystem.Typography.caption1)
                                    .foregroundColor(DesignSystem.Colors.textTertiary)

                                // 显式多选入口（iOS 相册模式）
                                Button("选择") {
                                    isSelectionMode = true
                                }
                                .font(DesignSystem.Typography.subheadline.weight(.semibold))
                                .foregroundColor(DesignSystem.Colors.primary)
                            }

                            importPickerButton
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                    if !isSelectionMode && !viewModel.records.isEmpty {
                        guidanceBanner
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    }

                    if viewModel.isImporting, let progress = viewModel.importProgress {
                        importProgressBanner(progress)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    }

                    if viewModel.records.isEmpty {
                        emptyStateView
                    } else {
                        photoGrid
                            .padding(.horizontal, 2)
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarHidden(true)
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                let itemsToImport = items
                pickerItems = []
                Task { await viewModel.importPhotos(from: itemsToImport) }
            }
            .navigationDestination(item: $selectedPhotoIndex) { index in
                PhotoBrowserView(
                    records: viewModel.records,
                    initialIndex: index,
                    photoProvider: { [weak viewModel] id in
                        viewModel?.fullPhoto(for: id)
                    }
                )
            }
            .confirmationDialog(
                "删除 \(selectedIDs.count) 张照片？",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    viewModel.deleteRecords(Array(selectedIDs))
                    selectedIDs.removeAll()
                    isSelectionMode = false
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后无法恢复")
            }
        }
    }

    // MARK: - Guidance

    private var guidanceBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(DesignSystem.Colors.primary)
            Text("点击照片浏览 · 「选择」多选删除 · 进入照片可导出卡片")
                .font(DesignSystem.Typography.caption1)
                .foregroundColor(DesignSystem.Colors.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DesignSystem.Colors.backgroundSecondary)
        )
    }

    // MARK: - Photo Grid

    private var photoGrid: some View {
        LazyVGrid(
            columns: Array(repeating: .init(.flexible(), spacing: 2), count: 3),
            spacing: 2
        ) {
            ForEach(Array(viewModel.records.enumerated()), id: \.element.id) { index, record in
                Button {
                    if isSelectionMode {
                        toggleSelection(record.id)
                    } else {
                        selectedPhotoIndex = index
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        PhotoCard(
                            record: record,
                            thumbnailProvider: { [weak viewModel] id in
                                viewModel?.thumbnail(for: id)
                            }
                        )

                        if isSelectionMode {
                            RoundedRectangle(cornerRadius: 0)
                                .fill(Color.black.opacity(0.4))

                            Image(systemName: selectedIDs.contains(record.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundColor(selectedIDs.contains(record.id) ? DesignSystem.Colors.primary : .white.opacity(0.7))
                                .padding(6)
                        }
                    }
                }
                .contextMenu { contextMenu(for: record) }
            }
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            if selectedIDs.isEmpty {
                isSelectionMode = false
            }
        } else {
            selectedIDs.insert(id)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for record: PhotoRecord) -> some View {
        Button {
            isSelectionMode = true
            selectedIDs = [record.id]
        } label: {
            Label("多选", systemImage: "checkmark.circle")
        }

        Button(role: .destructive) {
            viewModel.deleteRecord(record.id)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    // MARK: - 从相册导入

    /// 导入入口按钮（PhotosPicker 自身就是可点击的触发视图，不需要额外的 sheet 状态）
    private var importPickerButton: some View {
        PhotosPicker(selection: $pickerItems, maxSelectionCount: 30, matching: .images) {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                Text("导入")
            }
            .font(DesignSystem.Typography.subheadline.weight(.semibold))
            .foregroundColor(DesignSystem.Colors.primary)
        }
        .disabled(viewModel.isImporting)
    }

    private func importProgressBanner(_ progress: (done: Int, total: Int)) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("正在导入并 AI 打分 \(progress.done)/\(progress.total) 张照片…")
                .font(DesignSystem.Typography.caption1)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(DesignSystem.Colors.backgroundSecondary)
        )
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Spacer().frame(height: 60)
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 56))
                .foregroundColor(DesignSystem.Colors.textTertiary)
            Text("暂无照片")
                .font(DesignSystem.Typography.title3)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            Text("使用下方拍摄按钮开始创作，或从相册导入照片让 AI 打分")
                .font(DesignSystem.Typography.subheadline)
                .foregroundColor(DesignSystem.Colors.textTertiary)

            importPickerButton
                .padding(.top, 4)
        }
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}
