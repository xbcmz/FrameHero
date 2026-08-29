import Foundation

struct PhotoRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let creationDate: Date
    var localIdentifier: String?

    // 检测方法
    var detectionMethod: String?

    // EXIF 元数据
    var iso: Float?
    var shutterSpeed: Double?
    var aperture: Double?
    var imageWidth: Int?
    var imageHeight: Int?

    /// 拍下这张照片那一刻的 AI 构图评分（0-100）。
    /// 旧记录没有该字段——可选属性经合成解码 decodeIfPresent，老 records.json 直接兼容。
    var compositionScore: Int?

    init(id: UUID = UUID(),
         creationDate: Date = Date(),
         localIdentifier: String? = nil,
         detectionMethod: String? = nil,
         iso: Float? = nil,
         shutterSpeed: Double? = nil,
         aperture: Double? = nil,
         imageWidth: Int? = nil,
         imageHeight: Int? = nil,
         compositionScore: Int? = nil) {
        self.id = id
        self.creationDate = creationDate
        self.localIdentifier = localIdentifier
        self.detectionMethod = detectionMethod
        self.iso = iso
        self.shutterSpeed = shutterSpeed
        self.aperture = aperture
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.compositionScore = compositionScore
    }
}

extension PhotoRecord {
    static func photoFilename(for id: UUID) -> String { "\(id.uuidString).jpg" }
    static func thumbnailFilename(for id: UUID) -> String { "\(id.uuidString)_thumb.jpg" }
}
