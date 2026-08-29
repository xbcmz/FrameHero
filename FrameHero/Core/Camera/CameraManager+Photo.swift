import Foundation
import AVFoundation
import CoreImage
import ImageIO

#if os(iOS)

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func capturePhoto() {
        let settings: AVCapturePhotoSettings = AVCapturePhotoSettings()
        if self.photoOutput.supportedFlashModes.contains(.auto) {
            settings.flashMode = .auto
        }
        settings.isHighResolutionPhotoEnabled = true
        if photoOutput.isStillImageStabilizationSupported {
            settings.isAutoStillImageStabilizationEnabled = true
        }
        if #available(iOS 16.0, tvOS 16.0, *) {
            settings.photoQualityPrioritization = self.photoOutput.maxPhotoQualityPrioritization
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error: any Error = error {
            print("Photo processing error: \(error)")
            DispatchQueue.main.async { self.lastPhotoSaved = false }
            return
        }
        guard let data: Data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { self.lastPhotoSaved = false }
            return
        }
        // 取景器/构图网格都是 3:4，直接保存原始 4:3 会导致"所拍非所得"。
        // 裁剪到 3:4（失败时回退原始数据），并保留原图 EXIF 参数
        let finalData = processPhotoData(photo: photo, originalData: data) ?? data
        onPhotoDataReady?(finalData)
        DispatchQueue.main.async { self.lastPhotoSaved = true }
    }

    /// 将照片裁剪为与取景器一致的 3:4，并把原始 EXIF/TIFF 元数据合并进新 JPEG。
    func processPhotoData(photo: AVCapturePhoto, originalData: Data) -> Data? {
        guard let pixelBuffer = photo.pixelBuffer,
              let croppedBuffer = cropPixelBufferToThreeByFour(pixelBuffer,
                                                               orientation: photoOrientation(from: photo)),
              let jpegData = jpegData(from: croppedBuffer) else {
            return nil
        }
        return Self.mergingEXIF(from: originalData, into: jpegData)
    }

    /// 把原始照片的 EXIF/TIFF 元数据（ISO、快门、光圈、机型等）合并进裁剪后的 JPEG。
    /// 裁剪后图像已是直立方向，需剔除原图的 orientation/像素尺寸字段避免二次旋转。
    private static func mergingEXIF(from originalData: Data, into croppedJPEG: Data) -> Data? {
        guard let croppedSource = CGImageSourceCreateWithData(croppedJPEG as CFData, nil),
              let originalSource = CGImageSourceCreateWithData(originalData as CFData, nil),
              let originalProps = CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil)
                  as? [String: Any] else {
            return nil
        }

        var props = originalProps
        props[kCGImagePropertyOrientation as String] = nil
        props[kCGImagePropertyPixelWidth as String] = nil
        props[kCGImagePropertyPixelHeight as String] = nil

        let outData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(outData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImageFromSource(destination, croppedSource, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return outData as Data
    }

    func cropPixelBufferToThreeByFour(_ pixelBuffer: CVPixelBuffer,
                                      orientation: CGImagePropertyOrientation) -> CVPixelBuffer? {
        let oriented = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        let extent = oriented.extent
        let desiredAspect: CGFloat = 3.0 / 4.0
        var cropRect = extent
        let currentAspect = extent.width / extent.height

        if currentAspect > desiredAspect {
            let newWidth = extent.height * desiredAspect
            cropRect.origin.x = extent.midX - newWidth * 0.5
            cropRect.size.width = newWidth
        } else if currentAspect < desiredAspect {
            let newHeight = extent.width / desiredAspect
            cropRect.origin.y = extent.midY - newHeight * 0.5
            cropRect.size.height = newHeight
        }

        let cropped = oriented.cropped(to: cropRect)

        var output: CVPixelBuffer?
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(cropRect.width),
                                         Int(cropRect.height),
                                         pixelFormat,
                                         attributes as CFDictionary,
                                         &output)
        guard status == kCVReturnSuccess, let buffer = output else { return nil }

        photoContext.render(cropped, to: buffer)
        return buffer
    }

    func jpegData(from pixelBuffer: CVPixelBuffer) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return photoContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [:])
    }

    func photoOrientation(from photo: AVCapturePhoto) -> CGImagePropertyOrientation {
        if let value = photo.metadata[kCGImagePropertyOrientation as String] as? UInt32,
           let orientation = CGImagePropertyOrientation(rawValue: value) {
            return orientation
        }
        return .right
    }
}

#endif
