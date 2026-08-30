//
//  PhotoCritique.swift
//  FrameHero
//
//  拍后 AI 点评（路线图：拍后复盘）
//
//  ## 定位
//  拍前引导（本地实时）+ 拍后复盘构成完整闭环：图库中选一张照片
//  （无论是 App 内拍摄的，还是从系统相册导入的）→ 从构图/光线/主体
//  表达三个维度给出结构化点评（总分 + 分维度分 + 标签 + 亮点/改进建议）。
//
//  ## 双引擎：本地优先 + 云端增强
//  - 本地（LocalPhotoCritiqueEngine）：Vision 框架离线分析，零网络、
//    近乎瞬时，任何时候都可用，是默认展示的结果。
//  - 云端（DeepSeek Vision）：配置了 Key 时在后台并行/随后请求，
//    到达后无感升级为更懂语义的点评（参考当时拍摄的 EXIF/构图评分）。
//
//  ## 上下文注入（云端）
//  请求会附带照片的 EXIF（ISO/快门/光圈）与拍摄时刻的 AI 构图评分，
//  让点评能对"当时引导的效果"做出回应。
//

import Foundation

struct PhotoCritique: Codable, Equatable {

    enum Source: String, Codable {
        case local
        case cloud
    }

    /// 综合得分 0-100
    var score: Int?
    /// 一句话总评
    var summary: String?
    /// 亮点列表
    var strengths: [String]?
    /// 可改进点列表
    var improvements: [String]?

    /// 构图维度得分 0-100
    var compositionScore: Int?
    /// 光线维度得分 0-100
    var lightScore: Int?
    /// 主体表达维度得分 0-100
    var subjectScore: Int?
    /// 画面标签（如"逆光""三分构图""检测到人脸"）
    var tags: [String]?

    /// 产出该点评的引擎：本地 Vision 分析 or 云端 DeepSeek Vision
    var source: Source?

    enum CodingKeys: String, CodingKey {
        case score, summary, strengths, improvements, tags, source
        case compositionScore = "composition_score"
        case lightScore = "light_score"
        case subjectScore = "subject_score"
    }

    /// 点评提示词（上下文由调用方拼接在末尾）
    static func prompt(context: String) -> String {
        let contextBlock = context.isEmpty ? "" : "\n拍摄上下文（供参考）：\n\(context)\n"
        return """
        你是一位严格的手机摄影评委。分析这张照片，从构图、光线、主体表达三个角度评价。\(contextBlock)
        Return JSON only, no markdown, no extra text:
        {
          "score": 0-100 的综合整数,
          "composition_score": 0-100 的构图维度整数,
          "light_score": 0-100 的光线维度整数,
          "subject_score": 0-100 的主体表达维度整数,
          "tags": ["画面标签（中文，2-4 个，如 逆光/三分构图/背景杂乱）"],
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
