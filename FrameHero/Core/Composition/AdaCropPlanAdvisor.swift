//
//  AdaCropPlanAdvisor.swift
//  FrameHero
//
//  AdaCrop 构图模型"参谋"：方案生成时一次性预测当前画面的最佳构图裁切区，
//  用模型的建议校准构图方案的目标位置（Fast=Student / Pro=Teacher 两档）。
//
//  ## 定位（区别于旧魔法棒）
//  - 只在「AI 构图」会话的分析阶段调用一次，不参与实时逐帧跟踪
//  - 输出"最佳裁切区"（归一化矩形），由上层把主体位置映射进该区域，
//    得到"如果按模型的意思裁，主体应该放在哪"——方案目标位置的校准依据
//  - 模型不可用/推理失败时回调 nil，上层回退纯规则方案（优雅降级）
//
//  ## 模型
//  - Fast：AdacropStudentBBox（轻量）
//  - Pro：AdacropTeacherBBox（全量精度）
//  预处理与坐标映射沿用原 CoreMLCropDetector 的实现（含方形裁剪与
//  Accelerate 加速的 CHW 转换），保证与模型训练分布一致。
//

import Foundation
import CoreML
import AVFoundation
import CoreGraphics
import CoreImage
import Accelerate

#if os(iOS)

final class AdaCropPlanAdvisor {

    private let queue = DispatchQueue(label: "framehero.adacrop.plan", qos: .userInitiated)
    private let bboxModel: MLModel?
    private let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    init(mode: DetectionMode) {
        let config = MLModelConfiguration()
        switch mode {
        case .fast:
            bboxModel = try? AdacropStudentBBox(configuration: config).model
        case .pro:
            bboxModel = try? AdacropTeacherBBox(configuration: config).model
        case .vision:
            bboxModel = nil
        }
    }

    var isAvailable: Bool { bboxModel != nil }

    /// 预测最佳构图裁切区（归一化 CGRect，y 向上）。
    /// 模型不可用/推理失败时回调 nil（上层回退到纯规则方案）。
    func predictBestCrop(_ pixelBuffer: CVPixelBuffer,
                         orientation: CGImagePropertyOrientation,
                         completion: @escaping (CGRect?) -> Void) {
        guard let bboxModel else {
            completion(nil)
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            let oriented = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)

            guard let input = self.makeSquareModelInput(from: oriented) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            do {
                let feature = try MLDictionaryFeatureProvider(dictionary: ["full_img": input.array])
                let output = try bboxModel.prediction(from: feature)
                guard let bboxArray = output.featureValue(for: "bbox")?.multiArrayValue else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                // bbox 相对方形裁剪区（y 向上）→ 映射回全图归一化坐标
                let squareBBox = (0..<4).map { Float(truncating: bboxArray[$0]) }
                let full = Self.mapToFullImage(squareBBox,
                                               squareCrop: input.squareCrop,
                                               fullExtent: oriented.extent)

                var rect = CGRect(x: CGFloat(full[0]) - CGFloat(full[2]) / 2,
                                  y: CGFloat(full[1]) - CGFloat(full[3]) / 2,
                                  width: CGFloat(full[2]),
                                  height: CGFloat(full[3]))
                // 消毒：越界/退化区域视为无效建议
                rect = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                guard !rect.isNull, rect.width > 0.2, rect.height > 0.2 else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                DispatchQueue.main.async { completion(rect) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: - 预处理（沿用自原 CoreMLCropDetector）

    private struct SquareModelInput {
        let array: MLMultiArray
        let squareCrop: CGRect
    }

    /// 居中裁方形 → 等比缩放 224×224（与模型训练分布一致）
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
        ciContext.render(image.cropped(to: squareCrop), to: outBuffer)

        guard let array = bgraBufferToCHWFloat16(outBuffer) else { return nil }
        return SquareModelInput(array: array, squareCrop: squareCrop)
    }

    /// BGRA → [1,3,224,224] CHW float16，全程 Accelerate
    private func bgraBufferToCHWFloat16(_ buffer: CVPixelBuffer) -> MLMultiArray? {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let count = width * height

        guard let array = try? MLMultiArray(shape: [1, 3, NSNumber(value: width), NSNumber(value: height)],
                                            dataType: .float16) else { return nil }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }

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
        // BGRA 内存序拆分：planes[0]=B, planes[1]=G, planes[2]=R, planes[3]=A
        let convertError = vImageConvert_ARGB8888toPlanar8(&src, &planes[0], &planes[1], &planes[2], &planes[3],
                                                           vImage_Flags(kvImageNoFlags))
        guard convertError == kvImageNoError else { return nil }

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

    /// 方形空间归一化 bbox [cx, cy, w, h] → 全图归一化坐标
    private static func mapToFullImage(_ bbox: [Float], squareCrop: CGRect, fullExtent: CGRect) -> [Float] {
        [
            Float((squareCrop.minX + CGFloat(bbox[0]) * squareCrop.width - fullExtent.minX) / fullExtent.width),
            Float((squareCrop.minY + CGFloat(bbox[1]) * squareCrop.height - fullExtent.minY) / fullExtent.height),
            Float(CGFloat(bbox[2]) * squareCrop.width / fullExtent.width),
            Float(CGFloat(bbox[3]) * squareCrop.height / fullExtent.height)
        ]
    }
}

#endif
