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

    // MARK: - 2. 仓库 ID 有效性

    /// 验证每个模型的双源仓库 ID 格式正确。
    func testModelReposValid() {
        for model in OnDeviceModelCatalog.models {
            // HuggingFace 仓库 ID
            XCTAssertFalse(model.huggingFaceRepo.isEmpty, "HuggingFace 仓库 ID 不应为空：\(model.id)")
            XCTAssertTrue(model.huggingFaceRepo.contains("/"), "HuggingFace 仓库 ID 应包含 '/'（org/model 格式）：\(model.id)")

            // ModelScope 仓库 ID
            XCTAssertNotNil(model.modelScopeRepo, "ModelScope 仓库 ID 不应为 nil：\(model.id)")
            XCTAssertTrue(model.modelScopeRepo?.contains("/") ?? false, "ModelScope 仓库 ID 应包含 '/'（org/model 格式）：\(model.id)")
        }
    }

    // MARK: - 3. 仓库选择器

    /// 验证 repo(for:) 方法根据下载源返回对应仓库 ID。
    func testRepoForDownloadSource() {
        let model = OnDeviceModelCatalog.models[0]
        XCTAssertEqual(model.repo(for: .domestic), model.modelScopeRepo, "国内源应返回 ModelScope 仓库 ID")
        XCTAssertEqual(model.repo(for: .international), model.huggingFaceRepo, "国外源应返回 HuggingFace 仓库 ID")
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

    // MARK: - 补充小缺口测试

    /// 验证 DownloadSource.displayName 的具体字符串内容。
    /// 覆盖 OnDeviceModelCatalog.swift 第 10-13 行的 switch case 字符串字面量。
    func testDownloadSourceDisplayNameContent() {
        XCTAssertEqual(DownloadSource.domestic.displayName, "国内（ModelScope）",
                       "domestic displayName 应为 '国内（ModelScope）'")
        XCTAssertEqual(DownloadSource.international.displayName, "国外（HuggingFace）",
                       "international displayName 应为 '国外（HuggingFace）'")
    }

    /// 遍历 OnDeviceModelCatalog.models，对每个模型验证 repo(for:) 的两个分支。
    /// 覆盖 OnDeviceModelEntry.repo(for:) 的 domestic 与 international 两个 case 分支。
    func testRepoForDownloadSourceForAllModels() {
        for model in OnDeviceModelCatalog.models {
            XCTAssertEqual(model.repo(for: .domestic), model.modelScopeRepo,
                           "\(model.id): 国内源应返回 ModelScope 仓库 ID")
            XCTAssertEqual(model.repo(for: .international), model.huggingFaceRepo,
                           "\(model.id): 国外源应返回 HuggingFace 仓库 ID")
        }
    }

    /// 验证 DownloadSource 的 Codable 往返：编码后解码应与原值相等。
    func testDownloadSourceCodableRoundTrip() throws {
        for source in DownloadSource.allCases {
            let data = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(DownloadSource.self, from: data)
            XCTAssertEqual(decoded, source, "DownloadSource.\(source) Codable 往返应保持一致")
        }
    }

    /// 验证 DownloadSource 的 rawValue 正确，且可通过 rawValue 构造对应 case。
    func testDownloadSourceRawValues() {
        XCTAssertEqual(DownloadSource.domestic.rawValue, "domestic")
        XCTAssertEqual(DownloadSource.international.rawValue, "international")
        XCTAssertEqual(DownloadSource(rawValue: "domestic"), .domestic)
        XCTAssertEqual(DownloadSource(rawValue: "international"), .international)
        XCTAssertNil(DownloadSource(rawValue: "unknown"), "未知 rawValue 应构造失败返回 nil")
    }
}
