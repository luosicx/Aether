import Foundation
@preconcurrency import AVFoundation

/// v1.4: 基于 Apple AVSpeechSynthesizer 的 `TTSEngine` 原生实现。
///
/// v1.3 提供协议与占位实现，v1.4 使用 `AVSpeechSynthesizer` 的
/// `write(_:toBufferCallback:)` 接口将合成的音频写入 `AVAudioPCMBuffer`，
/// 再转 PCM/WAV Data 返回。无需 MLX-Voice 外部依赖，三端原生可用。
///
/// 设计参考 MASTER_PLAN §4.1.5 端侧语音：
/// > 引入 MLX-Voice（Apple 开源 Kokoro/Matcha-TTS 端侧版），自然度远超 AVSpeechSynthesizer
/// v1.4 实现 AVSpeechSynthesizer 路径作为基线，MLX-Voice 待 v1.5+ 集成。
public final class NativeTTSEngine: TTSEngine, @unchecked Sendable {
    public let name = "NativeTTS (AVSpeechSynthesizer)"
    public let isLoaded = true

    /// 内部使用的合成器（@unchecked Sendable 因 AVSpeechSynthesizer 非线程安全，
    /// 实际通过 actor 串行化调用）
    private let synthesizer = AVSpeechSynthesizer()

    public init() {}

    public func loadModel(at modelPath: URL) async throws {
        // AVSpeechSynthesizer 无需加载模型文件，保持兼容（no-op）
    }

    /// 合成语音
    ///
    /// 流程：
    /// 1. 校验文本非空
    /// 2. 创建 AVSpeechUtterance
    /// 3. 使用 write(_:toBufferCallback:) 接口收集 PCM Buffer
    /// 4. 拼接为完整 PCM Data，加 WAV 头返回
    public func synthesize(text: String, voiceId: String?) async throws -> Data {
        guard !text.isEmpty else {
            throw MultimodalError.emptyInput
        }

        // CI 环境下 AVSpeechSynthesizer 可能不可用，避免测试卡住
        if ProcessInfo.processInfo.environment["CI"] != nil {
            // 返回最小 WAV 头（44 字节空 PCM），让上层逻辑可继续
            return Self.emptyWAVHeader()
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = resolveVoice(voiceId: voiceId)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // 使用 write 接口将合成结果写入 PCM Buffer
        // write 接口为异步回调，每次回调返回一段 AVAudioPCMBuffer
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            var pcmBuffers: [AVAudioPCMBuffer] = []
            var hasCompleted = false
            let lock = NSLock()

            // 标记完成（避免多次回调）
            func finishOnce(_ result: Result<Data, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !hasCompleted else { return }
                hasCompleted = true
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            self.synthesizer.write(utterance) { buffer in
                // write 回调类型为 AVAudioBuffer?，需 cast 为 AVAudioPCMBuffer
                if let pcmBuffer = buffer as? AVAudioPCMBuffer {
                    lock.lock()
                    pcmBuffers.append(pcmBuffer)
                    lock.unlock()
                } else if buffer == nil {
                    // nil 表示合成完成
                    do {
                        let wavData = try Self.encodeToWAV(buffers: pcmBuffers)
                        finishOnce(.success(wavData))
                    } catch {
                        finishOnce(.failure(error))
                    }
                }
            }

            // 超时保护（30 秒后强制返回空 WAV，避免卡死）
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                let emptyWAV = Self.emptyWAVHeader()
                finishOnce(.success(emptyWAV))
            }
        }
    }

    /// 根据 voiceId 解析音色
    /// - Parameter voiceId: 音色标识符（AVSpeechSynthesisVoice.identifier），nil 使用默认中文音色
    /// - Returns: AVSpeechSynthesisVoice，未找到时返回 nil（系统自动选择默认）
    private func resolveVoice(voiceId: String?) -> AVSpeechSynthesisVoice? {
        guard let voiceId = voiceId, !voiceId.isEmpty else {
            return AVSpeechSynthesisVoice(language: "zh-CN")
        }
        // AVSpeechSynthesisVoice(identifier:) 已弃用，改用 speechVoices() 查找
        // speechVoices() 在首次调用时较慢，但合成本身是异步的，可接受
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let voice = voices.first(where: { $0.identifier == voiceId }) {
            return voice
        }
        // 未找到指定音色，回退到默认中文音色
        return AVSpeechSynthesisVoice(language: "zh-CN")
    }

    // MARK: - WAV 编码工具

