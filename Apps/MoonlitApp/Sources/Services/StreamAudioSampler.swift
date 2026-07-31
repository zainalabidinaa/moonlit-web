import Foundation
import Libavformat
import Libavcodec
import Libswresample
import Libavutil

struct SelectedAudioDescriptor: Equatable, Sendable {
    let languageCode: String
    let title: String?
}

struct StreamAudioSampleRequest: Sendable {
    let sourceURL: URL
    let headers: [String: String]
    let audio: SelectedAudioDescriptor
    let range: Range<Double>

    private init(
        sourceURL: URL,
        headers: [String: String],
        audio: SelectedAudioDescriptor,
        range: Range<Double>
    ) {
        self.sourceURL = sourceURL
        self.headers = headers
        self.audio = audio
        self.range = range
    }

    static func validated(
        sourceURL: URL,
        headers: [String: String],
        audio: SelectedAudioDescriptor,
        range: Range<Double>
    ) throws -> Self {
        guard isSupported(sourceURL) else {
            throw StreamAudioSampleError.unsupportedSource
        }
        guard range.lowerBound.isFinite,
              range.upperBound.isFinite,
              range.lowerBound >= 0,
              range.upperBound <= FFmpegStreamAudioSampler.openingWindowDuration,
              !range.isEmpty else {
            throw StreamAudioSampleError.invalidRange
        }
        guard headers.allSatisfy({ isValidHeaderName($0.key) && isValidHeaderValue($0.value) }) else {
            throw StreamAudioSampleError.invalidHeaders
        }

        return Self(
            sourceURL: sourceURL,
            headers: headers,
            audio: audio,
            range: range
        )
    }

    private static func isSupported(_ url: URL) -> Bool {
        if url.isFileURL {
            return !url.path.isEmpty
        }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return url.host?.isEmpty == false
    }

    private static func isValidHeaderName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let tokenPunctuation = Set("!#$%&'*+-.^_`|~".unicodeScalars.map(\.value))
        return name.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (48...57).contains(value)
                || (65...90).contains(value)
                || (97...122).contains(value)
                || tokenPunctuation.contains(value)
        }
    }

    private static func isValidHeaderValue(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            scalar.value != 0 && scalar.value != 10 && scalar.value != 13
        }
    }
}

protocol StreamAudioSampling: Sendable {
    func samples(for request: StreamAudioSampleRequest) async throws -> [Float]
}

enum StreamAudioSampleError: Error, Equatable, Sendable {
    case unsupportedSource
    case invalidRange
    case invalidHeaders
    case allocationFailed
    case inputOpenFailed(Int32)
    case streamInfoFailed(Int32)
    case audioStreamNotFound
    case decoderNotFound
    case decoderSetupFailed(Int32)
    case seekFailed(Int32)
    case readFailed(Int32)
    case decodeFailed(Int32)
    case resamplerSetupFailed(Int32)
    case resamplingFailed(Int32)
    case invalidAudioFormat
    case sampleLimitExceeded
    case timedOut
}

enum DecoderDrainAction: Equatable {
    case accepted
    case receiveThenRetry
    case alreadyDrained
}

private enum DecoderReceiveStatus: Equatable {
    case needsInput
    case endOfStream
    case rangeComplete
}

struct FFmpegStreamAudioSampler: StreamAudioSampling {
    static let outputSampleRate = 11_025
    static let openingWindowDuration: Double = 900

