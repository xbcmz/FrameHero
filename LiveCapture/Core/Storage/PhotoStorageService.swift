import Foundation
import Combine
import UIKit
import ImageIO

final class PhotoStorageService {
    static let shared = PhotoStorageService()

    private let storageQueue = DispatchQueue(label: "livecapture.storage", qos: .utility)
    // records / isLoaded 只允许在 storageQueue 上访问。
    // 之前主线程（loadRecords）与队列（savePhoto/deleteRecord）并发读写同一个
    // 非原子 Array，是会随机崩溃的数据竞争。
    private var records: [PhotoRecord] = []
    private var isLoaded = false

    let recordsPublisher = CurrentValueSubject<[PhotoRecord], Never>([])

    private var baseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("LiveCapture", isDirectory: true)
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

    func savePhoto(data: Data, detectionMethod: String? = nil) {
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
                                     imageWidth: exif.width, imageHeight: exif.height)
            self.records.insert(record, at: 0)
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
