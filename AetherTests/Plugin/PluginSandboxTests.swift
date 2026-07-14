import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// Task 14.3 测试：插件沙箱隔离与权限管理。
///
/// 覆盖范围：
/// 1. canExecute：工具名是否在 manifest 中声明
/// 2. canAccessNetwork / canAccessFileSystem / canAccessClipboard：权限校验
/// 3. maxExecutionTime / maxMemoryMB：执行限制常量
@MainActor
final class PluginSandboxTests: XCTestCase {
    // MARK: - 辅助：构造测试清单

    /// 构造带指定权限的测试插件清单
    private func makeManifest(
        permissions: [PluginPermission],
        tools: [PluginManifest.PluginToolDef] = [
            PluginManifest.PluginToolDef(
                name: "sandbox_tool", description: "沙箱测试工具",
                parameters: ["type": "object"]
            )
        ]
    ) -> PluginManifest {
        PluginManifest(
            id: "sandbox-test", name: "沙箱测试插件", version: "1.0.0",
            author: "测试", description: "沙箱测试", tools: tools,
            permissions: permissions, entryPoint: "main.js"
        )
    }

    // MARK: - canExecute

    /// canExecute 对 manifest 中声明的工具返回 true
    func testCanExecuteDeclaredTool() {
        let sandbox = PluginSandbox(manifest: makeManifest(permissions: []))
        XCTAssertTrue(sandbox.canExecute(toolName: "sandbox_tool"))
    }

    /// canExecute 对未声明的工具返回 false
    func testCannotExecuteUndeclaredTool() {
        let sandbox = PluginSandbox(manifest: makeManifest(permissions: []))
        XCTAssertFalse(sandbox.canExecute(toolName: "nonexistent_tool"))
    }

    /// canExecute 对空工具列表返回 false
    func testCanExecuteEmptyTools() {
        let sandbox = PluginSandbox(manifest: makeManifest(permissions: [], tools: []))
        XCTAssertFalse(sandbox.canExecute(toolName: "any_tool"))
    }

    // MARK: - canAccessNetwork

    /// 声明 network 权限时 canAccessNetwork 返回 true
    func testCanAccessNetworkWithPermission() {
        let sandbox = PluginSandbox(manifest: makeManifest(
            permissions: [PluginPermission(type: .network, description: nil)]
        ))
        XCTAssertTrue(sandbox.canAccessNetwork())
    }

    /// 未声明 network 权限时 canAccessNetwork 返回 false
    func testCannotAccessNetworkWithoutPermission() {
        let sandbox = PluginSandbox(manifest: makeManifest(
            permissions: [PluginPermission(type: .clipboard, description: nil)]
        ))
        XCTAssertFalse(sandbox.canAccessNetwork())
    }

    /// 空权限列表时 canAccessNetwork 返回 false
    func testCannotAccessNetworkWithEmptyPermissions() {
        let sandbox = PluginSandbox(manifest: makeManifest(permissions: []))
        XCTAssertFalse(sandbox.canAccessNetwork())
    }

    // MARK: - canAccessFileSystem

    /// 声明 fileSystem 权限时 canAccessFileSystem 返回 true
    func testCanAccessFileSystemWithPermission() {
        let sandbox = PluginSandbox(manifest: makeManifest(
            permissions: [PluginPermission(type: .fileSystem, description: nil)]
        ))
        XCTAssertTrue(sandbox.canAccessFileSystem())
    }

    /// 未声明 fileSystem 权限时 canAccessFileSystem 返回 false
    func testCannotAccessFileSystemWithoutPermission() {
        let sandbox = PluginSandbox(manifest: makeManifest(permissions: []))
        XCTAssertFalse(sandbox.canAccessFileSystem())
    }

    // MARK: - canAccessClipboard

    /// 声明 clipboard 权限时 canAccessClipboard 返回 true
    func testCanAccessClipboardWithPermission() {
        let sandbox = PluginSandbox(manifest: makeManifest(
            permissions: [PluginPermission(type: .clipboard, description: nil)]
        ))
        XCTAssertTrue(sandbox.canAccessClipboard())
    }

    /// 未声明 clipboard 权限时 canAccessClipboard 返回 false
    func testCannotAccessClipboardWithoutPermission() {
        let sandbox = PluginSandbox(manifest: makeManifest(
            permissions: [PluginPermission(type: .network, description: nil)]
        ))
        XCTAssertFalse(sandbox.canAccessClipboard())
    }

    // MARK: - 多权限组合

    /// 同时声明多个权限时各检查独立返回正确值
    func testMultiplePermissions() {
        let sandbox = PluginSandbox(manifest: makeManifest(permissions: [
            PluginPermission(type: .network, description: nil),
            PluginPermission(type: .clipboard, description: nil),
            PluginPermission(type: .location, description: nil),
        ]))
        XCTAssertTrue(sandbox.canAccessNetwork())
        XCTAssertTrue(sandbox.canAccessClipboard())
        XCTAssertFalse(sandbox.canAccessFileSystem())
    }

    // MARK: - 执行限制

    /// maxExecutionTime 应为 30 秒
    func testMaxExecutionTime() {
        let sandbox = PluginSandbox(manifest: makeManifest(permissions: []))
        XCTAssertEqual(sandbox.maxExecutionTime, 30)
    }

    /// maxMemoryMB 应为 50MB
    func testMaxMemoryMB() {
        let sandbox = PluginSandbox(manifest: makeManifest(permissions: []))
        XCTAssertEqual(sandbox.maxMemoryMB, 50)
    }
}
