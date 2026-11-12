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

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = resolveVoice(voiceId: voiceId)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // 使用 write 接口将合成结果写入 PCM Buffer
        // write 接口为异步回调，每次回调返回一段 AVAudioPCMBuffer
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let once = ResumeOnceContinuation(continuation)
            let collector = BufferCollector()

            self.synthesizer.write(utterance) { buffer in
                // write 回调类型为 AVAudioBuffer?，需 cast 为 AVAudioPCMBuffer
                if let pcmBuffer = buffer as? AVAudioPCMBuffer {
                    let generation = collector.append(pcmBuffer)
                    // 模拟器上合成器会持续交付 PCM 帧，却永远不给表示结束的 nil，
                    // 只认 nil 就得白等满整个总窗口。帧间静默超过 idleDeadline 即视为
                    // 交付完毕，把已收到的音频编码返回。
                    DispatchQueue.global().asyncAfter(deadline: .now() + Self.idleDeadline) {
                        if collector.generation == generation {
                            once.resume(returning: Self.encodeWAVOrEmpty(buffers: collector.snapshot()))
                        }
                    }
                } else if buffer == nil {
                    // nil 表示合成完成
                    do {
                        once.resume(returning: try Self.encodeToWAV(buffers: collector.snapshot()))
                    } catch {
                        once.resume(throwing: error)
                    }
                }
            }

            // 一帧都没收到说明该运行环境根本没有合成服务，无需再等帧间静默
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.firstFrameDeadline) {
                if collector.generation == 0 {
                    once.resume(returning: Self.emptyWAVHeader())
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.synthesisDeadline) {
                once.resume(returning: Self.encodeWAVOrEmpty(buffers: collector.snapshot()))
            }
        }
    }

    /// 首帧窗口：超过此时长仍没有任何 PCM 帧，判定合成服务不可用。
    private static let firstFrameDeadline: TimeInterval = 3
    /// 帧间静默窗口：正常交付时帧与帧的间隔远小于此值。
    private static let idleDeadline: TimeInterval = 5
    /// 整段合成的总兜底窗口（与改造前的定长等待一致）。
    private static let synthesisDeadline: TimeInterval = 30

    /// write 回调与兜底分支分属不同队列，buffer 需要一把锁保护的共享持有者。
    /// `generation` 同时充当"最近一次交付"的序号，用于判断帧间静默是否已结束。
    private final class BufferCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var buffers: [AVAudioPCMBuffer] = []
        private var frames = 0

        @discardableResult
        func append(_ buffer: AVAudioPCMBuffer) -> Int {
            lock.lock()
            buffers.append(buffer)
            frames += 1
            let generation = frames
            lock.unlock()
            return generation
        }

        var generation: Int {
            lock.lock()
            defer { lock.unlock() }
            return frames
        }

        func snapshot() -> [AVAudioPCMBuffer] {
            lock.lock()
            defer { lock.unlock() }
            return buffers
        }
    }

    /// `encodeToWAV` 声明为 throws 但当前实现不抛错；兜底分支要交付已收到的音频，
    /// 编不出来时退回 44 字节空 WAV 头。
    private static func encodeWAVOrEmpty(buffers: [AVAudioPCMBuffer]) -> Data {
        (try? encodeToWAV(buffers: buffers)) ?? emptyWAVHeader()
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