    private static let decodeQueue = DispatchQueue(
        label: "app.trymoonlit.stream-audio-sampler",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private static let activeDecodeContextCountLock = NSLock()
    private static var activeContexts = 0
    private static let maximumSampleCount = outputSampleRate * Int(openingWindowDuration)
    private static let maximumFrameSampleCount = 1_048_576
    // AVERROR_EOF is not imported into Swift because FFERRTAG is a nested C macro.
    // This is the exact FFERRTAG('E', 'O', 'F', ' ') expansion from libavutil/error.h.
    private static let endOfFileError = -Int32(
        UInt32(69)
            | (UInt32(79) << 8)
            | (UInt32(70) << 16)
            | (UInt32(32) << 24)
    )

    static var activeDecodeContextCount: Int {
        activeDecodeContextCountLock.lock()
        defer { activeDecodeContextCountLock.unlock() }
        return activeContexts
    }

    func samples(for request: StreamAudioSampleRequest) async throws -> [Float] {
        try Task.checkCancellation()
        let interrupt = FFmpegInterruptToken(timeout: .seconds(30))

        let decoded: [Float] = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<[Float], Error>) in
                Self.decodeQueue.async {
                    do {
                        continuation.resume(
                            returning: try Self.decode(request, interrupt: interrupt)
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            interrupt.cancel()
        }

        try Task.checkCancellation()
        return decoded
    }

    private static func decode(
        _ request: StreamAudioSampleRequest,
        interrupt: FFmpegInterruptToken
    ) throws -> [Float] {
        incrementActiveContexts()
        defer { decrementActiveContexts() }

        try throwIfInterrupted(interrupt)

        var formatContext = avformat_alloc_context()
        guard formatContext != nil else {
            throw StreamAudioSampleError.allocationFailed
        }
        var inputWasOpened = false
        formatContext?.pointee.interrupt_callback = AVIOInterruptCB(
            callback: ffmpegInterruptCallback,
            opaque: Unmanaged.passUnretained(interrupt).toOpaque()
        )
        defer {
            if inputWasOpened {
                avformat_close_input(&formatContext)
            } else if let formatContext {
                avformat_free_context(formatContext)
            }
        }

        var inputOptions: OpaquePointer?
        defer {
            av_dict_free(&inputOptions)
        }
        if !request.headers.isEmpty {
            let headerLines = request.headers
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)\r\n" }
                .joined()
            let headerResult = headerLines.withCString {
                av_dict_set(&inputOptions, "headers", $0, 0)
            }
            guard headerResult >= 0 else {
                throw StreamAudioSampleError.invalidHeaders
            }
        }
        let timeoutResult = av_dict_set_int(
            &inputOptions,
            "rw_timeout",
            30_000_000,
            0
        )
        guard timeoutResult >= 0 else {
            throw StreamAudioSampleError.allocationFailed
        }

        let inputLocation = request.sourceURL.isFileURL
            ? request.sourceURL.path
            : request.sourceURL.absoluteString
        let openResult = inputLocation.withCString {
            avformat_open_input(&formatContext, $0, nil, &inputOptions)
        }
        guard openResult >= 0 else {
            try throwIfInterrupted(interrupt)
            throw StreamAudioSampleError.inputOpenFailed(openResult)
        }
        inputWasOpened = true
        guard let formatContext else {
            throw StreamAudioSampleError.inputOpenFailed(openResult)
        }

        let streamInfoResult = avformat_find_stream_info(formatContext, nil)
        guard streamInfoResult >= 0 else {
            try throwIfInterrupted(interrupt)
            throw StreamAudioSampleError.streamInfoFailed(streamInfoResult)
        }

        guard let streamIndex = configureSelectedAudioStream(
            in: formatContext,
            descriptor: request.audio
        ),
        let stream = formatContext.pointee.streams[Int(streamIndex)] else {
            throw StreamAudioSampleError.audioStreamNotFound
        }

        guard let codecParameters = stream.pointee.codecpar,
              let decoder = avcodec_find_decoder(codecParameters.pointee.codec_id) else {
            throw StreamAudioSampleError.decoderNotFound
        }
        var codecContext = avcodec_alloc_context3(decoder)
        guard codecContext != nil else {
            throw StreamAudioSampleError.allocationFailed
        }
        defer {
            avcodec_free_context(&codecContext)
        }
        guard let codecContext else {
            throw StreamAudioSampleError.allocationFailed
        }

        let parameterResult = avcodec_parameters_to_context(codecContext, codecParameters)
        guard parameterResult >= 0 else {
            throw StreamAudioSampleError.decoderSetupFailed(parameterResult)
        }
        guard stream.pointee.time_base.num > 0,
              stream.pointee.time_base.den > 0 else {
            throw StreamAudioSampleError.invalidAudioFormat
        }
        let codecOpenResult = avcodec_open2(codecContext, decoder, nil)
        guard codecOpenResult >= 0 else {
            throw StreamAudioSampleError.decoderSetupFailed(codecOpenResult)
        }

        let timelineOrigin = timelineOriginTimestamp(
            stream: stream,
            formatContext: formatContext
        )
        let requestedStartOffset = timestamp(
            for: request.range.lowerBound,
            timeBase: stream.pointee.time_base
        )
        let (startTimestamp, timestampOverflow) = timelineOrigin.addingReportingOverflow(
            requestedStartOffset
        )
        guard !timestampOverflow else {
            throw StreamAudioSampleError.invalidAudioFormat
        }
        let seekResult = avformat_seek_file(
            formatContext,
            streamIndex,
            Int64.min,
            startTimestamp,
            startTimestamp,
            AVSEEK_FLAG_BACKWARD
        )
        guard seekResult >= 0 else {
            try throwIfInterrupted(interrupt)
            throw StreamAudioSampleError.seekFailed(seekResult)
        }
        avcodec_flush_buffers(codecContext)

        var inputLayout = AVChannelLayout()
        let layoutResult = av_channel_layout_copy(
            &inputLayout,
            &codecContext.pointee.ch_layout
        )
        guard layoutResult >= 0 else {
            throw StreamAudioSampleError.invalidAudioFormat
        }
        defer {
            av_channel_layout_uninit(&inputLayout)
        }
        guard inputLayout.nb_channels > 0,
              codecContext.pointee.sample_rate > 0,
              codecContext.pointee.sample_fmt != AV_SAMPLE_FMT_NONE else {
            throw StreamAudioSampleError.invalidAudioFormat
        }

        var outputLayout = AVChannelLayout()
        av_channel_layout_default(&outputLayout, 1)
        defer {
            av_channel_layout_uninit(&outputLayout)
        }

        var resampler: OpaquePointer?
        let resamplerResult = swr_alloc_set_opts2(
            &resampler,
            &outputLayout,
            AV_SAMPLE_FMT_FLT,
            Int32(outputSampleRate),
            &inputLayout,
            codecContext.pointee.sample_fmt,
            codecContext.pointee.sample_rate,
            0,
            nil
        )
        guard resamplerResult >= 0, resampler != nil else {
            throw StreamAudioSampleError.resamplerSetupFailed(resamplerResult)
        }
        defer {
            swr_free(&resampler)
        }
        guard let resampler else {
            throw StreamAudioSampleError.resamplerSetupFailed(resamplerResult)
        }
        let resamplerInitResult = swr_init(resampler)
        guard resamplerInitResult >= 0 else {
            throw StreamAudioSampleError.resamplerSetupFailed(resamplerInitResult)
        }

        var packet = av_packet_alloc()
        guard packet != nil else {
            throw StreamAudioSampleError.allocationFailed
        }
        defer {
            av_packet_free(&packet)
        }
        var frame = av_frame_alloc()
        guard frame != nil else {
            throw StreamAudioSampleError.allocationFailed
        }
        defer {
            av_frame_free(&frame)
        }
        guard let packet, let frame else {
            throw StreamAudioSampleError.allocationFailed
        }

        let duration = request.range.upperBound - request.range.lowerBound
        let requestedSampleCount = Int(ceil(duration * Double(outputSampleRate)))
        guard requestedSampleCount > 0,
              requestedSampleCount <= maximumSampleCount else {
            throw StreamAudioSampleError.sampleLimitExceeded
        }

        var samples: [Float] = []
        samples.reserveCapacity(requestedSampleCount)
        var reachedRangeBoundary = false

        while !reachedRangeBoundary {
            try throwIfInterrupted(interrupt)
            let readResult = av_read_frame(formatContext, packet)
            if readResult == endOfFileError {
                break
            }
            guard readResult >= 0 else {
                try throwIfInterrupted(interrupt)
                throw StreamAudioSampleError.readFailed(readResult)
            }

            guard packet.pointee.stream_index == streamIndex else {
                av_packet_unref(packet)
                continue
            }

            let receiveStatus = try sendPacketAndReceiveFrames(
                packet: packet,
                codecContext: codecContext,
                frame: frame,
                resampler: resampler,
                streamTimeBase: stream.pointee.time_base,
                timelineOrigin: timelineOrigin,
                request: request,
                requestedSampleCount: requestedSampleCount,
                samples: &samples
            )
            av_packet_unref(packet)
            if receiveStatus == .rangeComplete {
                reachedRangeBoundary = true
                break
            }
            if receiveStatus == .endOfStream {
                break
            }
        }

        try drainDecoder(
            codecContext: codecContext,
            frame: frame,
            resampler: resampler,
            streamTimeBase: stream.pointee.time_base,
            timelineOrigin: timelineOrigin,
            request: request,
            requestedSampleCount: requestedSampleCount,
            collectRemainingFrames: !reachedRangeBoundary,
            samples: &samples
        )
        try flushResampler(
            resampler,
            inputSampleRate: codecContext.pointee.sample_rate,
            requestedSampleCount: requestedSampleCount,
            samples: &samples
        )

        try throwIfInterrupted(interrupt)
        return samples
    }

    private static func sendPacketAndReceiveFrames(
        packet: UnsafePointer<AVPacket>,
        codecContext: UnsafeMutablePointer<AVCodecContext>,
        frame: UnsafeMutablePointer<AVFrame>,
        resampler: OpaquePointer,
        streamTimeBase: AVRational,
        timelineOrigin: Int64,
        request: StreamAudioSampleRequest,
        requestedSampleCount: Int,
        samples: inout [Float]
    ) throws -> DecoderReceiveStatus {
        while true {
            let sendResult = avcodec_send_packet(codecContext, packet)
            if sendResult == -EAGAIN {
                let receiveStatus = try receiveFrames(
                    codecContext: codecContext,
                    frame: frame,
                    resampler: resampler,
                    streamTimeBase: streamTimeBase,
                    timelineOrigin: timelineOrigin,
                    request: request,
                    requestedSampleCount: requestedSampleCount,
                    collectingSamples: true,
                    samples: &samples
                )
                if receiveStatus == .needsInput {
                    continue
                }
                return receiveStatus
            }
            guard sendResult >= 0 else {
                throw StreamAudioSampleError.decodeFailed(sendResult)
            }
            return try receiveFrames(
                codecContext: codecContext,
                frame: frame,
                resampler: resampler,
                streamTimeBase: streamTimeBase,
                timelineOrigin: timelineOrigin,
                request: request,
                requestedSampleCount: requestedSampleCount,
                collectingSamples: true,
                samples: &samples
            )
        }
    }

    private static func receiveFrames(
        codecContext: UnsafeMutablePointer<AVCodecContext>,
        frame: UnsafeMutablePointer<AVFrame>,
        resampler: OpaquePointer,
        streamTimeBase: AVRational,
        timelineOrigin: Int64,
        request: StreamAudioSampleRequest,
        requestedSampleCount: Int,
        collectingSamples: Bool,
        samples: inout [Float]
    ) throws -> DecoderReceiveStatus {
        while true {
            let receiveResult = avcodec_receive_frame(codecContext, frame)
            if receiveResult == -EAGAIN {
                return .needsInput
            }
            if receiveResult == endOfFileError {
                return .endOfStream
            }
            guard receiveResult >= 0 else {
                throw StreamAudioSampleError.decodeFailed(receiveResult)
            }

            var shouldStop = !collectingSamples
            do {
                if collectingSamples {
                    shouldStop = try append(
                        frame: frame,
                        resampler: resampler,
                        inputSampleRate: codecContext.pointee.sample_rate,
                        expectedSampleFormat: codecContext.pointee.sample_fmt,
                        expectedChannelLayout: &codecContext.pointee.ch_layout,
                        streamTimeBase: streamTimeBase,
                        timelineOrigin: timelineOrigin,
                        request: request,
                        requestedSampleCount: requestedSampleCount,
                        samples: &samples
                    )
                }
            } catch {
                av_frame_unref(frame)
                throw error
            }
            av_frame_unref(frame)

            if shouldStop {
                return .rangeComplete
            }
        }
    }

    private static func drainDecoder(
        codecContext: UnsafeMutablePointer<AVCodecContext>,
        frame: UnsafeMutablePointer<AVFrame>,
        resampler: OpaquePointer,
        streamTimeBase: AVRational,
        timelineOrigin: Int64,
        request: StreamAudioSampleRequest,
        requestedSampleCount: Int,
        collectRemainingFrames: Bool,
        samples: inout [Float]
    ) throws {
        var shouldCollect = collectRemainingFrames

        sendFlush: while true {
            switch try decoderDrainAction(
                forSendResult: avcodec_send_packet(codecContext, nil)
            ) {
            case .accepted:
                break sendFlush
            case .alreadyDrained:
                return
            case .receiveThenRetry:
                let receiveStatus = try receiveFrames(
                    codecContext: codecContext,
                    frame: frame,
                    resampler: resampler,
                    streamTimeBase: streamTimeBase,
                    timelineOrigin: timelineOrigin,
                    request: request,
                    requestedSampleCount: requestedSampleCount,
                    collectingSamples: shouldCollect,
                    samples: &samples
                )
                switch receiveStatus {
                case .needsInput:
                    continue sendFlush
                case .endOfStream:
                    return
                case .rangeComplete:
                    shouldCollect = false
                }
            }
        }

        while true {
            switch try receiveFrames(
                codecContext: codecContext,
                frame: frame,
                resampler: resampler,
                streamTimeBase: streamTimeBase,
                timelineOrigin: timelineOrigin,
                request: request,
                requestedSampleCount: requestedSampleCount,
                collectingSamples: shouldCollect,
                samples: &samples
            ) {
            case .endOfStream:
                return
            case .rangeComplete:
                shouldCollect = false
            case .needsInput:
                // After an accepted flush packet, FFmpeg promises EOF, not EAGAIN.
                throw StreamAudioSampleError.decodeFailed(-EAGAIN)
            }
        }
    }

    static func decoderDrainAction(
        forSendResult result: Int32
    ) throws -> DecoderDrainAction {
        if result >= 0 {
            return .accepted
        }
        if result == -EAGAIN {
            return .receiveThenRetry
        }
        if result == endOfFileError {
            return .alreadyDrained
        }
        throw StreamAudioSampleError.decodeFailed(result)
    }

    private static func append(
        frame: UnsafeMutablePointer<AVFrame>,
        resampler: OpaquePointer,
        inputSampleRate: Int32,
        expectedSampleFormat: AVSampleFormat,
        expectedChannelLayout: UnsafePointer<AVChannelLayout>,
        streamTimeBase: AVRational,
        timelineOrigin: Int64,
        request: StreamAudioSampleRequest,
        requestedSampleCount: Int,
        samples: inout [Float]
    ) throws -> Bool {
        let inputSampleCount = Int(frame.pointee.nb_samples)
        guard inputSampleCount >= 0,
              inputSampleCount <= maximumFrameSampleCount,
              inputSampleRate > 0 else {
            throw StreamAudioSampleError.invalidAudioFormat
        }

        var frameStart: Double?
        if frame.pointee.best_effort_timestamp != Int64.min {
            let (openingTimestamp, overflow) = frame.pointee.best_effort_timestamp
                .subtractingReportingOverflow(timelineOrigin)
            guard !overflow else {
                throw StreamAudioSampleError.invalidAudioFormat
            }
            frameStart = seconds(
                for: openingTimestamp,
                timeBase: streamTimeBase
            )
            if frameStart! >= request.range.upperBound {
                return true
            }
        }

        let delay = swr_get_delay(resampler, Int64(inputSampleRate))
        let capacity = Int(
            ceil(
                Double(delay + Int64(inputSampleCount))
                    * Double(outputSampleRate)
                    / Double(inputSampleRate)
            )
        ) + 32
        let remaining = requestedSampleCount - samples.count
        let outputCapacity = min(max(capacity, 1), remaining)
        var converted = [Float](repeating: 0, count: outputCapacity)

        let convertedCount: Int32 = try converted.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                throw StreamAudioSampleError.allocationFailed
            }
            var output: UnsafeMutablePointer<UInt8>? = baseAddress
                .assumingMemoryBound(to: UInt8.self)
            return try withUnsafePointer(to: &output) { outputPlanes in
                try withValidatedAudioInputPlanes(
                    frame: frame,
                    expectedSampleFormat: expectedSampleFormat,
                    expectedSampleRate: inputSampleRate,
                    expectedChannelLayout: expectedChannelLayout
                ) {
                    swr_convert(
                        resampler,
                        outputPlanes,
                        Int32(outputCapacity),
                        $0.baseAddress,
                        frame.pointee.nb_samples
                    )
                }
            }
        }
        guard convertedCount >= 0 else {
            throw StreamAudioSampleError.resamplingFailed(convertedCount)
        }

