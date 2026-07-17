import XCTest
import AetherRust

/// Rust FFI 边界条件测试（Task 10）。
///
/// 覆盖 8 个 Rust 模块在边界输入下的行为：
/// - Sha256 / Token / Chunker / Vector / SSE / RateLimiter / Redactor / Sandbox
///
/// 设计目标：
/// - 验证 FFI 层在异常输入下不崩溃（空、超大、无效字节、负值等）
/// - 验证底层 Rust 行为契约（如空向量返回 0、零范数返回 0）
/// - 稳定可重复，无 flaky
///
/// 注意：沙箱（Sandbox）相关测试仅在非 iOS 平台编译（与 `Sandbox.swift` 的
/// `#if !os(iOS)` 一致，wasmtime 不支持 iOS target）。
final class RustFFIBoundaryTests: XCTestCase {

    /// xcframework 标准相对路径（用于跳过未配置环境）。
    /// 测试 target 通过 SPM 解析 `AetherCore` 包时，xcframework 应在下列路径之一。
    private static let xcframeworkPath = "Packages/AetherCore/aether_core.xcframework"

    /// 所有测试前置：xcframework 未配置时跳过，避免链接失败导致误报。
    /// 注意：本检查只能在运行时执行；若 xcframework 完全未链接，编译期就会失败，
    /// 此处主要用于防御本地开发环境的旧 checkout。
    override func setUpWithError() throws {
        try super.setUpWithError()
        // 检查 xcframework 是否存在于仓库内（兼容从仓库根目录运行的场景）。
        let candidates = [
            xcframeworkPath,                                  // 仓库根目录运行
            "../" + xcframeworkPath,                          // 测试 bundle 子目录运行
            "../../" + xcframeworkPath,                       // 更深层级
        ]
        let exists = candidates.contains { FileManager.default.fileExists(atPath: $0) }
        try XCTSkipIf(!exists, "aether_core.xcframework 未在本地配置，跳过 Rust FFI 边界测试")
    }

    // MARK: - SubTask 10.2: Sha256 边界

    /// 空输入应返回已知空哈希值。
    func testSha256EmptyInputReturnsKnownHash() {
        let hasher = AetherRustSha256()
        let result = hasher.finalize()
        XCTAssertEqual(
            result,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "空输入应返回 SHA-256 已知空哈希"
        )
    }

    /// 超大输入（10MB 字符串）不应崩溃，且返回 64 字符 hex。
    func testSha256LargeInput10MBDoesNotCrash() {
        // 10 MB = 10 * 1024 * 1024 字节
        let byteCount = 10 * 1024 * 1024
        let pattern = "abcdefghijklmnopqrstuvwxyz0123456789" // 36 字符
        var data = Data()
        data.reserveCapacity(byteCount)
        // 用重复 pattern 填充到 10MB，避免一次性构造超大字符串
        while data.count + pattern.utf8.count <= byteCount {
            data.append(contentsOf: pattern.utf8)
        }
        // 补齐剩余字节
        let remaining = byteCount - data.count
        if remaining > 0 {
            data.append(contentsOf: pattern.utf8.prefix(remaining))
        }
        XCTAssertEqual(data.count, byteCount, "应构造恰好 10MB 数据")

        let hasher = AetherRustSha256()
        hasher.update(data)
        let result = hasher.finalize()

        XCTAssertEqual(result.count, 64, "10MB 输入应返回 64 字符 hex")
        XCTAssertTrue(result.allSatisfy { $0.isHexDigit }, "输出应全部为十六进制字符")
        // 确定性：相同输入应产生相同输出
        let hasher2 = AetherRustSha256()
        hasher2.update(data)
        XCTAssertEqual(hasher2.finalize(), result, "相同超大输入应产生相同哈希")
    }