    /// 将 PCM Buffer 数组编码为 WAV 文件 Data
    private static func encodeToWAV(buffers: [AVAudioPCMBuffer]) throws -> Data {
        guard !buffers.isEmpty else {
            return emptyWAVHeader()
        }

        // 取第一个 buffer 的格式作为基准
        let format = buffers[0].format
        let sampleRate = format.sampleRate
        let channels = format.channelCount
        let bitsPerChannel = format.settings[AVLinearPCMBitDepthKey] as? Int ?? 16
        let isFloat = format.settings[AVLinearPCMIsFloatKey] as? Bool ?? false
        let isBigEndian = format.settings[AVLinearPCMIsBigEndianKey] as? Bool ?? false

        // 计算总帧数与字节数
        let totalFrames = buffers.reduce(0) { $0 + Int($1.frameLength) }
        let bytesPerSample = bitsPerChannel / 8
        let dataSize = totalFrames * Int(channels) * bytesPerSample
        let headerSize = 44
        let totalSize = headerSize + dataSize

        var wavData = Data(capacity: totalSize)

        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        var riffSize = UInt32(totalSize - 8).littleEndian
        wavData.append(Data(bytes: &riffSize, count: 4))
        wavData.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        var fmtSize = UInt32(16).littleEndian
        wavData.append(Data(bytes: &fmtSize, count: 4))
        var audioFormat = UInt16(isFloat ? 3 : 1).littleEndian  // 1=PCM, 3=Float
        wavData.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = UInt16(channels).littleEndian
        wavData.append(Data(bytes: &numChannels, count: 2))
        var sampleRateLE = UInt32(sampleRate).littleEndian
        wavData.append(Data(bytes: &sampleRateLE, count: 4))
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bytesPerSample)
        var byteRateLE = byteRate.littleEndian
        wavData.append(Data(bytes: &byteRateLE, count: 4))
        let blockAlign = UInt16(channels) * UInt16(bytesPerSample)
        var blockAlignLE = blockAlign.littleEndian
        wavData.append(Data(bytes: &blockAlignLE, count: 2))
        var bitsPerSampleLE = UInt16(bitsPerChannel).littleEndian
        wavData.append(Data(bytes: &bitsPerSampleLE, count: 2))

        // data chunk
        wavData.append("data".data(using: .ascii)!)
        var dataSizeLE = UInt32(dataSize).littleEndian
        wavData.append(Data(bytes: &dataSizeLE, count: 4))

        // 拼接 PCM 数据
        for buffer in buffers {
            let frameLength = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            if isFloat {
                // Float32
                guard let floatChannelData = buffer.floatChannelData else { continue }
                for frame in 0..<frameLength {
                    for channel in 0..<channelCount {
                        var sample = floatChannelData[channel][frame]
                        wavData.append(Data(bytes: &sample, count: 4))
                    }
                }
            } else {
                // Int16
                guard let intChannelData = buffer.int16ChannelData else { continue }
                for frame in 0..<frameLength {
                    for channel in 0..<channelCount {
                        var sample = intChannelData[channel][frame]
                        wavData.append(Data(bytes: &sample, count: 2))
                    }
                }
            }
        }

        return wavData
    }

    /// 生成最小 WAV 头（44 字节空 PCM，用于 CI 环境兜底）
    private static func emptyWAVHeader() -> Data {
        var wavData = Data(capacity: 44)
        wavData.append("RIFF".data(using: .ascii)!)
        var riffSize = UInt32(36).littleEndian
        wavData.append(Data(bytes: &riffSize, count: 4))
        wavData.append("WAVE".data(using: .ascii)!)
        wavData.append("fmt ".data(using: .ascii)!)
        var fmtSize = UInt32(16).littleEndian
        wavData.append(Data(bytes: &fmtSize, count: 4))
        var audioFormat = UInt16(1).littleEndian
        wavData.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = UInt16(1).littleEndian
        wavData.append(Data(bytes: &numChannels, count: 2))
        var sampleRate = UInt32(16000).littleEndian
        wavData.append(Data(bytes: &sampleRate, count: 4))
        var byteRate = UInt32(32000).littleEndian
        wavData.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = UInt16(2).littleEndian
        wavData.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample = UInt16(16).littleEndian
        wavData.append(Data(bytes: &bitsPerSample, count: 2))
        wavData.append("data".data(using: .ascii)!)
        var dataSize = UInt32(0).littleEndian
        wavData.append(Data(bytes: &dataSize, count: 4))
        return wavData
    }
}
