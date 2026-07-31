import XCTest
import Darwin
import Libavformat
import Libavcodec
import Libavutil
@testable import MoonlitApp

final class StreamAudioSamplerTests: XCTestCase {
    private var fixtureURL: URL {
        fixtureURL(named: "fingerprint-reference", extension: "wav")
    }

    private var multistreamFixtureURL: URL {
        fixtureURL(named: "fingerprint-multistream", extension: "mkv")
    }

    private var nonzeroOriginFixtureURL: URL {
        fixtureURL(named: "fingerprint-nonzero-origin", extension: "ts")
    }

    private func fixtureURL(named name: String, extension fileExtension: String) -> URL {
        let bundle = Bundle(for: StreamAudioSamplerTests.self)
        return bundle.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Fixtures"
        ) ?? bundle.url(
            forResource: name,
            withExtension: fileExtension
        )!
    }

    func testRequestRejectsRangesOutsideOpeningWindow() {
        XCTAssertThrowsError(try StreamAudioSampleRequest.validated(
            sourceURL: fixtureURL,
            headers: [:],
            audio: .init(languageCode: "en", title: nil),
            range: 0..<901
        ))
    }

    func testRequestRejectsEmptyRangesAndUnsafeHeaderLines() {
        XCTAssertThrowsError(try StreamAudioSampleRequest.validated(
            sourceURL: fixtureURL,
            headers: [:],
            audio: .init(languageCode: "en", title: nil),
            range: 5..<5
        ))
        XCTAssertThrowsError(try StreamAudioSampleRequest.validated(
            sourceURL: fixtureURL,
            headers: ["X-Test": "allowed\r\nX-Injected: unsafe"],
            audio: .init(languageCode: "en", title: nil),
            range: 0..<5
        ))
    }

    func testSamplerDecodesFixtureAsMono11025Hz() async throws {
        let samples = try await FFmpegStreamAudioSampler().samples(
            for: .validated(
                sourceURL: fixtureURL,
                headers: [:],
                audio: .init(languageCode: "en", title: nil),
                range: 0..<5
            )
        )

        XCTAssertLessThanOrEqual(abs(samples.count - 55_125), 2_048)
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
    }

    func testSelectedAudioConfigurationDiscardsVideoAndAlternateAudio() throws {
        try withFormatContext(for: multistreamFixtureURL) { formatContext in
            let selected = FFmpegStreamAudioSampler.configureSelectedAudioStream(
                in: formatContext,
                descriptor: .init(languageCode: "sv", title: "Commentary")
            )

            XCTAssertEqual(selected, 2)
            XCTAssertEqual(formatContext.pointee.streams[0]?.pointee.discard, AVDISCARD_ALL)
            XCTAssertEqual(formatContext.pointee.streams[1]?.pointee.discard, AVDISCARD_ALL)
            XCTAssertEqual(formatContext.pointee.streams[2]?.pointee.discard, AVDISCARD_DEFAULT)
        }
    }

    func testSelectedAudioConfigurationFallsBackToDefaultAudio() throws {
        try withFormatContext(for: multistreamFixtureURL) { formatContext in
            let selected = FFmpegStreamAudioSampler.configureSelectedAudioStream(
                in: formatContext,
                descriptor: .init(languageCode: "fr", title: "Unavailable")
            )

            XCTAssertEqual(selected, 1)
            XCTAssertEqual(formatContext.pointee.streams[0]?.pointee.discard, AVDISCARD_ALL)
            XCTAssertEqual(formatContext.pointee.streams[1]?.pointee.discard, AVDISCARD_DEFAULT)
            XCTAssertEqual(formatContext.pointee.streams[2]?.pointee.discard, AVDISCARD_ALL)
        }
    }

    func testSamplerUsesStreamStartAsOpeningOriginAndStopsAtRequestedEnd() async throws {
        let samples = try await FFmpegStreamAudioSampler().samples(
            for: .validated(
                sourceURL: nonzeroOriginFixtureURL,
                headers: [:],
                audio: .init(languageCode: "en", title: nil),
                range: 1..<2
            )
        )

        XCTAssertLessThanOrEqual(abs(samples.count - 11_025), 256)
        XCTAssertGreaterThan(rootMeanSquare(of: samples.prefix(1_000)), 0.03)
        XCTAssertGreaterThan(rootMeanSquare(of: samples.suffix(1_000)), 0.03)
    }

    func testPackedHighChannelFrameUsesExactlyOneInputPlane() throws {
        var frame = av_frame_alloc()
        XCTAssertNotNil(frame)
        defer { av_frame_free(&frame) }
        guard let frame else { return }

        frame.pointee.format = AV_SAMPLE_FMT_S16.rawValue
        frame.pointee.sample_rate = 48_000
        frame.pointee.nb_samples = 32
        av_channel_layout_default(&frame.pointee.ch_layout, 12)
        XCTAssertEqual(av_frame_get_buffer(frame, 0), 0)

        var expectedLayout = AVChannelLayout()
        av_channel_layout_default(&expectedLayout, 12)
        defer { av_channel_layout_uninit(&expectedLayout) }

        var observedPlaneCount = 0
        try FFmpegStreamAudioSampler.withValidatedAudioInputPlanes(
            frame: frame,
            expectedSampleFormat: AV_SAMPLE_FMT_S16,
            expectedSampleRate: 48_000,
            expectedChannelLayout: &expectedLayout
        ) { planes in
            observedPlaneCount = planes.count
            XCTAssertNotNil(planes.first ?? nil)
        }

        XCTAssertEqual(observedPlaneCount, 1)
    }

    func testRequestedTimeBoundaryFlushesResamplerTail() async throws {
        let firstInputFrameDuration = Double(4_096) / 44_100
        let samples = try await FFmpegStreamAudioSampler().samples(
            for: .validated(
                sourceURL: fixtureURL,
                headers: [:],
                audio: .init(languageCode: "en", title: nil),
                range: 0..<firstInputFrameDuration
            )
        )

        XCTAssertEqual(samples.count, 1_024)
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
    }

    func testDecoderDrainSendResultFollowsEOFAndEAGAINContract() throws {
        XCTAssertEqual(
            try FFmpegStreamAudioSampler.decoderDrainAction(forSendResult: 0),
            .accepted
        )
        XCTAssertEqual(
            try FFmpegStreamAudioSampler.decoderDrainAction(forSendResult: -EAGAIN),
            .receiveThenRetry
        )
        XCTAssertEqual(
            try FFmpegStreamAudioSampler.decoderDrainAction(forSendResult: -541_478_725),
            .alreadyDrained
        )
        XCTAssertThrowsError(
            try FFmpegStreamAudioSampler.decoderDrainAction(forSendResult: -1_234)
        ) { error in
            XCTAssertEqual(
                error as? StreamAudioSampleError,
                .decodeFailed(-1_234)
            )
        }
    }

    func testCancellationInterruptsBlockedReadAndReleasesDecodeContext() async throws {
        let server = try BlockingHTTPServer()
        server.start()
        defer { server.stop() }

        let sampler = FFmpegStreamAudioSampler()
        let result = LockedSamplingResult()
        let completed = expectation(description: "Blocked FFmpeg read completed")
        let task = Task {
            do {
                _ = try await sampler.samples(
                    for: .validated(
                        sourceURL: server.url,
                        headers: [:],
                        audio: .init(languageCode: "en", title: nil),
                        range: 0..<5
                    )
                )
                result.store(nil)
            } catch {
                result.store(error)
            }
            completed.fulfill()
        }

        let contextDeadline = ContinuousClock.now + .seconds(1)
        while FFmpegStreamAudioSampler.activeDecodeContextCount == 0,
              ContinuousClock.now < contextDeadline {
            await Task.yield()
        }
        XCTAssertEqual(FFmpegStreamAudioSampler.activeDecodeContextCount, 1)

        let cancelledAt = ContinuousClock.now
        task.cancel()
        await fulfillment(of: [completed], timeout: 1)

        XCTAssertTrue(result.error is CancellationError)
        XCTAssertLessThan(ContinuousClock.now - cancelledAt, .seconds(1))
        XCTAssertEqual(FFmpegStreamAudioSampler.activeDecodeContextCount, 0)
    }

    private func withFormatContext(
        for url: URL,
        _ body: (UnsafeMutablePointer<AVFormatContext>) throws -> Void
    ) throws {
        var context: UnsafeMutablePointer<AVFormatContext>?
        let openResult = url.path.withCString {
            avformat_open_input(&context, $0, nil, nil)
        }
        XCTAssertGreaterThanOrEqual(openResult, 0)
        guard openResult >= 0, let openedContext = context else { return }
        defer { avformat_close_input(&context) }

        let infoResult = avformat_find_stream_info(openedContext, nil)
        XCTAssertGreaterThanOrEqual(infoResult, 0)
        guard infoResult >= 0 else { return }
        try body(openedContext)
    }

    private func rootMeanSquare<S: Sequence>(of samples: S) -> Float where S.Element == Float {
        var sum: Float = 0
        var count = 0
        for sample in samples {
            sum += sample * sample
            count += 1
        }
        return count == 0 ? 0 : sqrt(sum / Float(count))
    }
}

