import SwiftUI
import Photos

struct PhotoBrowserView: View {
    let records: [PhotoRecord]
    let initialIndex: Int
    let photoProvider: (UUID) -> UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var showExportSheet = false
    @State private var exportImage: UIImage?
    /// 原图直出时保存的原始 JPEG 字节（不经重编码）
    @State private var exportRawData: Data?
    @State private var isGenerating = false
    @State private var saveSuccess = false
    @State private var loadedPhotos: [UUID: UIImage] = [:]
    /// 导出样式：信息卡片（含日期/参数，无品牌水印）或原图直出。
    /// AppStorage 持久化，下次导出沿用上次选择
    @AppStorage("exportUsesCard") private var exportUsesCard = true

    init(records: [PhotoRecord], initialIndex: Int, photoProvider: @escaping (UUID) -> UIImage?) {
        self.records = records
        self.initialIndex = initialIndex
        self.photoProvider = photoProvider
        self._currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部栏
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("返回")
                                .font(DesignSystem.Typography.subheadline)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                    }

                    Spacer()

                    Text("\(currentIndex + 1) / \(records.count)")
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundColor(DesignSystem.Colors.textTertiary)

                    Spacer()

                    Button {
                        prepareExport()
                    } label: {
                        if isGenerating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                    }
                    .disabled(isGenerating)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // 照片浏览器
                TabView(selection: $currentIndex) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        Group {
                            if let photo = loadedPhotos[record.id] {
                                Image(uiImage: photo)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .tag(index)
                            } else {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                                    .tag(index)
                                    .onAppear {
                                        loadPhoto(for: record)
                                    }
                            }
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // 底部信息
                if let record = records[safe: currentIndex] {
                    metadataSection(record)
                        .padding(.bottom, 16)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showExportSheet) {
            exportPreviewView
        }
    }

    // MARK: - Export Preview

    private var exportPreviewView: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 导出样式切换（选择持久化，下次导出沿用）
                Picker("导出样式", selection: $exportUsesCard) {
                    Text("信息卡片").tag(true)
                    Text("原图直出").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .onChange(of: exportUsesCard) { _, _ in
                    regenerateExport()
                }

                if let exportImage {
                    Image(uiImage: exportImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(16)

                    // 操作按钮
                    VStack(spacing: 12) {
                        Button {
                            saveExport()
                        } label: {
                            HStack {
                                Image(systemName: saveSuccess ? "checkmark.circle.fill" : "square.and.arrow.down")
                                Text(saveSuccess ? "已保存" : "保存到相册")
                            }
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(saveSuccess ? DesignSystem.Colors.success : DesignSystem.Colors.primary)
                            )
                        }
                        .disabled(saveSuccess)
                        .padding(.horizontal, 16)

                        Text(exportUsesCard ? "含拍摄日期与参数的信息卡片" : "保存原始 JPEG 照片，无任何装饰")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                    }
                    .padding(.bottom, 24)
                } else {
                    Spacer()
                    ProgressView(exportUsesCard ? "正在生成分享卡片..." : "正在载入原图...")
                    Spacer()
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("导出预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        showExportSheet = false
                        saveSuccess = false
                    }
                }
            }
        }
    }

    // MARK: - Metadata Section

    private func metadataSection(_ record: PhotoRecord) -> some View {
        VStack(spacing: 6) {
            Text(formattedDate(record.creationDate))
                .font(DesignSystem.Typography.subheadline)
                .foregroundColor(DesignSystem.Colors.textTertiary)

            HStack(spacing: 16) {
                MetadataBadge(label: record.detectionMethod ?? "未知引擎")

                if let iso = record.iso {
                    MetadataBadge(label: "ISO \(Int(iso))")
                }

                if let shutter = record.shutterSpeed {
                    MetadataBadge(label: shutterDisplay(shutter))
                }

                if let aperture = record.aperture {
                    MetadataBadge(label: "f/\(String(format: "%.1f", aperture))")
                }
            }

            if let w = record.imageWidth, let h = record.imageHeight {
                Text("\(w) × \(h)")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.textTertiary.opacity(0.5))
            }
        }
    }

    // MARK: - Helpers

    private func loadPhoto(for record: PhotoRecord) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let photo = photoProvider(record.id) {
                DispatchQueue.main.async {
                    loadedPhotos[record.id] = photo
                }
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func shutterDisplay(_ speed: Double) -> String {
        if speed >= 1 { return "\(Int(speed))s" }
        else { return "1/\(Int(1.0 / speed))s" }
    }

    // MARK: - Export

    private func prepareExport() {
        guard let record = records[safe: currentIndex] else { return }
        isGenerating = true
        showExportSheet = true
        generateExport(for: record)
    }

    /// 导出预览里切换样式后重新生成
    private func regenerateExport() {
        guard let record = records[safe: currentIndex] else { return }
        exportImage = nil
        exportRawData = nil
        isGenerating = true
        generateExport(for: record)
    }

    private func generateExport(for record: PhotoRecord) {
        if exportUsesCard {
            exportRawData = nil
            if let photo = loadedPhotos[record.id] {
                generateCard(from: photo, record: record)
            } else {
                // 尚未加载，先加载
                DispatchQueue.global(qos: .userInitiated).async {
                    if let photo = photoProvider(record.id) {
                        DispatchQueue.main.async {
                            loadedPhotos[record.id] = photo
                            generateCard(from: photo, record: record)
                        }
                    }
                }
            }
        } else {
            // 原图直出：读存储的原始 JPEG 字节，不经重编码
            DispatchQueue.global(qos: .userInitiated).async {
                let data = PhotoStorageService.shared.photoData(for: record.id)
                DispatchQueue.main.async {
                    exportRawData = data
                    exportImage = data.flatMap(UIImage.init)
                    isGenerating = false
                }
            }
        }
    }

    private func generateCard(from photo: UIImage, record: PhotoRecord) {
        DispatchQueue.global(qos: .userInitiated).async {
            let card = ShareCardGenerator.generate(
                photo: photo,
                date: record.creationDate,
                detectionMethod: record.detectionMethod,
                iso: record.iso,
                shutterSpeed: record.shutterSpeed,
                aperture: record.aperture,
                imageWidth: record.imageWidth,
                imageHeight: record.imageHeight
            )
            DispatchQueue.main.async {
                isGenerating = false
                exportImage = card
            }
        }
    }

    private func saveExport() {
        // 原图直出存原始 JPEG 字节；卡片模式存渲染 PNG
        guard let data = exportRawData ?? exportImage?.pngData() else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }) { success, _ in
                DispatchQueue.main.async {
                    if success {
                        saveSuccess = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showExportSheet = false
                            saveSuccess = false
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Metadata Badge

private struct MetadataBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(DesignSystem.Colors.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(DesignSystem.Colors.backgroundSecondary)
            )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