    /// 无效 UTF-8 字节序列仍可哈希（按字节处理，Data 不要求 UTF-8 合法）。
    func testSha256InvalidUtf8BytesStillHashable() {
        // 0xff 0xfe 0xfd 在 UTF-8 中是非法起始字节
        let invalidBytes: [UInt8] = [0xff, 0xfe, 0xfd, 0x80, 0xc0, 0xc1]
        let data = Data(invalidBytes)

        let hasher = AetherRustSha256()
        hasher.update(data)
        let result = hasher.finalize()

        XCTAssertEqual(result.count, 64, "无效 UTF-8 字节仍应产生 64 字符 hex")
        XCTAssertTrue(result.allSatisfy { $0.isHexDigit }, "输出应全部为十六进制字符")
        // 确定性验证
        let hasher2 = AetherRustSha256()
        hasher2.update(data)
        XCTAssertEqual(hasher2.finalize(), result, "相同字节序列应产生相同哈希")
    }

    // MARK: - SubTask 10.3: Token 边界

    /// 空字符串应返回 0 token。
    func testTokenEmptyStringReturnsZero() {
        let tokens = AetherRustToken.estimateTokens("")
        XCTAssertEqual(tokens, 0, "空字符串应返回 0 token")
    }

    /// 超长字符串（10 万字）不应崩溃。
    func testTokenVeryLongStringDoesNotCrash() {
        // 10 万字符的中文文本（每个字符是非 ASCII，会走 1.5x 估算路径）
        let text = String(repeating: "测", count: 100_000)
        XCTAssertEqual(text.count, 100_000, "应构造 10 万字符")

        let tokens = AetherRustToken.estimateTokens(text)
        XCTAssertGreaterThan(tokens, 0, "10 万字文本应返回正数 token")
        // 确定性验证
        XCTAssertEqual(AetherRustToken.estimateTokens(text), tokens, "相同输入应产生相同估算")
    }

    /// 纯 emoji 应返回合理的 token 数（非负，非崩溃）。
    func testTokenPureEmojiReturnsReasonableCount() {
        let text = "🎉🎊🎈" // 3 个 emoji
        let tokens = AetherRustToken.estimateTokens(text)
        XCTAssertGreaterThanOrEqual(tokens, 0, "纯 emoji 不应崩溃，应返回非负 token 数")
        // emoji 均为非 ASCII，按 1.5x 估算至少应有几个 token
        XCTAssertGreaterThan(tokens, 0, "3 个 emoji 应估算出正数 token")
    }

    // MARK: - SubTask 10.4: Chunker 边界

    /// 空文本应返回 0 chunks。
    func testChunkerEmptyTextReturnsZeroChunks() {
        let chunks = AetherRustChunker.chunkDocument("", maxChars: 512, overlapChars: 128)
        XCTAssertTrue(chunks.isEmpty, "空文本应返回 0 个 chunk")
    }

    /// 单句超长（无标点）应返回 1 个 chunk（不二次切分，保持语义完整）。
    func testChunkerSingleLongSentenceNoPunctuationReturnsOneChunk() {
        // 1000 字符无空格无标点的长句
        let longSentence = String(repeating: "a", count: 1000)
        let chunks = AetherRustChunker.chunkDocument(longSentence, maxChars: 100, overlapChars: 20)
        XCTAssertEqual(chunks.count, 1, "单句超长无标点应返回 1 个 chunk（不二次切分）")
        XCTAssertEqual(chunks[0], longSentence, "chunk 内容应与原文本一致")
    }

    /// 无标点的短文本应返回 1 个 chunk。
    func testChunkerShortTextNoPunctuationReturnsOneChunk() {
        let shortText = "hello world without punctuation"
        let chunks = AetherRustChunker.chunkDocument(shortText, maxChars: 512, overlapChars: 128)
        XCTAssertEqual(chunks.count, 1, "无标点短文本应返回 1 个 chunk")
        XCTAssertEqual(chunks[0], shortText, "chunk 内容应与原文本一致")
    }

