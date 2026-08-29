import Foundation
import CoreML
import AVFoundation
import CoreGraphics
import CoreImage
import Accelerate

#if os(iOS)

final class CoreMLCropDetector {
    private let mode: DetectionMode
    private let queue = DispatchQueue(label: "livecapture.coreml.queue", qos: .userInitiated)
    private let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    // 模型只在 init 时加载一次。原实现每次检测都重新实例化 MLModel，
    // 造成数百毫秒级延迟和内存抖动。
    private let bboxModel: MLModel?
    private let actorModel: MLModel?

    private enum ModelLoadError: Error {
        case modelNotFound
        case compilationFailed
    }

    init(mode: DetectionMode) {
        self.mode = mode
        self.bboxModel = try? Self.loadBBoxModel(mode: mode)
        self.actorModel = try? Self.loadActorModel(mode: mode)
    }

    // MARK: - Model Loading

    private static func loadBBoxModel(mode: DetectionMode) throws -> MLModel {
        let config = MLModelConfiguration()
        switch mode {
        case .fast:
            return try AdacropStudentBBox(configuration: config).model
        case .pro:
            return try AdacropTeacherBBox(configuration: config).model
        case .vision:
            throw ModelLoadError.modelNotFound
        }
    }

    private static func loadActorModel(mode: DetectionMode) throws -> MLModel {
        let config = MLModelConfiguration()
        switch mode {
        case .fast:
            return try AdacropStudentActor(configuration: config).model
        case .pro:
            return try AdacropTeacherActor(configuration: config).model
        case .vision:
            throw ModelLoadError.modelNotFound
        }
    }

    // MARK: - Image Preprocessing

    /// 224×224 模型输入，以及该输入对应的方形裁剪区
    /// （bbox 预测在方形空间，映射回全图坐标时需要它）
    private struct SquareModelInput {
        let array: MLMultiArray
        let squareCrop: CGRect  // oriented 图像像素坐标中的方形区域
    }

    /// 构建方形模型输入：居中裁方形 → 等比缩放到 224×224。
    /// 之前把 3:4 画面非等比拉伸成正方形，人物比例失真、偏离模型训练分布。
    private func makeSquareModelInput(from image: CIImage) -> SquareModelInput? {
        let extent = image.extent
        let side = min(extent.width, extent.height)
        guard side >= 1 else { return nil }
        let squareCrop = CGRect(x: extent.midX - side / 2,
                                y: extent.midY - side / 2,
                                width: side,
                                height: side)

        var outBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 224, 224,
                                         kCVPixelFormatType_32BGRA, nil, &outBuffer)
        guard status == kCVReturnSuccess, let outBuffer else { return nil }

        // 方形裁剪 → 方形缓冲，CIContext 等比缩放
        ciContext.render(image.cropped(to: squareCrop), to: outBuffer)

