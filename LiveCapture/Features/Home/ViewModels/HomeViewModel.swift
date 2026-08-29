import Foundation
import Combine
import UIKit

final class HomeViewModel: ObservableObject {
    @Published private(set) var records: [PhotoRecord] = []
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
}
