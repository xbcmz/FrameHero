//
//  CoordinateConverter.swift
//  FrameHero
//
//  坐标换算专用工具（MVP Final Plan §13）
//
//  ## 约定
//  - 图像归一化坐标：x 向右，y 向上（0,0 = 左下），Apple Vision / 构图引擎使用
//  - 视图坐标：x 向右，y 向下（0,0 = 左上），SwiftUI Overlay 使用
//  - 前置摄像头预览是镜像的：显示层的 X 需要翻转
//
//  所有"图像坐标 ↔ 视图坐标"的换算必须经由本工具，
//  禁止在 UI 文件里散落手写 1-y / width-x 之类的转换。
//

import Foundation
import CoreGraphics

#if os(iOS)

enum CoordinateConverter {

    /// 图像归一化点（y 向上）→ 构图区域视图点（y 向下）
    static func viewPoint(fromImagePoint point: CGPoint, rect: CGRect) -> CGPoint {
        CGPoint(x: point.x * rect.width,
                y: (1 - point.y) * rect.height)
    }

    /// 视图点 X 随前置预览镜像翻转
    static func mirroredX(_ x: CGFloat, rectWidth: CGFloat) -> CGFloat {
        rectWidth - x
    }

    /// 方案目标（y 从顶部计）→ 视图点
    static func viewPoint(fromPlanTarget target: CGPoint, rect: CGRect) -> CGPoint {
        CGPoint(x: target.x * rect.width,
                y: target.y * rect.height)
    }
}

#endif
