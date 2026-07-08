import XCTest
@testable import AIBuilder

/// TTSConfig 单元测试:验证默认值、UserDefaults 往返持久化、损坏数据回退默认值。
final class TTSConfigTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 清理可能残留的 UserDefaults 数据
        UserDefaults.standard.removeObject(forKey: TTSConfig.userDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: TTSConfig.userDefaultsKey)
        super.tearDown()
    }

    // MARK: - 默认值

    func testDefaultValueHasExpectedFields() {
        let def = TTSConfig.defaultValue
        XCTAssertEqual(def.voiceIdentifier, "")
        XCTAssertEqual(def.rate, 0.5)
        XCTAssertEqual(def.pitchMultiplier, 1.0)
        XCTAssertEqual(def.volume, 1.0)
    }

    // MARK: - load 往返

    func testLoadReturnsDefaultWhenEmpty() {
        UserDefaults.standard.removeObject(forKey: TTSConfig.userDefaultsKey)
        let loaded = TTSConfig.load()
        XCTAssertEqual(loaded, .defaultValue)
    }

    func testSaveThenLoadRoundTrip() {
        var config = TTSConfig.defaultValue
        config.voiceIdentifier = "com.apple.voice.compact.zh-CN.Tingting"
        config.rate = 0.7
        config.pitchMultiplier = 1.5
        config.volume = 0.8
        config.save()

        let loaded = TTSConfig.load()
        XCTAssertEqual(loaded.voiceIdentifier, "com.apple.voice.compact.zh-CN.Tingting")
        XCTAssertEqual(loaded.rate, 0.7, accuracy: 0.0001)
        XCTAssertEqual(loaded.pitchMultiplier, 1.5, accuracy: 0.0001)
        XCTAssertEqual(loaded.volume, 0.8, accuracy: 0.0001)
    }

    // MARK: - 损坏数据回退

    func testLoadFallsBackOnCorruptData() {
        // 写入非 JSON 数据,load 应回退默认值,不抛错
        UserDefaults.standard.set("not a valid json".data(using: .utf8)!, forKey: TTSConfig.userDefaultsKey)
        let loaded = TTSConfig.load()
        XCTAssertEqual(loaded, .defaultValue)
    }

    func testLoadFallsBackOnNonObjectData() {
        // 写入非 Data 类型(字符串),load 应回退默认值
        UserDefaults.standard.set("garbage", forKey: TTSConfig.userDefaultsKey)
        let loaded = TTSConfig.load()
        XCTAssertEqual(loaded, .defaultValue)
    }

    // MARK: - Equatable

    func testEquatable() {
        let a = TTSConfig(voiceIdentifier: "id1", rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)
        let b = TTSConfig(voiceIdentifier: "id1", rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)
        let c = TTSConfig(voiceIdentifier: "id2", rate: 0.5, pitchMultiplier: 1.0, volume: 1.0)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