        var firstSample = 0
        if let frameStart, frameStart < request.range.lowerBound {
            firstSample = min(
                Int(ceil(
                    (request.range.lowerBound - frameStart)
                        * Double(outputSampleRate)
                )),
                Int(convertedCount)
            )
        }
        if firstSample < convertedCount {
            samples.append(contentsOf: converted[firstSample..<Int(convertedCount)])
        }
        return samples.count >= requestedSampleCount
    }

    static func withValidatedAudioInputPlanes<Result>(
        frame: UnsafeMutablePointer<AVFrame>,
        expectedSampleFormat: AVSampleFormat,
        expectedSampleRate: Int32,
        expectedChannelLayout: UnsafePointer<AVChannelLayout>,
        _ body: (UnsafeBufferPointer<UnsafePointer<UInt8>?>) throws -> Result
    ) throws -> Result {
        guard frame.pointee.format == expectedSampleFormat.rawValue,
              frame.pointee.sample_rate == expectedSampleRate,
              av_get_bytes_per_sample(expectedSampleFormat) > 0,
              av_channel_layout_check(&frame.pointee.ch_layout) == 1,
              av_channel_layout_compare(
                &frame.pointee.ch_layout,
                expectedChannelLayout
              ) == 0,
              let extendedData = frame.pointee.extended_data else {
            throw StreamAudioSampleError.invalidAudioFormat
        }

        let channelCount = Int(frame.pointee.ch_layout.nb_channels)
        let planeCount = av_sample_fmt_is_planar(expectedSampleFormat) == 0
            ? 1
            : channelCount
        let inputPlanes: [UnsafePointer<UInt8>?] = (0..<planeCount).map {
            extendedData[$0].map { UnsafePointer($0) }
        }
        guard inputPlanes.allSatisfy({ $0 != nil }) else {
            throw StreamAudioSampleError.invalidAudioFormat
        }
        return try inputPlanes.withUnsafeBufferPointer(body)
    }

    private static func flushResampler(
        _ resampler: OpaquePointer,
        inputSampleRate: Int32,
        requestedSampleCount: Int,
        samples: inout [Float]
    ) throws {
        while samples.count < requestedSampleCount {
            let remaining = requestedSampleCount - samples.count
            let delayed = swr_get_delay(resampler, Int64(inputSampleRate))
            if delayed <= 0 {
                return
            }
            let capacity = min(
                remaining,
                max(
                    Int(ceil(
                        Double(delayed)
                            * Double(outputSampleRate)
                            / Double(inputSampleRate)
                    )) + 32,
                    1
                )
            )
            var converted = [Float](repeating: 0, count: capacity)
            let convertedCount = converted.withUnsafeMutableBytes { bytes -> Int32 in
                guard let baseAddress = bytes.baseAddress else { return 0 }
                var output: UnsafeMutablePointer<UInt8>? = baseAddress
                    .assumingMemoryBound(to: UInt8.self)
                return withUnsafePointer(to: &output) {
                    swr_convert(resampler, $0, Int32(capacity), nil, 0)
                }
            }
            guard convertedCount >= 0 else {
                throw StreamAudioSampleError.resamplingFailed(convertedCount)
            }
            if convertedCount == 0 {
                return
            }
            samples.append(contentsOf: converted[..<Int(convertedCount)])
        }
    }

    static func configureSelectedAudioStream(
        in formatContext: UnsafeMutablePointer<AVFormatContext>,
        descriptor: SelectedAudioDescriptor
    ) -> Int32? {
        guard let selectedIndex = selectedAudioStreamIndex(
            in: formatContext,
            descriptor: descriptor
        ) else {
            return nil
        }

        for index in 0..<Int(formatContext.pointee.nb_streams) {
            formatContext.pointee.streams[index]?.pointee.discard =
                Int32(index) == selectedIndex ? AVDISCARD_DEFAULT : AVDISCARD_ALL
        }
        return selectedIndex
    }

    private static func selectedAudioStreamIndex(
        in formatContext: UnsafeMutablePointer<AVFormatContext>,
        descriptor: SelectedAudioDescriptor
    ) -> Int32? {
        let requestedLanguage = PlayerTrackGrouping.normalizedLanguageCode(
            descriptor.languageCode
        )
        let requestedTitle = normalizedTitle(descriptor.title)
        var languageAndTitleMatch: Int32?
        var languageMatch: Int32?
        var defaultStream: Int32?

        for index in 0..<Int(formatContext.pointee.nb_streams) {
            guard let stream = formatContext.pointee.streams[index],
                  stream.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_AUDIO else {
                continue
            }
            let streamIndex = Int32(index)
            let language = metadataValue("language", in: stream.pointee.metadata)
                .map(PlayerTrackGrouping.normalizedLanguageCode) ?? "und"
            let title = normalizedTitle(metadataValue("title", in: stream.pointee.metadata))

            if stream.pointee.disposition & AV_DISPOSITION_DEFAULT != 0,
               defaultStream == nil {
                defaultStream = streamIndex
            }
            if language == requestedLanguage, languageMatch == nil {
                languageMatch = streamIndex
            }
            if language == requestedLanguage,
               (requestedTitle == nil || title == requestedTitle),
               languageAndTitleMatch == nil {
                languageAndTitleMatch = streamIndex
            }
        }

        if let languageAndTitleMatch {
            return languageAndTitleMatch
        }
        if let languageMatch {
            return languageMatch
        }
        if let defaultStream {
            return defaultStream
        }

        let bestStream = av_find_best_stream(
            formatContext,
            AVMEDIA_TYPE_AUDIO,
            -1,
            -1,
            nil,
            0
        )
        return bestStream >= 0 ? bestStream : nil
    }

    private static func metadataValue(
        _ key: String,
        in metadata: OpaquePointer?
    ) -> String? {
        guard let entry = key.withCString({
            av_dict_get(metadata, $0, nil, 0)
        }),
        let value = entry.pointee.value else {
            return nil
        }
        return String(cString: value)
    }

    private static func normalizedTitle(_ title: String?) -> String? {
        guard let normalized = title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
              !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

    private static func timestamp(
        for seconds: Double,
        timeBase: AVRational
    ) -> Int64 {
        let ticksPerSecond = Double(timeBase.den) / Double(timeBase.num)
        return Int64((seconds * ticksPerSecond).rounded(.towardZero))
    }

    private static func timelineOriginTimestamp(
        stream: UnsafeMutablePointer<AVStream>,
        formatContext: UnsafeMutablePointer<AVFormatContext>
    ) -> Int64 {
        if stream.pointee.start_time != Int64.min {
            return stream.pointee.start_time
        }
        guard formatContext.pointee.start_time != Int64.min else {
            // Raw elementary streams may have no declared timeline origin.
            return 0
        }

        var microseconds = AVRational()
        microseconds.num = 1
        microseconds.den = 1_000_000
        return av_rescale_q(
            formatContext.pointee.start_time,
            microseconds,
            stream.pointee.time_base
        )
    }

    private static func seconds(
        for timestamp: Int64,
        timeBase: AVRational
    ) -> Double {
        Double(timestamp) * Double(timeBase.num) / Double(timeBase.den)
    }

    private static func throwIfInterrupted(
        _ interrupt: FFmpegInterruptToken
    ) throws {
        switch interrupt.reason {
        case .none:
            return
        case .cancelled:
            throw CancellationError()
        case .timedOut:
            throw StreamAudioSampleError.timedOut
        }
    }

    private static func incrementActiveContexts() {
        activeDecodeContextCountLock.lock()
        activeContexts += 1
        activeDecodeContextCountLock.unlock()
    }

    private static func decrementActiveContexts() {
        activeDecodeContextCountLock.lock()
        activeContexts -= 1
        activeDecodeContextCountLock.unlock()
    }
}

private enum FFmpegInterruptReason {
    case none
    case cancelled
    case timedOut
}

private final class FFmpegInterruptToken: @unchecked Sendable {
    private let lock = NSLock()
    private let deadline: ContinuousClock.Instant
    private var storedReason: FFmpegInterruptReason = .none

    init(timeout: Duration) {
        deadline = ContinuousClock.now + timeout
    }

    var reason: FFmpegInterruptReason {
        lock.lock()
        defer { lock.unlock() }
        if storedReason == .none, ContinuousClock.now >= deadline {
            storedReason = .timedOut
        }
        return storedReason
    }

    func cancel() {
        lock.lock()
        storedReason = .cancelled
        lock.unlock()
    }
}

private let ffmpegInterruptCallback: @convention(c) (UnsafeMutableRawPointer?) -> Int32 = {
    opaque in
    guard let opaque else { return 0 }
    let token = Unmanaged<FFmpegInterruptToken>.fromOpaque(opaque).takeUnretainedValue()
    return token.reason == .none ? 0 : 1
}
