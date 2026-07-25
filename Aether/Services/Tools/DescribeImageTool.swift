import Foundation
import AetherFoundation

/// v1.3: 图像理解工具。
///
/// 调用 `MultimodalFacade.describeImage` 端侧 VLM 进行图像理解。
/// 模型未加载时返回提示信息，引导用户先下载模型。
///
/// 调用方式：execute(arguments: ["image_path": "...", "prompt": "描述这张图片"])
final class DescribeImageTool: ToolProtocol, @unchecked Sendable {
    var definition: ToolDefinition {
        ToolDefinition(
            name: "describe_image",
            description: "使用端侧 VLM（视觉语言模型）理解图像内容，回答关于图像的问题或生成描述",
            parameters: [
                "type": "object",
                "properties": [
                    "image_path": ["type": "string", "description": "图像文件路径"],
                    "prompt": ["type": "string", "description": "文本提示，如「描述这张图片」「图中有几个物体？」"]
                ],
                "required": ["image_path", "prompt"]
            ]
        )
    }

    @MainActor
    func execute(arguments: [String: Any]) async throws -> String {
        guard let imagePath = arguments["image_path"] as? String, !imagePath.isEmpty else {
            return "错误：请提供 image_path 参数"
        }
        guard let prompt = arguments["prompt"] as? String, !prompt.isEmpty else {
            return "错误：请提供 prompt 参数"
        }

        let facade = MultimodalFacade.shared
        do {
            let description = try await facade.describeImage(at: URL(fileURLWithPath: imagePath), prompt: prompt)
            return description
        } catch let error as MultimodalError {
            return "图像理解失败：\(error.errorDescription ?? "未知错误")"
        } catch {
            return "图像理解失败：\(error.localizedDescription)"
        }
    }
}