    // MARK: - SubTask 10.5: Vector 边界

    /// 空向量应返回相似度 0（长度 0，范数 0）。
    func testVectorEmptyReturnsZero() {
        // f32 空向量
        let simF32 = AetherRustVector.cosine([Float](), [Float]())
        XCTAssertEqual(simF32, 0.0, "f32 空向量余弦相似度应为 0")
        // f64 空向量
        let simF64 = AetherRustVector.cosine([Double](), [Double]())
        XCTAssertEqual(simF64, 0.0, "f64 空向量余弦相似度应为 0")
        // 一空一非空
        XCTAssertEqual(AetherRustVector.cosine([], [1.0 as Float]), 0.0, "一空一非空应返回 0")
    }

    /// 零范数向量（全 0）不应崩溃，应返回 0（避免除零）。
    func testVectorZeroNormDoesNotCrash() {
        let zeroVec: [Float] = [0.0, 0.0, 0.0]
        let nonZero: [Float] = [1.0, 2.0, 3.0]
        let sim = AetherRustVector.cosine(zeroVec, nonZero)
        XCTAssertEqual(sim, 0.0, "零范数向量应返回 0（避免除零）")
        // 双零向量
        XCTAssertEqual(AetherRustVector.cosine(zeroVec, zeroVec), 0.0, "双零向量应返回 0")

        // f64 同样验证
        let zeroF64: [Double] = [0.0, 0.0, 0.0]
        XCTAssertEqual(AetherRustVector.cosine(zeroF64, zeroF64), 0.0, "f64 双零向量应返回 0")
    }

    /// 长度不等的两个向量做相似度应返回 0（与现有 API 契约一致）。
    func testVectorDifferentLengthsReturnsZero() {
        // f32 长度不等
        let simF32 = AetherRustVector.cosine([1.0, 2.0, 3.0] as [Float], [1.0, 2.0] as [Float])
        XCTAssertEqual(simF32, 0.0, "f32 长度不等应返回 0")
        // f64 长度不等
        let simF64 = AetherRustVector.cosine([1.0, 2.0, 3.0] as [Double], [1.0] as [Double])
        XCTAssertEqual(simF64, 0.0, "f64 长度不等应返回 0")
    }

    // MARK: - SubTask 10.6: SSE 边界

    /// 不完整流（无 \n\n 分隔）应在单行级别正常解析。
    /// FFI 层 `parseChunk` 接受单行输入，调用方负责按行切分；
    /// 此测试验证无 \n\n 的"半行"输入不会被误判为有效 data 行。
    func testSSEIncompleteStreamNoNewlineSeparator() {
        let parser = AetherRustSSEParser()
        // 无 data: 前缀的纯文本应返回 nil（非 data 行）
        XCTAssertNil(parser.parseChunk("incomplete chunk without data prefix"),
                     "无 data: 前缀的输入应返回 nil")
        // 无换行分隔的多个事件拼接：FFI 一次性解析整行，无 data: 前缀（行首是 event:）则返回 nil
        XCTAssertNil(parser.parseChunk("event: ping data: {\"x\":1}"),
                     "拼接行无合法 data: 前缀（被当作非 data 行）应返回 nil")
        // 空 data: 行：payload 为空字符串，serde_json 解析失败 → 返回 nil（外层）
        // 说明：与 `data: [DONE]` 不同，[DONE] 显式返回 Some(None)，空 payload 直接解析失败。
        XCTAssertNil(parser.parseChunk("data:"),
                     "空 data: 行 payload 为空串，JSON 解析失败应返回 nil")
        // 仅有前缀空白也应同样返回 nil
        XCTAssertNil(parser.parseChunk("data:   "),
                     "仅有空白的 data: 行 payload 为空串，应返回 nil")
    }

