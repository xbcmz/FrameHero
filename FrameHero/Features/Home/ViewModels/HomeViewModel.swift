import Foundation
import Combine
import UIKit
import SwiftUI
import PhotosUI

final class HomeViewModel: ObservableObject {
    @Published private(set) var records: [PhotoRecord] = []
    /// 从系统相册导入中（批量导入时需要一个进度 UI）
    @Published private(set) var isImporting = false
    @Published private(set) var importProgress: (done: Int, total: Int)?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        PhotoStorageService.shared.recordsPublisher
            .receive(on: DispatchQueue.main)
            .map { $0.sorted { $0.creationDate > $1.creationDate } }
            .sink { [weak self] records in
                self?.records = records
            }
            .store(in: &cancellables)
    }

    // MARK: - 首页统计

    /// 今天的拍摄数量
    var todayPhotoCount: Int {
        records.filter { Calendar.current.isDateInToday($0.creationDate) }.count
    }

    /// 今天照片的平均 AI 构图评分（没有带评分的照片时为 nil）
    var todayAverageScore: Int? {
        let scores = records
            .filter { Calendar.current.isDateInToday($0.creationDate) }
            .compactMap { $0.compositionScore }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / scores.count
    }

    /// 最近拍摄（首页横滑预览用，新→旧）
    var recentRecords: ArraySlice<PhotoRecord> {
        records.prefix(8)
    }

    // MARK: - 照片访问

    func deleteRecord(_ id: UUID) {
        PhotoStorageService.shared.deleteRecord(id)
    }

    func deleteRecords(_ ids: [UUID]) {
        for id in ids {
            PhotoStorageService.shared.deleteRecord(id)
        }
    }

    func thumbnail(for id: UUID) -> UIImage? {
        PhotoStorageService.shared.thumbnail(for: id)
    }

    func fullPhoto(for id: UUID) -> UIImage? {
        guard let url = PhotoStorageService.shared.photoURL(for: id),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - 从系统相册导入

    /// 批量导入：逐张读取 PhotosPickerItem → 写入图库 → 后台跑一次本地 AI 点评打分
    /// （零网络，不需要等待也不会阻塞导入流程，完成后通过 recordsPublisher 自然刷新图库角标）
    @MainActor
    func importPhotos(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isImporting = true
        importProgress = (0, items.count)
        defer {
            isImporting = false
            importProgress = nil
        }

        for (index, item) in items.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data),
               let jpegData = uiImage.jpegData(compressionQuality: 0.92) {
                let id = await withCheckedContinuation { (continuation: CheckedContinuation<UUID, Never>) in
                    PhotoStorageService.shared.savePhoto(data: jpegData, detectionMethod: "相册导入") { id in
                        continuation.resume(returning: id)
                    }
                }
                DispatchQueue.global(qos: .utility).async {
                    guard let critique = LocalPhotoCritiqueEngine.analyze(uiImage) else { return }
                    PhotoStorageService.shared.updateCritique(critique, for: id)
                }
            }
            importProgress = (index + 1, items.count)
        }
    }
}