private final class LockedSamplingResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }

    func store(_ error: Error?) {
        lock.lock()
        storedError = error
        lock.unlock()
    }
}

private final class BlockingHTTPServer: @unchecked Sendable {
    private let listener: Int32
    private let lock = NSLock()
    private var acceptedConnection: Int32 = -1
    private var isStopped = false
    let url: URL

    init() throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw POSIXError(.ENOTSOCK)
        }

        var reuse: Int32 = 1
        guard setsockopt(
            listener,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuse,
            socklen_t(MemoryLayout.size(ofValue: reuse))
        ) == 0 else {
            close(listener)
            throw POSIXError(.EADDRNOTAVAIL)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    listener,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard bindResult == 0, listen(listener, 1) == 0 else {
            close(listener)
            throw POSIXError(.EADDRINUSE)
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(listener, $0, &boundLength)
            }
        }
        guard nameResult == 0 else {
            close(listener)
            throw POSIXError(.EADDRNOTAVAIL)
        }

        self.listener = listener
        url = URL(string: "http://127.0.0.1:\(UInt16(bigEndian: boundAddress.sin_port))/audio")!
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else { return }

            lock.lock()
            if isStopped {
                lock.unlock()
                close(connection)
                return
            }
            acceptedConnection = connection
            lock.unlock()
        }
    }

    func stop() {
        lock.lock()
        guard !isStopped else {
            lock.unlock()
            return
        }
        isStopped = true
        let connection = acceptedConnection
        acceptedConnection = -1
        lock.unlock()

        if connection >= 0 {
            shutdown(connection, SHUT_RDWR)
            close(connection)
        }
        shutdown(listener, SHUT_RDWR)
        close(listener)
    }

    deinit {
        stop()
    }
}
