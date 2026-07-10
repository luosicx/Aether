import XCTest
@testable import Aether

/// 端侧模型目录单元测试：验证目录结构、模型字段完整性与双源 URL 有效性。
final class OnDeviceModelCatalogTests: XCTestCase {

    // MARK: - 1. 目录结构与数量

    /// 验证目录包含 3 个预定义模型。
    func testCatalogHasThreeModels() {
        XCTAssertEqual(OnDeviceModelCatalog.models.count, 3, "目录应包含 3 个模型")
    }

    /// 验证每个模型字段非空。
    func testAllModelFieldsNonEmpty() {
        for model in OnDeviceModelCatalog.models {
            XCTAssertFalse(model.id.isEmpty, "模型 ID 不应为空：\(model)")
            XCTAssertFalse(model.name.isEmpty, "模型名不应为空：\(model.id)")
            XCTAssertFalse(model.description.isEmpty, "模型简介不应为空：\(model.id)")
            XCTAssertGreaterThan(model.estimatedSizeMB, 0, "模型大小应大于 0：\(model.id)")
            XCTAssertFalse(model.sha256.isEmpty, "SHA256 不应为空：\(model.id)")
            XCTAssertEqual(model.sha256.count, 64, "SHA256 应为 64 位十六进制：\(model.id)")
        }
    }

    // MARK: - 2. URL 有效性

    /// 验证每个模型的双源 URL 格式正确。
    func testModelURLsValid() {
        for model in OnDeviceModelCatalog.models {
            // HuggingFace URL
            XCTAssertEqual(model.huggingFaceURL.scheme, "https", "HuggingFace URL 应为 https：\(model.id)")
            XCTAssertEqual(model.huggingFaceURL.host, "huggingface.co", "HuggingFace URL host 应为 huggingface.co：\(model.id)")
            XCTAssertTrue(
                model.huggingFaceURL.path.contains("model.safetensors"),
                "HuggingFace URL 路径应包含 model.safetensors：\(model.id)"
            )

            // ModelScope URL
            XCTAssertEqual(model.modelScopeURL.scheme, "https", "ModelScope URL 应为 https：\(model.id)")
            XCTAssertEqual(model.modelScopeURL.host, "www.modelscope.cn", "ModelScope URL host 应为 www.modelscope.cn：\(model.id)")
            XCTAssertTrue(
                model.modelScopeURL.absoluteString.contains("model.safetensors"),
                "ModelScope URL 应包含 model.safetensors：\(model.id)"
            )
        }
    }

    // MARK: - 3. URL 选择器

    /// 验证 url(for:) 方法根据下载源返回对应 URL。
    func testURLForDownloadSource() {
        let model = OnDeviceModelCatalog.models[0]
        XCTAssertEqual(model.url(for: .domestic), model.modelScopeURL, "国内源应返回 ModelScope URL")
        XCTAssertEqual(model.url(for: .international), model.huggingFaceURL, "国外源应返回 HuggingFace URL")
    }

    // MARK: - 4. 模型查找

    /// 验证按 ID 查找模型。
    func testFindById() {
        let model = OnDeviceModelCatalog.models[0]
        let found = OnDeviceModelCatalog.find(id: model.id)
        XCTAssertNotNil(found, "按 ID 查找应返回模型")
        XCTAssertEqual(found?.id, model.id, "查找结果应匹配")
        XCTAssertNil(OnDeviceModelCatalog.find(id: "nonexistent"), "不存在的 ID 应返回 nil")
    }

    // MARK: - 5. DownloadSource 枚举

    /// 验证下载源枚举有两个 case 且 displayName 非空。
    func testDownloadSourceCases() {
        XCTAssertEqual(DownloadSource.allCases.count, 2, "下载源应有 2 个选项")
        for source in DownloadSource.allCases {
            XCTAssertFalse(source.displayName.isEmpty, "下载源 displayName 不应为空：\(source)")
        }
        XCTAssertEqual(DownloadSource.domestic.rawValue, "domestic", "国内源 rawValue 应为 domestic")
        XCTAssertEqual(DownloadSource.international.rawValue, "international", "国外源 rawValue 应为 international")
    }
}
