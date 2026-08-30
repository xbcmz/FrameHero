//
//  AestheticCropDetector.swift
//  FrameHero
//
//  基于 Vision 框架的原始检测数据源
//
//  ## 文件作用
//  使用 Apple Vision 框架检测人脸、人体，供构图评分/AI 建议使用
//  （旧版本还包含一套基于候选框打分的"最佳裁切"逻辑，用于替代
//  AdaCrop 模型前的"magic wand"体验；随 AdaCropPlanAdvisor 上线后，
//  上层已全部改为 detectPeople + AdaCrop 模型的组合，该逻辑无调用方，
//  已随之移除，避免与当前架构混淆）
//
//  ## 主要方法
//  - detectPeople(in:orientation:completion:): 检测人脸/人体原始数据（10Hz 高频路径，
//    不含显著性检测——显著性是三个 Vision 请求里最贵的一个）
//
//  ## 线程安全
//  - 使用专用的 queue 执行所有检测操作
//  - 通过 completion 异步返回结果（主线程）
//  - 不阻塞主线程
//

import Foundation
import Vision
import AVFoundation
import CoreGraphics

#if os(iOS)

/// 基于 Vision 的检测器：提供人脸/人体原始检测数据
final class AestheticCropDetector {
	private let queue = DispatchQueue(label: "framehero.aesthetic.queue")

	/// 检测画面中的人物、人脸等原始数据（用于构图分析）
	///
	/// - Parameters:
	///   - pixelBuffer: 输入图像
	///   - orientation: 图像方向
	///   - completion: 完成回调，返回 RawDetections（主线程）
	func detectPeople(
		in pixelBuffer: CVPixelBuffer,
		orientation: CGImagePropertyOrientation,
		completion: @escaping (RawDetections) -> Void
	) {
		queue.async {
			// 执行 Vision 检测（detectPeople 不使用显著性结果，
			// 而显著性检测是三个请求里最贵的，10Hz 高频路径必须跳过）
			let detections = self.performVisionDetection(
				pixelBuffer: pixelBuffer,
				orientation: orientation,
				includeSaliency: false
			)

			// 转换为 RawDetections 格式
			var result = RawDetections()

			// 人脸
			result.faces = detections.faces.map { face in
				let box = face.boundingBox
				return DetectedObject(
					centerX: box.midX,
					centerY: box.midY,
					width: box.width,
					height: box.height,
					confidence: face.confidence
				)
			}

			// 人体
			result.bodies = detections.bodies.map { body in
				let box = body.boundingBox
				return DetectedObject(
					centerX: box.midX,
					centerY: box.midY,
					width: box.width,
					height: box.height,
					confidence: body.confidence
				)
			}

			// 显著性区域（V1 暂不处理，后续版本再加）
			// if let saliency = detections.saliency { ... }

			DispatchQueue.main.async {
				completion(result)
			}
		}
	}

	// MARK: - Vision 检测

	private struct VisionDetections {
		let faces: [VNFaceObservation]
		let bodies: [VNHumanObservation]
		let saliency: VNSaliencyImageObservation?
	}

	private func performVisionDetection(
		pixelBuffer: CVPixelBuffer,
		orientation: CGImagePropertyOrientation,
		includeSaliency: Bool
	) -> VisionDetections {
		let faceRequest = VNDetectFaceRectanglesRequest()
		let bodyRequest = VNDetectHumanRectanglesRequest()

		let handler = VNImageRequestHandler(
			cvPixelBuffer: pixelBuffer,
			orientation: orientation,
			options: [:]
		)

		if includeSaliency {
			let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
			try? handler.perform([faceRequest, bodyRequest, saliencyRequest])
			let saliency = saliencyRequest.results?.first
			return VisionDetections(faces: faceRequest.results ?? [],
									bodies: bodyRequest.results ?? [],
									saliency: saliency)
		}

		try? handler.perform([faceRequest, bodyRequest])
		return VisionDetections(faces: faceRequest.results ?? [],
								bodies: bodyRequest.results ?? [],
								saliency: nil)
	}
}

#endif