    /// 流无 [DONE] 标记应正常解析（[DONE] 非必须）。
    func testSSEStreamWithoutDoneMarkerParsesNormally() {
        let parser = AetherRustSSEParser()
        // 模拟一段无 [DONE] 的流：两行 data，分别提取 content
        let line1 = #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#
        let line2 = #"data: {"choices":[{"delta":{"content":" World"}}]}"#

        let c1 = parser.parseChunk(line1)
        XCTAssertEqual(c1 ?? nil, "Hello", "第一行应解析出 'Hello'")

        let c2 = parser.parseChunk(line2)
        XCTAssertEqual(c2 ?? nil, " World", "第二行应解析出 ' World'（无 [DONE] 不影响解析）")

        // extractContent 也应正常工作
        XCTAssertEqual(parser.extractContent(line1), "Hello")
    }

    /// 嵌套 data: 前缀（如 `data: data: foo`）应按现有实现验证：
    /// `strip_data_prefix` 仅剥离一次前缀，剩余 `data: foo` 作为 payload 尝试 JSON 解析，
    /// 非 JSON 字符串 → 返回 nil（与 Rust 侧 `parse_chunk` 行为一致）。
    func testSSENestedDataPrefix() {
        let parser = AetherRustSSEParser()
        // data: data: foo → 剥离一次前缀后 payload = "data: foo"，
        // serde_json 解析失败（不是合法 JSON 对象）→ parseChunk 返回 nil
        let nested = "data: data: foo"
        XCTAssertNil(parser.parseChunk(nested),
                     "嵌套 data: 前缀的 payload 'data: foo' 非 JSON，应返回 nil")
        // extractContent 同样返回 nil
        XCTAssertNil(parser.extractContent(nested),
                     "extractContent 对非 JSON payload 应返回 nil")

        // 对照：合法 JSON 对象 payload 中 content 字段值为 "data: foo" 应解析成功
        // 说明：parseChunk 期望 payload 是 ChatChunk 结构（{"choices":[...]}），不是 JSON 字符串。
        let validChatChunk = #"data: {"choices":[{"delta":{"content":"data: foo"}}]}"#
        let result = parser.parseChunk(validChatChunk)
        XCTAssertEqual(result ?? nil, "data: foo",
                       "JSON 对象 content 字段值为 'data: foo' 应被正确解析")
        XCTAssertEqual(parser.extractContent(validChatChunk), "data: foo",
                       "extractContent 应提取 content 字段值 'data: foo'")
    }

    // MARK: - SubTask 10.7: RateLimiter 边界

    /// 时间戳倒退（等价于"负时间戳"场景，UInt64 不能传负值，用倒退时间模拟）
    /// 不应崩溃，且不应补充令牌。
    func testRateLimiterBackwardTimestampDoesNotCrash() {
        let initMs: UInt64 = 10_000
        let bucket = AetherRustTokenBucket(capacity: 10.0, refillRate: 100.0, nowMs: initMs)
        // 消耗 5 个令牌
        _ = bucket.acquire(5.0, nowMs: initMs)
        let afterAcquire = bucket.availableTokens(nowMs: initMs)
        XCTAssertEqual(afterAcquire, 5.0, accuracy: 0.001, "消耗后应剩 5 个令牌")

        // 时间倒退到 initMs - 1000（早于初始时间），不应补充令牌
        let backwardMs: UInt64 = initMs - 1000
        let afterBackward = bucket.availableTokens(nowMs: backwardMs)
        XCTAssertEqual(afterBackward, 5.0, accuracy: 0.001,
                       "时间倒退不应补充令牌（避免负 elapsed）")

        // 时间戳 0（epoch 起点）也不应崩溃
        let zeroMs: UInt64 = 0
        let bucket2 = AetherRustTokenBucket(capacity: 5.0, refillRate: 1.0, nowMs: zeroMs)
        XCTAssertEqual(bucket2.availableTokens(nowMs: zeroMs), 5.0, accuracy: 0.001,
                       "nowMs=0 初始化不应崩溃")
        // 在 nowMs=0 后再 acquire（同时间）应正常工作
        XCTAssertNil(bucket2.acquire(1.0, nowMs: zeroMs), "nowMs=0 acquire 应成功")
    }

