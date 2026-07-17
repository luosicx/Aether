import Foundation
import SQLite3

/// Task 19 阶段 1: 基于 sqlite-vec 扩展的 ANN 向量存储。
///
/// 设计要点：
/// - 使用 SQLite C API 打开数据库文件，并通过 `sqlite3_load_extension` 加载 sqlite-vec。
/// - 加载失败（iOS 沙箱限制、二进制缺失）时 `isAvailable` 为 false，所有方法降级为 no-op 或返回空结果。
/// - `query` 使用 vec0 虚拟表的 KNN 查询语法。
/// - actor 串行化保证线程安全。
///
/// 注意：sqlite-vec 二进制依赖可能在 CI 加载失败，调用方应通过 `VectorStoreFactory` 自动降级为 `BruteForceVectorStore`。
actor SQLiteVecStore: VectorStore {
    /// SQLite 数据库句柄
    private var db: OpaquePointer?
    /// sqlite-vec 是否成功加载
    private(set) var isAvailable: Bool = false
    /// 向量维度（首次 upsert 时确定，所有后续插入须匹配）
    private var dimension: Int = 0
    /// 数据库文件路径
    private let dbPath: String

    /// 创建 SQLiteVecStore 实例
    /// - Parameter dbPath: SQLite 数据库文件路径（位于 App Group 容器）
    init(dbPath: String) {
        self.dbPath = dbPath
    }

    /// 初始化：打开数据库 → 加载 sqlite-vec 扩展 → 建表
    func initialize() async throws {
        guard db == nil else { return }
        let openResult = sqlite3_open(dbPath, &db)
        guard openResult == SQLITE_OK else {
            isAvailable = false
            throw VectorStoreError.sqliteOpenFailed(Int(openResult))
        }
        // 尝试加载 sqlite-vec 扩展（系统默认查找路径）
        // 注意：iOS/macOS 沙箱内 sqlite-vec 扩展通常以静态链接或 framework 方式提供
        // CI 环境与未集成 sqlite-vec 二进制的环境会加载失败，自动降级为 BruteForceVectorStore
        // sqlite3_enable_load_extension / sqlite3_load_extension 在某些 SQLite3 模块中不可用，
        // 用条件编译跳过（macOS 系统模块不导出这些 API）
        #if canImport(SQLite3) && !os(macOS)
        sqlite3_enable_load_extension(db, 1)
        let loadResult = sqlite3_load_extension(db, "sqlitevec", nil, nil)
        if loadResult != SQLITE_OK {
            // 加载失败：iOS 沙箱限制或二进制未集成，标记不可用并关闭 db
            isAvailable = false
            sqlite3_close(db)
            db = nil
            return
        }
        sqlite3_enable_load_extension(db, 0)
        #else
        // macOS：sqlite-vec 扩展加载 API 不可用，直接标记为不可用
        // 调用方应通过 VectorStoreFactory 自动降级为 BruteForceVectorStore
        isAvailable = false
        sqlite3_close(db)
        db = nil
        return
        #endif
        isAvailable = true
        try createMetaTable()
    }

    // MARK: - VectorStore 协议实现

    func upsert(id: UUID, embedding: [Double], metadata: [String: String]) async throws {
        if db == nil { try await initialize() }
        guard isAvailable else { return }
        try upsertVector(id: id, embedding: embedding)
        try upsertMetadata(id: id, metadata: metadata)
    }

    func upsertBatch(_ records: [(id: UUID, embedding: [Double], metadata: [String: String])]) async throws {
        if db == nil { try await initialize() }
        guard isAvailable else { return }
        try execute("BEGIN TRANSACTION;")
        for record in records {
            try upsertVector(id: record.id, embedding: record.embedding)
            try upsertMetadata(id: record.id, metadata: record.metadata)
        }
        try execute("COMMIT;")
    }

    func query(_ query: [Double], limit: Int) async throws -> [VectorSearchResult] {
        if db == nil { try await initialize() }
        guard isAvailable, !query.isEmpty else { return [] }
        // vec0 虚拟表 KNN 查询：SELECT id, distance FROM vec_items WHERE embedding MATCH ? ORDER BY distance LIMIT ?
        // distance 是 L2 距离，转换为 cosine similarity 近似：sim = 1/(1+distance)
        let sql = "SELECT id, distance FROM vec_items WHERE embedding MATCH ? ORDER BY distance LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw VectorStoreError.queryFailed("prepare failed")
        }
        defer { sqlite3_finalize(stmt) }
        let blobData = blobFromVector(query)
        let blobSize = Int32(blobData.count)
        blobData.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(stmt, 1, rawBuffer.baseAddress, blobSize, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        sqlite3_bind_int64(stmt, 2, sqlite3_int64(limit))

        var results: [VectorSearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let idBytes = sqlite3_column_blob(stmt, 0)
            let idSize = sqlite3_column_bytes(stmt, 0)
            guard idSize == 16, let idBytes = idBytes else { continue }
            let uuid = uuidFromBlob(idBytes)
            let distance = sqlite3_column_double(stmt, 1)
            let similarity = 1.0 / (1.0 + distance)
            let metadata = (try? fetchMetadata(id: uuid)) ?? [:]
            results.append(VectorSearchResult(id: uuid, similarity: similarity, metadata: metadata))
        }
        return results
    }

    func delete(id: UUID) async throws {
        if db == nil { try await initialize() }
        guard isAvailable else { return }
        try execute("DELETE FROM vec_items WHERE id = ?;", uuidBlobBind: id)
        try execute("DELETE FROM vec_metadata WHERE id = ?;", uuidBlobBind: id)
    }

    func deleteAll() async throws {
        if db == nil { try await initialize() }
        guard isAvailable else { return }
        try execute("DELETE FROM vec_items;")
        try execute("DELETE FROM vec_metadata;")
    }

    func count() async throws -> Int {
        if db == nil { try await initialize() }
        guard isAvailable else { return 0 }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM vec_items;", -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    // MARK: - 内部辅助

    /// 创建元数据表
    private func createMetaTable() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS vec_metadata (
            id BLOB PRIMARY KEY,
            category TEXT,
            importance REAL,
            created_at REAL,
            metadata_json TEXT
        );
        """)
    }

    /// 根据 embedding 维度创建 vec0 虚拟表
    private func ensureVecTable(dimension dim: Int) throws {
        guard dimension != dim else { return }
        if dimension != 0 {
            try execute("DROP TABLE IF EXISTS vec_items;")
        }
        let ddl = "CREATE VIRTUAL TABLE IF NOT EXISTS vec_items USING vec0(embedding float[\(dim)]);"
        try execute(ddl)
        dimension = dim
    }

    /// 插入向量（vec0 虚拟表）
    private func upsertVector(id: UUID, embedding: [Double]) throws {
        try ensureVecTable(dimension: embedding.count)
        try execute("DELETE FROM vec_items WHERE id = ?;", uuidBlobBind: id)
        let sql = "INSERT INTO vec_items(id, embedding) VALUES (?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw VectorStoreError.upsertFailed("prepare insert failed")
        }
        defer { sqlite3_finalize(stmt) }
        var uuid = id.uuid
        let uuidSize = Int32(MemoryLayout<uuid_t>.size)
        withUnsafePointer(to: &uuid) { ptr in
            sqlite3_bind_blob(stmt, 1, ptr, uuidSize, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        let blobData = blobFromVector(embedding)
        let blobSize = Int32(blobData.count)
        blobData.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(stmt, 2, rawBuffer.baseAddress, blobSize, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw VectorStoreError.upsertFailed("insert step failed")
        }
    }

    /// 插入元数据
    private func upsertMetadata(id: UUID, metadata: [String: String]) throws {
        try execute("DELETE FROM vec_metadata WHERE id = ?;", uuidBlobBind: id)
        let json = try metadataToJSON(metadata)
        let sql = "INSERT INTO vec_metadata(id, category, importance, created_at, metadata_json) VALUES (?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw VectorStoreError.upsertFailed("prepare metadata failed")
        }
        defer { sqlite3_finalize(stmt) }
        var uuid = id.uuid
        let uuidSize = Int32(MemoryLayout<uuid_t>.size)
        withUnsafePointer(to: &uuid) { ptr in
            sqlite3_bind_blob(stmt, 1, ptr, uuidSize, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        sqlite3_bind_text(stmt, 2, metadata["category"], -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        let importance = Double(metadata["importance"] ?? "0.5") ?? 0.5
        sqlite3_bind_double(stmt, 3, importance)
        let createdAt = Double(metadata["createdAt"] ?? "0") ?? 0
        sqlite3_bind_double(stmt, 4, createdAt)
        sqlite3_bind_text(stmt, 5, json, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw VectorStoreError.upsertFailed("metadata insert step failed")
        }
    }

    /// 读取元数据
    private func fetchMetadata(id: UUID) throws -> [String: String] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT metadata_json FROM vec_metadata WHERE id = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return [:]
        }
        var uuid = id.uuid
        let uuidSize = Int32(MemoryLayout<uuid_t>.size)
        withUnsafePointer(to: &uuid) { ptr in
            sqlite3_bind_blob(stmt, 1, ptr, uuidSize, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        if sqlite3_step(stmt) == SQLITE_ROW, let cString = sqlite3_column_text(stmt, 0) {
            let jsonString = String(cString: cString)
            return try metadataFromJSON(jsonString)
        }
        return [:]
    }

    /// 执行无返回结果的 SQL
    private func execute(_ sql: String, uuidBlobBind: UUID? = nil) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw VectorStoreError.queryFailed("execute prepare failed: \(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        if let uuid = uuidBlobBind {
            var uuidVal = uuid.uuid
            let uuidSize = Int32(MemoryLayout<uuid_t>.size)
            withUnsafePointer(to: &uuidVal) { ptr in
                sqlite3_bind_blob(stmt, 1, ptr, uuidSize, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw VectorStoreError.queryFailed("execute step failed: \(sql)")
        }
    }

    /// [Double] 转 Data (Little-Endian Double 字节序)
    private func blobFromVector(_ vector: [Double]) -> Data {
        var data = Data(count: vector.count * MemoryLayout<Double>.size)
        data.withUnsafeMutableBytes { buffer in
            let doubleBuffer = buffer.bindMemory(to: Double.self)
            for (idx, value) in vector.enumerated() {
                doubleBuffer[idx] = value
            }
        }
        return data
    }

    /// blob (16 字节) 转 UUID
    private func uuidFromBlob(_ bytes: UnsafeRawPointer) -> UUID {
        let uuidPtr = bytes.assumingMemoryBound(to: uuid_t.self)
        return UUID(uuid: uuidPtr.pointee)
    }

    /// metadata 字典转 JSON 字符串
    private func metadataToJSON(_ metadata: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// JSON 字符串转 metadata 字典
    private func metadataFromJSON(_ jsonString: String) throws -> [String: String] {
        guard let data = jsonString.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }
}

/// Task 19 阶段 1: 向量存储错误类型
enum VectorStoreError: Error, LocalizedError {
    case sqliteOpenFailed(Int)
    case queryFailed(String)
    case upsertFailed(String)
    case dimensionMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .sqliteOpenFailed(let code): return "SQLite 打开失败：\(code)"
        case .queryFailed(let msg): return "向量查询失败：\(msg)"
        case .upsertFailed(let msg): return "向量插入失败：\(msg)"
        case .dimensionMismatch(let expected, let actual): return "向量维度不匹配：期望 \(expected)，实际 \(actual)"
        }
    }
}
