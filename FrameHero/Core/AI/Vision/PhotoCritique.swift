//
//  PhotoCritique.swift
//  FrameHero
//
//  拍后 AI 点评（路线图：拍后复盘）
//
//  ## 定位
//  拍前引导（本地实时）+ 拍后复盘（DeepSeek Vision 云端）构成完整闭环：
//  图库中选一张照片 → 视觉模型从构图/光线/主体表达三个角度给出
//  结构化点评（得分/总评/亮点/改进建议）。
//
//  ## 上下文注入
//  请求会附带照片的 EXIF（ISO/快门/光圈）与拍摄时刻的 AI 构图评分，
//  让点评能对"当时引导的效果"做出回应。
//

import Foundation

struct PhotoCritique: Codable, Equatable {

    /// 综合得分 0-100（模型输出）
    var score: Int?
    /// 一句话总评
    var summary: String?
    /// 亮点列表
    var strengths: [String]?
    /// 可改进点列表
    var improvements: [String]?

    /// 点评提示词（上下文由调用方拼接在末尾）
    static func prompt(context: String) -> String {
        let contextBlock = context.isEmpty ? "" : "\n拍摄上下文（供参考）：\n\(context)\n"
        return """
        你是一位严格的手机摄影评委。分析这张照片，从构图、光线、主体表达三个角度评价。\(contextBlock)
        Return JSON only, no markdown, no extra text:
        {
          "score": 0-100 的整数,
          "summary": "一句话总评（中文）",
          "strengths": ["亮点1（中文）", "亮点2（中文）"],
          "improvements": ["可改进点1（中文）", "可改进点2（中文）"]
        }
        """
    }

    /// 稳健解析：容忍围栏与前后杂文本
    static func parse(from text: String) -> PhotoCritique? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PhotoCritique.self, from: data)
    }
}