    /// 超大令牌数（Int32.max ≈ 2.1B）不应溢出。
    /// Double 可精确表示 Int32.max，acquire 在容量内应成功。
    func testRateLimiterLargeTokenCountNoOverflow() {
        let largeN = Double(Int32.max) // ≈ 2.147483647e9
        let ts: UInt64 = 1_000_000

        // 场景 1：capacity = Int32.max，acquire(Int32.max) 应成功
        let bucket1 = AetherRustTokenBucket(capacity: largeN, refillRate: 1.0, nowMs: ts)
        let wait1 = bucket1.acquire(largeN, nowMs: ts)
        XCTAssertNil(wait1, "容量等于 Int32.max 时 acquire 同等数量应成功（无溢出）")
        let remaining = bucket1.availableTokens(nowMs: ts)
        XCTAssertEqual(remaining, 0.0, accuracy: 1.0,
                       "耗尽后剩余令牌应为 0（允许浮点误差）")

        // 场景 2：小容量桶 acquire(Int32.max) 应失败但不崩溃，返回正数等待时间
        let bucket2 = AetherRustTokenBucket(capacity: 10.0, refillRate: 1.0, nowMs: ts)
        let wait2 = bucket2.acquire(largeN, nowMs: ts)
        XCTAssertNotNil(wait2, "小容量桶请求超大令牌数应返回等待时间")
        XCTAssertGreaterThan(wait2!, 0, "等待时间应为正数")
        // 验证未溢出为 NaN 或 inf
        XCTAssertFalse(wait2!.isNaN, "等待时间不应为 NaN")
        XCTAssertFalse(wait2!.isInfinite, "等待时间不应为 inf")
    }

    // MARK: - SubTask 10.8: Redactor 边界

    /// 空输入应返回空输出。
    func testRedactorEmptyInputReturnsEmpty() {
        let result = AetherRustRedactor.redact("")
        XCTAssertEqual(result, "", "空输入应返回空字符串")
    }

    /// 无匹配模式应原样返回。
    func testRedactorNoMatchReturnsOriginal() {
        let inputs = [
            "Network timeout occurred while connecting to server",
            "用户登录失败，请重试",
            "Plain text without any sensitive data 12345",
            "   ",                       // 仅空白
            "Multi\nline\ntext",         // 多行
        ]
        for input in inputs {
            let result = AetherRustRedactor.redact(input)
            XCTAssertEqual(result, input, "无敏感模式匹配时应原样返回: \(input.prefix(20))")
        }
    }

    /// 超长输入（10 万字）不应崩溃，且敏感片段应被替换。
    func testRedactorVeryLongInputDoesNotCrash() {
        // 构造 10 万字符的混合文本（含敏感片段）
        let unit = "用户 user@test.com 访问 https://example.com/path?token=secret 出错 "
        let repeats = (100_000 / unit.count) + 1
        let longText = String(repeating: unit, count: repeats)
        XCTAssertGreaterThan(longText.count, 100_000, "应构造至少 10 万字符")

        // redact 内部用预编译正则，对长文本线性时间匹配，不应崩溃。
        let result = AetherRustRedactor.redact(longText)
        XCTAssertFalse(result.isEmpty, "脱敏结果不应为空")
        // 验证敏感内容已被替换（脱敏标记长度与原文不同，所以不比较总长度）
        XCTAssertFalse(result.contains("user@test.com"), "邮箱应被脱敏")
        XCTAssertFalse(result.contains("example.com"), "URL 应被脱敏")
        XCTAssertFalse(result.contains("token=secret"), "URL 内 token 字段应随 URL 一并脱敏")
        XCTAssertTrue(result.contains("[REDACTED_EMAIL]"), "应包含邮箱脱敏标记")
        XCTAssertTrue(result.contains("[REDACTED_URL]"), "应包含 URL 脱敏标记")
    }

