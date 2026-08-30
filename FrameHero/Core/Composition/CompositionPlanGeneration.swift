//
//  CompositionPlanGeneration.swift
//  FrameHero
//
//  DeepSeek Vision 驱动的构图方案生成（MVP Final Plan §6/§16）
//
//  ## 职责边界
//  - DeepSeek Vision 负责"思考"：理解场景 → 生成 1~3 个结构化构图方案
//  - 只在用户点「AI 构图」时调用一次（§19：每次分析动作最多 1 个请求）
//  - 实时跟踪/完成判断/Overlay 全部由 Apple Vision 本地执行
//
//  ## 输出契约（§6）
//  模型必须返回结构化 JSON（scene / main_subject / plans[]），
//  不接受自由文本作为主逻辑；解析失败自动重试一次，
//  仍失败则上层回退本地启发式方案（§18 错误处理）。
//

import Foundation

// MARK: - 提示词（§16）

enum CompositionPrompt {

    /// 系统角色：AI 摄影指导
    static let systemRole = """
    You are an AI photography director specializing in mobile photography composition.

    Your task is to analyze the provided camera image and recommend the best way to photograph the current scene.

    Analyze: main subject, scene type, background, visual balance, available space, lighting, and composition opportunities.

    Generate up to 3 composition plans. Each plan must be visually achievable by moving the smartphone camera.

    Rules:
    1. Do not provide long photography explanations.
    2. Do not provide generic advice — base everything on the actual image.
    3. Subject target coordinates must use normalized values from 0 to 1.
    4. Return valid JSON only. Do not return markdown.
    5. The main recommendation should be practical for a smartphone user.
    """

    /// 用户侧请求：附图 + 输出契约
    static let planRequest = """
    Analyze this camera image and generate up to 3 composition plans.

    Return JSON only, no markdown, exactly matching this schema:
    {
      "scene": { "type": "string", "description": "string" },
      "main_subject": { "type": "string", "description": "string" },
      "plans": [
        {
          "id": "plan_1",
          "title": "简短方案名（中文）",
          "style": "风格词（中文，如 电影感）",
          "description": "一句话说明（中文）",
          "composition": "rule_of_thirds | centered | symmetry | negative_space | environmental_portrait | close_up",
          "subject_target": { "x": 0.0, "y": 0.0 },
          "camera_action": { "horizontal": "left|right|none", "vertical": "up|down|none", "distance": "closer|keep|farther" },
          "focal_length": "1x | 2x | 0.5x | keep",
          "instruction": "一句中文动作指令（如：向右移动一点，让人物位于画面右侧）"
        }
      ]
    }

    Rules:
    - subject_target uses normalized coordinates, (0,0) = top-left, (1,1) = bottom-right.
    - Order plans by recommendation (best first).
    - All user-facing text (title/style/description/instruction) must be in Simplified Chinese.
    """
}

// MARK: - 响应模型（§6 契约）

/// DeepSeek Vision 的完整响应（Codable 宽松解析）
struct CompositionPlanResponse: Codable {
    struct SceneInfo: Codable {
        var type: String?
        var description: String?
    }

    struct SubjectInfo: Codable {
        var type: String?
        var description: String?
    }

    struct RemotePlan: Codable {
        var id: String?
        var title: String?
        var style: String?
        var description: String?
        var composition: String?
        var subjectTarget: SubjectTarget?
        var focalLength: String?
        var instruction: String?

        enum CodingKeys: String, CodingKey {
            case id, title, style, description, composition
            case subjectTarget = "subject_target"
            case focalLength = "focal_length"
            case instruction
        }
    }

    struct SubjectTarget: Codable {
        var x: Double?
        var y: Double?
    }

    var scene: SceneInfo?
    var mainSubject: SubjectInfo?
    var plans: [RemotePlan]?

    /// 稳健解析：容忍 ```json 围栏与前后杂文本（取首个 { 到最后一个 }）
    static func parse(from text: String) -> CompositionPlanResponse? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CompositionPlanResponse.self, from: data)
    }
}

// MARK: - 响应 → 本地方案模型

enum CompositionPlanMapper {

    /// 构图类型字符串 → 本地枚举（宽松映射，未知回退三分法）
    static func compositionType(from raw: String?) -> PlanCompositionStyle {
        switch raw?.lowercased() {
        case "centered", "center_symmetry", "symmetry":
            return .centerSymmetry
        case "negative_space":
            return .negativeSpace
        case "environmental_portrait", "environment_portrait":
            return .environmentPortrait
        case "close_up":
            return .centerSymmetry   // 特写：居中 + 距离建议 closer 表达
        case "leading_lines":
            return .leadingLines
        case "framing":
            return .framing
        case "foreground_layering":
            return .foregroundLayering
        default:
            return .ruleOfThirds
        }
    }

    /// 把远程方案数组映射为本地 CompositionPlan（过滤无效项，截取前 3 个）
    static func plans(from response: CompositionPlanResponse) -> [CompositionPlan] {
        // 主体类型 → 跟踪方式：人物用人体检测，其余（物品/建筑/食物）用显著性
        let subjectType = (response.mainSubject?.type ?? "").lowercased()
        let looksLikePerson = subjectType.contains("person") || subjectType.contains("people")
            || subjectType.contains("man") || subjectType.contains("woman")
            || subjectType.contains("child") || subjectType.contains("人")
        let remotePlans = (response.plans ?? []).prefix(3)
        let mapped = remotePlans.compactMap { remote -> CompositionPlan? in
            guard let title = remote.title, !title.isEmpty else { return nil }
            let target = remote.subjectTarget
            // subject_target 缺失或离谱时回退默认兴趣位（右三分）
            var x = target?.x ?? (2.0 / 3.0)
            var yFromTop = target?.y ?? 0.5
            x = min(max(x, 0.06), 0.94)
            yFromTop = min(max(yFromTop, 0.08), 0.92)

            return CompositionPlan(
                id: UUID(),
                title: title,
                styleWord: remote.style ?? "推荐",
                detail: remote.description ?? remote.instruction ?? "",
                composition: compositionType(from: remote.composition),
                subjectTarget: CGPoint(x: x, y: yFromTop),
                distance: .keep,
                focalHint: normalizeFocal(remote.focalLength),
                tracking: looksLikePerson ? .person : .saliency,
                instruction: remote.instruction,
                confidence: 0.9
            )
        }
        return mapped
    }

    /// 归一化焦段串（"2x"/"0.5x"/"keep"）→ 高亮倍率或 nil
    static func normalizeFocal(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw.lowercased() != "keep" else { return nil }
        return raw.lowercased()
    }
}
