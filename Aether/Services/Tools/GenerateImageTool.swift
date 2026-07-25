import Foundation
import AetherFoundation

/// v1.3: 图像生成工具。
///
/// 调用 `MultimodalFacade.generateImage` 进行端侧图像生成。
/// v1.3 占位实现返回 `platformUnsupported`，v1.5 集成 SD Mobile 后启用。
///
/// 调用方式：execute(arguments: ["prompt": "一只可爱的猫咪", "width": 512, "height": 512])
final class GenerateImageTool: ToolProtocol, @unchecked Sendable {
    var definition: ToolDefinition {
        ToolDefinition(
            name: "generate_image",
            description: "使用端侧 Stable Diffusion Mobile 生成图像（v1.3 占位，v1.5 启用）",
            parameters: [
                "type": "object",
                "properties": [
                    "prompt": ["type": "string", "description": "文本提示，描述要生成的图像"],
                    "negative_prompt": ["type": "string", "description": "负面提示，不希望出现的内容"],
                    "width": ["type": "integer", "description": "图像宽度，默认 512"],
                    "height": ["type": "integer", "description": "图像高度，默认 512"],
                    "steps": ["type": "integer", "description": "推理步数，默认 20"],
                    "seed": ["type": "integer", "description": "随机种子，不传则随机"]
                ],
                "required": ["prompt"]
            ]
        )
    }

    @MainActor
    func execute(arguments: [String: Any]) async throws -> String {
        guard let prompt = arguments["prompt"] as? String, !prompt.isEmpty else {
            return "错误：请提供 prompt 参数"
        }
        let negativePrompt = arguments["negative_prompt"] as? String
        let width = arguments["width"] as? Int ?? 512
        let height = arguments["height"] as? Int ?? 512
        let steps = arguments["steps"] as? Int ?? 20
        let seed = arguments["seed"] as? Int

        let facade = MultimodalFacade.shared
        do {
            let _ = try await facade.generateImage(
                prompt: prompt,
                negativePrompt: negativePrompt,
                width: width,
                height: height,
                steps: steps,
                seed: seed.map(UInt64.init)
            )
            return "图像生成成功"
        } catch let error as MultimodalError {
            return "图像生成失败：\(error.errorDescription ?? "未知错误")"
        } catch {
            return "图像生成失败：\(error.localizedDescription)"
        }
    }
}