    // MARK: - SubTask 10.9: Sandbox 边界
    // 沙箱（AetherRustSandbox）仅在非 iOS 平台编译（wasmtime 不支持 iOS target）

    #if !os(iOS)

    /// null 指针 / 无效输入场景：API 不直接暴露 null 指针给用户，
    /// 但通过 failable init 与返回 Optional 的 load 验证错误路径不崩溃。
    func testSandboxInvalidInputsReturnNilNotCrash() {
        // 极端配置（fuel=0, memory=1）应仍能创建引擎（不为 nil）
        let sandbox = AetherRustSandbox(maxFuel: 0, maxMemoryBytes: 1)
        XCTAssertNotNil(sandbox, "极端配置（fuel=0, memory=1）应仍能创建引擎")
        guard let sb = sandbox else { return }

        // 空 Data 应返回 nil（guard count > 0）
        XCTAssertNil(sb.load(Data()), "空 Data 应返回 nil 模块")
        // 无效 WASM 字节应返回 nil（编译失败，不崩溃）
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xff, 0xee])
        XCTAssertNil(sb.load(garbage), "无效 WASM 字节应返回 nil 模块")
    }

    /// 超长 JSON 参数（10MB）不应导致宿主崩溃，应正常返回成功或按 fuel/memory 限制拒绝。
    /// 使用内嵌的 add-one WASM 模块（接收 i32 参数，返回 arg+1）触发完整 callJson 路径。
    func testSandboxLargeJsonDoesNotCrashHost() throws {
        // 内嵌 add-one WASM 模块（编译自以下 WAT）：
        //   (module
        //     (memory (export "memory") 1)
        //     (func (export "execute") (param i32) (result i32)
        //       local.get 0
        //       i32.const 1
        //       i32.add))
        let addOneWasm = Data([
            // WASM 魔数与版本
            0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
            // Type section: 1 个函数类型 (i32) -> (i32)
            0x01, 0x06, 0x01, 0x60, 0x01, 0x7f, 0x01, 0x7f,
            // Function section: 1 个函数，使用 type 0
            0x03, 0x02, 0x01, 0x00,
            // Memory section: 1 个 memory，min=1 page
            0x05, 0x03, 0x01, 0x00, 0x01,
            // Export section: 2 个导出（memory, execute）
            0x07, 0x14, 0x02,
            0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x02, 0x00,
            0x07, 0x65, 0x78, 0x65, 0x63, 0x75, 0x74, 0x65, 0x00, 0x00,
            // Code section: local.get 0; i32.const 1; i32.add; end
            0x0a, 0x09, 0x01, 0x07, 0x00,
            0x20, 0x00,           // local.get 0
            0x41, 0x01,           // i32.const 1
            0x6a,                 // i32.add
            0x0b,                 // end function
        ])

        // 创建沙箱：fuel 充足（10M 指令），memory 1MB（小于 10MB args，可能触发 grow 失败）
        guard let sandbox = AetherRustSandbox(maxFuel: 10_000_000, maxMemoryBytes: 1024 * 1024) else {
            throw XCTSkip("无法创建沙箱引擎（可能 wasmtime 不可用）")
        }
        guard let module = sandbox.load(addOneWasm) else {
            throw XCTSkip("无法加载 add-one WASM 模块")
        }
        guard let instance = module.instantiate() else {
            throw XCTSkip("无法实例化 WASM 模块")
        }

        // 构造 10MB 的 JSON 参数字符串
        let unit = #"{"key":"value"}"#
        let targetBytes = 10 * 1024 * 1024
        let repeats = targetBytes / unit.utf8.count + 1
        let largeJson = String(repeating: unit, count: repeats)
        XCTAssertGreaterThan(largeJson.utf8.count, targetBytes, "应构造至少 10MB JSON")

        // 调用 callJson 不应崩溃。结果可能是：
        // - ok=true：wasmtime 默认允许内存增长到 4GB，10MB 可被容纳
        // - ok=false + error=MemoryLimit：若内存增长被拒
        // 两种结果都算"按 fuel/memory 限制截断或拒绝"，均符合预期。
        let result = instance.callJson(largeJson)
        if result.ok {
            // 成功：add-one 模块回写 args_len+1 字节，output 应非空
            XCTAssertFalse(result.output.isEmpty, "成功时 output 不应为空")
        } else {
            // 失败：error 应为已知错误类型，不应是 NullResult/InvalidJson（宿主侧 bug）
            XCTAssertNotNil(result.error, "失败时应包含 error 字段")
            let knownErrors = ["MemoryLimit", "OutOfFuel", "Utf8", "Call",
                               "MissingMemory", "MissingExecute"]
            XCTAssertTrue(knownErrors.contains(result.error ?? ""),
                          "error 应为已知类型，实际: \(result.error ?? "nil")")
        }
    }

    /// fuel 耗尽应返回 OutOfFuel 错误而非崩溃。
    /// 使用内嵌的无限循环 WASM 模块触发 fuel 耗尽。
    func testSandboxFuelExhaustionReturnsError() throws {
        // 内嵌的无限循环 WASM 模块（编译自以下 WAT）：
        //   (module
        //     (memory (export "memory") 1)
        //     (func (export "execute") (param i32) (result i32)
        //       (loop $forever (br $forever))
        //       (i32.const 0)))
        // 字节码：60 字节，含 memory 与 execute 导出，execute 内无限循环。
        let infiniteLoopWasm = Data([
            // WASM 魔数与版本
            0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
            // Type section: 1 个函数类型 (i32) -> (i32)
            0x01, 0x06, 0x01, 0x60, 0x01, 0x7f, 0x01, 0x7f,
            // Function section: 1 个函数，使用 type 0
            0x03, 0x02, 0x01, 0x00,
            // Memory section: 1 个 memory，min=1 page
            0x05, 0x03, 0x01, 0x00, 0x01,
            // Export section: 2 个导出（memory, execute）
            0x07, 0x14, 0x02,
            0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x02, 0x00,   // "memory" -> memory 0
            0x07, 0x65, 0x78, 0x65, 0x63, 0x75, 0x74, 0x65, 0x00, 0x00, // "execute" -> func 0
            // Code section: 1 个函数体
            0x0a, 0x0b, 0x01, 0x09, 0x00,
            0x03, 0x40,           // loop $forever (void block type)
            0x0c, 0x00,           // br 0 (branch to loop start)
            0x0b,                 // end loop
            0x41, 0x00,           // i32.const 0
            0x0b,                 // end function
        ])

        // 创建一个 fuel 极小的沙箱（1000 条指令），让无限循环快速耗尽
        guard let sandbox = AetherRustSandbox(maxFuel: 1_000, maxMemoryBytes: 64 * 1024) else {
            throw XCTSkip("无法创建沙箱引擎（可能 wasmtime 不可用）")
        }
        guard let module = sandbox.load(infiniteLoopWasm) else {
            throw XCTSkip("无法加载内嵌 WASM 模块（wasmtime target 可能不支持）")
        }
        guard let instance = module.instantiate() else {
            throw XCTSkip("无法实例化 WASM 模块")
        }

        // 调用 execute 应触发 fuel 耗尽，返回 ok=false + error=OutOfFuel
        let result = instance.callJson("")
        XCTAssertFalse(result.ok, "fuel 耗尽时应返回 ok=false")
        XCTAssertEqual(result.error, "OutOfFuel",
                       "fuel 耗尽错误类型应为 'OutOfFuel'")
    }

    #endif // !os(iOS)
}
