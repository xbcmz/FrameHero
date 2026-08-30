import Foundation
import Combine
import UIKit
import ImageIO

final class PhotoStorageService {
    static let shared = PhotoStorageService()

    private let storageQueue = DispatchQueue(label: "framehero.storage", qos: .utility)
    // records / isLoaded 只允许在 storageQueue 上访问。
    // 之前主线程（loadRecords）与队列（savePhoto/deleteRecord）并发读写同一个
    // 非原子 Array，是会随机崩溃的数据竞争。
    private var records: [PhotoRecord] = []
    private var isLoaded = false

    let recordsPublisher = CurrentValueSubject<[PhotoRecord], Never>([])

    private var baseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FrameHero", isDirectory: true)
    }

    private var recordsURL: URL {
        baseURL.appendingPathComponent("records.json")
    }

    private var photosDir: URL {
        baseURL.appendingPathComponent("photos", isDirectory: true)
    }

    private var thumbnailsDir: URL {
        baseURL.appendingPathComponent("thumbnails", isDirectory: true)
    }

    private init() {}

    // MARK: - Public API

    /// 触发磁盘记录加载（异步）。
    /// 结果经 recordsPublisher 发布到主线程，HomeViewModel 订阅该流刷新列表；
    /// 重复调用安全，只在首次真正读盘。
    func loadRecordsIfNeeded() {
        storageQueue.async { [weak self] in
            guard let self, !self.isLoaded else { return }
            self.isLoaded = true
            self.ensureDirectories()
            if let data = try? Data(contentsOf: self.recordsURL),
               let decoded = try? JSONDecoder().decode([PhotoRecord].self, from: data) {
                self.records = decoded
            }
            let snapshot = self.records
            DispatchQueue.main.async {
                self.recordsPublisher.send(snapshot)
            }
        }
    }

    func savePhoto(data: Data, detectionMethod: String? = nil, compositionScore: Int? = nil,
                    burstID: UUID? = nil, completion: ((UUID) -> Void)? = nil) {
        let id = UUID()
        let photoURL = photosDir.appendingPathComponent(PhotoRecord.photoFilename(for: id))
        let thumbURL = thumbnailsDir.appendingPathComponent(PhotoRecord.thumbnailFilename(for: id))

        // 提取 EXIF 元数据
        var exif: (iso: Float?, shutter: Double?, aperture: Double?, width: Int?, height: Int?) = (nil, nil, nil, nil, nil)
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            if let exifDict = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                if let isoValues = exifDict[kCGImagePropertyExifISOSpeedRatings as String] as? [Float] {
                    exif.iso = isoValues.first
                }
                exif.shutter = exifDict[kCGImagePropertyExifExposureTime as String] as? Double
                exif.aperture = exifDict[kCGImagePropertyExifFNumber as String] as? Double
            }
            exif.width = props[kCGImagePropertyPixelWidth as String] as? Int
            exif.height = props[kCGImagePropertyPixelHeight as String] as? Int
        }

        storageQueue.async { [weak self] in
            guard let self else { return }
            self.ensureDirectories()

            do {
                try data.write(to: photoURL, options: .atomic)
            } catch {
                print("PhotoStorageService: failed to write photo \(error)")
                return
            }

            if let thumbData = ThumbnailGenerator.generate(from: data) {
                try? thumbData.write(to: thumbURL, options: .atomic)
            }

            let record = PhotoRecord(id: id, creationDate: Date(),
                                     detectionMethod: detectionMethod,
                                     iso: exif.iso, shutterSpeed: exif.shutter, aperture: exif.aperture,
                                     imageWidth: exif.width, imageHeight: exif.height,
                                     compositionScore: compositionScore,
                                     burstID: burstID)
            self.records.insert(record, at: 0)
            self.persist()
            if let completion {
                DispatchQueue.main.async { completion(id) }
            }
        }
    }

    /// 写入图库「AI 点评」结果缓存。若该记录还没拍摄时评分（例如从相册导入的照片），
    /// 用点评的综合分回填，让图库角标/首页统计也能用上。
    func updateCritique(_ critique: PhotoCritique, for id: UUID) {
        storageQueue.async { [weak self] in
            guard let self else { return }
            guard let index = self.records.firstIndex(where: { $0.id == id }) else { return }
            self.records[index].critique = critique
            if self.records[index].compositionScore == nil {
                self.records[index].compositionScore = critique.score
            }
            self.persist()
        }
    }

    /// 记录本地清晰度预审结果（Laplacian 方差判糊），供图库角标和连拍优选使用
    func updateBlurResult(_ isBlurry: Bool, for id: UUID) {
        storageQueue.async { [weak self] in
            guard let self else { return }
            guard let index = self.records.firstIndex(where: { $0.id == id }) else { return }
            self.records[index].isBlurry = isBlurry
            self.persist()
        }
    }

    /// 连拍结束后，从同一 burstID 分组里选出清晰度 + 构图/点评分数综合最优的一张打标。
    /// 模糊的照片会被重量惩罚，没分数时默认均等权。
    func markBurstBest(_ burstID: UUID) {
        storageQueue.async { [weak self] in
            guard let self else { return }
            let indices = self.records.indices.filter { self.records[$0].burstID == burstID }
            guard indices.count > 1 else { return }

            func rank(_ record: PhotoRecord) -> Int {
                let base = record.critique?.score ?? record.compositionScore ?? 50
                return record.isBlurry == true ? base - 1000 : base
            }

            guard let bestIndex = indices.max(by: { rank(self.records[$0]) < rank(self.records[$1]) }) else { return }
            for index in indices {
                self.records[index].isBurstBest = (index == bestIndex)
            }
            self.persist()
        }
    }

    func deleteRecord(_ id: UUID) {
        storageQueue.async { [weak self] in
            guard let self else { return }
            self.records.removeAll { $0.id == id }
            let photoURL = self.photosDir.appendingPathComponent(PhotoRecord.photoFilename(for: id))
            let thumbURL = self.thumbnailsDir.appendingPathComponent(PhotoRecord.thumbnailFilename(for: id))
            try? FileManager.default.removeItem(at: photoURL)
            try? FileManager.default.removeItem(at: thumbURL)
            self.persist()
        }
    }

    func thumbnail(for id: UUID) -> UIImage? {
        let thumbURL = thumbnailsDir.appendingPathComponent(PhotoRecord.thumbnailFilename(for: id))
        return UIImage(contentsOfFile: thumbURL.path)
    }

    func photoURL(for id: UUID) -> URL? {
        let url = photosDir.appendingPathComponent(PhotoRecord.photoFilename(for: id))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 读取原始照片字节（原图直出导出用，不经重编码）
    func photoData(for id: UUID) -> Data? {
        guard let url = photoURL(for: id) else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: - Private

    private func ensureDirectories() {
        let dirs = [baseURL, photosDir, thumbnailsDir]
        for dir in dirs {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// 写盘并把最新快照发布到主线程。只能在 storageQueue 上调用
    /// （records 的读写都必须 confinement 在该队列）。
    private func persist() {
        let snapshot = records
        let url = recordsURL
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            print("PhotoStorageService: persist failed \(error)")
        }
        DispatchQueue.main.async {
            self.recordsPublisher.send(snapshot)
        }
    }
}