        guard let array = bgraBufferToCHWFloat16(outBuffer) else { return nil }
        return SquareModelInput(array: array, squareCrop: squareCrop)
    }

    /// BGRA 像素缓冲 → [1,3,224,224] CHW float16，通道拆分/归一化/半精度转换全程 Accelerate。
    /// （之前是逐像素 Swift 循环，224×224×3 要做 15 万次浮点转换）
    private func bgraBufferToCHWFloat16(_ buffer: CVPixelBuffer) -> MLMultiArray? {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let count = width * height

        guard let array = try? MLMultiArray(shape: [1, 3, NSNumber(value: width), NSNumber(value: height)],
                                            dataType: .float16) else { return nil }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        // BGRA 内存序拆成 4 个 Planar8 通道：plane0=B, plane1=G, plane2=R, plane3=A（丢弃）
        var planes: [vImage_Buffer] = (0..<4).map { _ in vImage_Buffer() }
        let u8Blocks: [UnsafeMutableRawPointer] = (0..<4).map { _ in
            UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 64)
        }
        defer { u8Blocks.forEach { $0.deallocate() } }
        for (idx, block) in u8Blocks.enumerated() {
            planes[idx] = vImage_Buffer(data: block,
                                        height: vImagePixelCount(height),
                                        width: vImagePixelCount(width),
                                        rowBytes: width)
        }

        var src = vImage_Buffer(data: baseAddress,
                                height: vImagePixelCount(height),
                                width: vImagePixelCount(width),
                                rowBytes: CVPixelBufferGetBytesPerRow(buffer))
        // ARGB8888toPlanar8 按内存字节序拆分：destA←byte0、destR←byte1、destG←byte2、destB←byte3。
        // BGRA 缓冲（byte0=B, byte1=G, byte2=R, byte3=A）代入后：
        // planes[0]=B、planes[1]=G、planes[2]=R、planes[3]=A（丢弃）
        let convertError = vImageConvert_ARGB8888toPlanar8(&src, &planes[0], &planes[1], &planes[2], &planes[3],
                                                           vImage_Flags(kvImageNoFlags))
        guard convertError == kvImageNoError else { return nil }

        // 模型通道序为 RGB：plane0=R(planes[2])、plane1=G(planes[1])、plane2=B(planes[0])
        let rgbSources = [planes[2], planes[1], planes[0]]
        var normScale: Float = 1.0 / 255.0
        let stride = count
        let f16Base = array.dataPointer.assumingMemoryBound(to: Float16.self)

        let f32Block = UnsafeMutableRawPointer.allocate(byteCount: count * 4, alignment: 64)
        defer { f32Block.deallocate() }

        for (modelPlane, srcPlane) in rgbSources.enumerated() {
            let f32Ptr = f32Block.assumingMemoryBound(to: Float.self)
            vDSP_vfltu8(srcPlane.data.assumingMemoryBound(to: UInt8.self), 1,
                        f32Ptr, 1, vDSP_Length(count))
            vDSP_vsmul(f32Ptr, 1, &normScale, f32Ptr, 1, vDSP_Length(count))

            var f32Buffer = vImage_Buffer(data: f32Block,
                                          height: vImagePixelCount(height),
                                          width: vImagePixelCount(width),
                                          rowBytes: width * 4)
            var f16Buffer = vImage_Buffer(data: f16Base + modelPlane * stride,
                                          height: vImagePixelCount(height),
                                          width: vImagePixelCount(width),
                                          rowBytes: width * 2)
            let halfError = vImageConvert_PlanarFtoPlanar16F(&f32Buffer, &f16Buffer,
                                                             vImage_Flags(kvImageNoFlags))
            guard halfError == kvImageNoError else { return nil }
        }

        return array
    }

    /// 从 oriented 图像中按归一化 bbox（相对全图）裁出 224×224 的 actor 模型输入
    private func cropPixelBuffer(from image: CIImage, bbox: [Float]) -> CVPixelBuffer? {
        let imageWidth = image.extent.width
        let imageHeight = image.extent.height

        // bbox 为归一化的 [cx, cy, w, h]
        let cx = CGFloat(bbox[0]) * imageWidth
        let cy = CGFloat(bbox[1]) * imageHeight
        let bw = CGFloat(bbox[2]) * imageWidth
        let bh = CGFloat(bbox[3]) * imageHeight

        let cropRect = CGRect(x: cx - bw / 2, y: cy - bh / 2, width: bw, height: bh)
            .intersection(image.extent)

        guard cropRect.width > 0, cropRect.height > 0 else { return nil }

        let cropped = image.cropped(to: cropRect)

        var outBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 224, 224, kCVPixelFormatType_32BGRA, nil, &outBuffer)
        guard let outBuffer else { return nil }

        // Scale cropped region to 224x224
        let targetRect = CGRect(x: 0, y: 0, width: 224, height: 224)
        let scaleX = targetRect.width / cropRect.width
        let scaleY = targetRect.height / cropRect.height
        let scale = min(scaleX, scaleY)
        let scaledWidth = cropRect.width * scale
        let scaledHeight = cropRect.height * scale
        let centeredRect = CGRect(x: (224 - scaledWidth) / 2, y: (224 - scaledHeight) / 2,
                                  width: scaledWidth, height: scaledHeight)
        let transformed = cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: centeredRect.origin.x, y: centeredRect.origin.y))

        ciContext.render(transformed, to: outBuffer)
        return outBuffer
    }

    // MARK: - Detection

    func detectBestCrop(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        targetAspectRatio: CGFloat,
        completion: @escaping (AestheticCrop?) -> Void
    ) {
        queue.async { [weak self] in
            guard let self, let bboxModel = self.bboxModel, let actorModel = self.actorModel else {
                // 模型不可用时明确失败，让上层走重试逻辑。
                // 绝不伪造"检测成功"的结果——否则自动拍摄会对着假目标倒计时拍照
                completion(nil)
                return
            }

            // orientation 真正参与预处理（.up 是常见路径，连接层已旋转时为零开销）
            let orientedImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)

            // Step 1: 预处理图像并运行 BBox 模型
            guard let input = self.makeSquareModelInput(from: orientedImage) else {
                completion(nil)
                return
            }

            do {
                let bboxInput = try MLDictionaryFeatureProvider(dictionary: ["full_img": input.array])
                let bboxOutput = try bboxModel.prediction(from: bboxInput)

                guard let bboxArray = bboxOutput.featureValue(for: "bbox")?.multiArrayValue else {
                    completion(nil)
                    return
                }

                let squareBBox = (0..<4).map { Float(truncating: bboxArray[$0]) }

                // bbox 是相对方形裁剪区的归一化坐标，映射回全图归一化空间，
                // 后续裁剪/坐标换算才能与全图对齐
                let bbox = Self.mapToFullImage(squareBBox,
                                               squareCrop: input.squareCrop,
                                               fullExtent: orientedImage.extent)

                // Step 2: 裁切并运行 Actor 模型
                guard let cropBuffer = self.cropPixelBuffer(from: orientedImage, bbox: bbox) else {
                    completion(nil)
                    return
                }
                guard let cropInput = self.makeSquareModelInput(from: CIImage(cvPixelBuffer: cropBuffer)) else {
                    completion(nil)
                    return
                }

                guard let stateArray = try? MLMultiArray(shape: [1, 4], dataType: .float16) else {
                    completion(nil)
                    return
                }
                // state 输入必须用 bbox 模型自己的坐标空间（方形裁剪空间）
                for i in 0..<4 { stateArray[i] = NSNumber(value: squareBBox[i]) }

                let actorInput = try MLDictionaryFeatureProvider(dictionary: [
                    "crop_img": cropInput.array,
                    "state_workaround": stateArray
                ])
                let actorOutput = try actorModel.prediction(from: actorInput)

                guard let actionArray = actorOutput.featureValue(for: "action_probs")?.multiArrayValue else {
                    completion(nil)
                    return
                }

                let actionProbs = (0..<7).map { Float(truncating: actionArray[$0]) }

                // Step 3: 选择最佳动作并映射到裁切调整
                guard let maxIndex = actionProbs.indices.max(by: { actionProbs[$0] < actionProbs[$1] }) else {
                    completion(nil)
                    return
                }

                // 动作微调在模型原生（方形）空间进行，再映射回全图
                let refinedSquareBBox = self.applyAction(maxIndex, to: squareBBox)
                let refinedBBox = Self.mapToFullImage(refinedSquareBBox,
                                                      squareCrop: input.squareCrop,
                                                      fullExtent: orientedImage.extent)
                let rect = self.bboxToCGRect(refinedBBox)

                // 调整到目标宽高比
                let finalRect = self.fitToAspectRatio(rect, target: targetAspectRatio)

                let detectionType = "Adacrop \(self.mode == .fast ? "Fast" : "Pro")"
                completion(AestheticCrop(rect: finalRect, confidence: actionProbs[maxIndex], detectionType: detectionType))
            } catch {
                completion(nil)
            }
        }
    }

    // MARK: - Action Mapping

    /// 把方形裁剪空间中的归一化 [cx, cy, w, h] bbox 映射回全图归一化空间
    private static func mapToFullImage(_ bbox: [Float], squareCrop: CGRect, fullExtent: CGRect) -> [Float] {
        [
            Float((squareCrop.minX + CGFloat(bbox[0]) * squareCrop.width - fullExtent.minX) / fullExtent.width),
            Float((squareCrop.minY + CGFloat(bbox[1]) * squareCrop.height - fullExtent.minY) / fullExtent.height),
            Float(CGFloat(bbox[2]) * squareCrop.width / fullExtent.width),
            Float(CGFloat(bbox[3]) * squareCrop.height / fullExtent.height)
        ]
    }

    /// 将 7 个动作映射到 bbox 调整。
    /// 0: no-op, 1: left, 2: right, 3: up, 4: down, 5: zoom out, 6: zoom in
    private func applyAction(_ action: Int, to bbox: [Float]) -> [Float] {
        let step: Float = 0.05
        let zoomStep: Float = 0.08
        var result = bbox

        switch action {
        case 1: result[0] = max(0, bbox[0] - step)          // left
        case 2: result[0] = min(1, bbox[0] + step)          // right
        case 3: result[1] = max(0, bbox[1] - step)          // up
        case 4: result[1] = min(1, bbox[1] + step)          // down
        case 5:                                              // zoom out
            result[2] = min(1, bbox[2] + zoomStep)
            result[3] = min(1, bbox[3] + zoomStep)
        case 6:                                              // zoom in
            result[2] = max(0.1, bbox[2] - zoomStep)
            result[3] = max(0.1, bbox[3] - zoomStep)
        default: break                                       // no-op
        }

        return result
    }

    /// 将归一化 [cx, cy, w, h] bbox 转换为归一化 CGRect
    private func bboxToCGRect(_ bbox: [Float]) -> CGRect {
        let cx = CGFloat(bbox[0])
        let cy = CGFloat(bbox[1])
        let w = CGFloat(bbox[2])
        let h = CGFloat(bbox[3])
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// 将矩形调整为目标宽高比
    private func fitToAspectRatio(_ rect: CGRect, target: CGFloat) -> CGRect {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var width = rect.width
        var height = rect.height

        let currentRatio = width / height
        if currentRatio > target {
            height = width / target
        } else {
            width = height * target
        }

        var result = CGRect(x: center.x - width / 2, y: center.y - height / 2,
                            width: width, height: height)
        result.origin.x = max(0, min(result.origin.x, 1 - result.width))
        result.origin.y = max(0, min(result.origin.y, 1 - result.height))

        if result.width > 1 || result.height > 1 {
            let scale = min(1.0 / result.width, 1.0 / result.height)
            result.size.width *= scale
            result.size.height *= scale
            result.origin.x = center.x - result.width / 2
            result.origin.y = center.y - result.height / 2
        }

        return result
    }
}

// MARK: - CropDetectionStrategy

extension CoreMLCropDetector: CropDetectionStrategy {}

#endif
