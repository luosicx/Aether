import XCTest
@testable import Aether

/// v1.3: MultimodalError 错误类型测试
final class MultimodalErrorTests: XCTestCase {

    // MARK: - Equatable 判等

    func testEngineNotLoadedEquality() {
        XCTAssertEqual(MultimodalError.engineNotLoaded, MultimodalError.engineNotLoaded)
    }

    func testEmptyInputEquality() {
        XCTAssertEqual(MultimodalError.emptyInput, MultimodalError.emptyInput)
    }

    func testUnsupportedImageFormatEquality() {
        XCTAssertEqual(MultimodalError.unsupportedImageFormat, MultimodalError.unsupportedImageFormat)
    }

    func testUnsupportedAudioFormatEquality() {
        XCTAssertEqual(MultimodalError.unsupportedAudioFormat, MultimodalError.unsupportedAudioFormat)
    }

    func testUnsupportedSampleRateEquality() {
        XCTAssertEqual(
            MultimodalError.unsupportedSampleRate(actual: 44100),
            MultimodalError.unsupportedSampleRate(actual: 44100)
        )
        XCTAssertNotEqual(
            MultimodalError.unsupportedSampleRate(actual: 44100),
            MultimodalError.unsupportedSampleRate(actual: 48000)
        )
    }

    func testAudioTooShortEquality() {
        XCTAssertEqual(
            MultimodalError.audioTooShort(actualSeconds: 3.0, requiredSeconds: 5.0),
            MultimodalError.audioTooShort(actualSeconds: 3.0, requiredSeconds: 5.0)
        )
        XCTAssertNotEqual(
            MultimodalError.audioTooShort(actualSeconds: 3.0, requiredSeconds: 5.0),
            MultimodalError.audioTooShort(actualSeconds: 4.0, requiredSeconds: 5.0)
        )
    }

    func testMemoryBudgetExceededEquality() {
        XCTAssertEqual(
            MultimodalError.memoryBudgetExceeded(requestedMB: 2000, availableMB: 1000),
            MultimodalError.memoryBudgetExceeded(requestedMB: 2000, availableMB: 1000)
        )
    }

    func testDeviceCapabilityInsufficientEquality() {
        XCTAssertEqual(
            MultimodalError.deviceCapabilityInsufficient(required: "ultra", actual: "high"),
            MultimodalError.deviceCapabilityInsufficient(required: "ultra", actual: "high")
        )
    }

    func testVLMInferenceFailedEquality() {
        XCTAssertEqual(
            MultimodalError.vlmInferenceFailed(message: "timeout"),
            MultimodalError.vlmInferenceFailed(message: "timeout")
        )
        XCTAssertNotEqual(
            MultimodalError.vlmInferenceFailed(message: "timeout"),
            MultimodalError.vlmInferenceFailed(message: "oom")
        )
    }

    func testDifferentCasesNotEqual() {
        XCTAssertNotEqual(MultimodalError.engineNotLoaded, MultimodalError.emptyInput)
        XCTAssertNotEqual(MultimodalError.platformUnsupported, MultimodalError.emptyInput)
    }

    // MARK: - errorDescription

    func testErrorDescriptionNonEmpty() {
        let errors: [MultimodalError] = [
            .engineNotLoaded,
            .emptyInput,
            .unsupportedImageFormat,
            .unsupportedAudioFormat,
            .unsupportedSampleRate(actual: 44100),
            .audioTooShort(actualSeconds: 3.0, requiredSeconds: 5.0),
            .memoryBudgetExceeded(requestedMB: 2000, availableMB: 1000),
            .deviceCapabilityInsufficient(required: "ultra", actual: "high"),
            .vlmInferenceFailed(message: "fail"),
            .asrRecognitionFailed(message: "fail"),
            .ttsSynthesisFailed(message: "fail"),
            .voiceCloneFailed(message: "fail"),
            .imageGenerationFailed(message: "fail"),
            .ocrFailed(message: "fail"),
            .modelDownloadFailed(message: "fail"),
            .platformUnsupported
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "errorDescription 应非 nil: \(error)")
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "errorDescription 应非空: \(error)")
        }
    }

    // MARK: - diagnosticDescription

    func testDiagnosticDescriptionNonEmpty() {
        let errors: [MultimodalError] = [
            .engineNotLoaded,
            .emptyInput,
            .unsupportedImageFormat,
            .unsupportedAudioFormat,
            .unsupportedSampleRate(actual: 44100),
            .audioTooShort(actualSeconds: 3.0, requiredSeconds: 5.0),
            .memoryBudgetExceeded(requestedMB: 2000, availableMB: 1000),
            .deviceCapabilityInsufficient(required: "ultra", actual: "high"),
            .vlmInferenceFailed(message: "fail"),
            .platformUnsupported
        ]
        for error in errors {
            XCTAssertFalse(error.diagnosticDescription.isEmpty, "diagnosticDescription 应非空: \(error)")
            XCTAssertTrue(error.diagnosticDescription.hasPrefix("MultimodalError."), "diagnosticDescription 应以 MultimodalError. 开头: \(error)")
        }
    }

    // MARK: - LocalizedError 一致性

    func testLocalizedErrorConformance() {
        let error = MultimodalError.engineNotLoaded
        XCTAssertEqual(error.errorDescription, error.errorDescription)
        XCTAssertNotNil(error.errorDescription)
    }
}
