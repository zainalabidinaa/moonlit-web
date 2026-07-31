import XCTest
import Darwin
@testable import MoonlitApp

final class StreamAudioSamplerTests: XCTestCase {
    private var fixtureURL: URL {
        let bundle = Bundle(for: StreamAudioSamplerTests.self)
        return bundle.url(
            forResource: "fingerprint-reference",
            withExtension: "wav",
            subdirectory: "Fixtures"
        ) ?? bundle.url(
            forResource: "fingerprint-reference",
            withExtension: "wav"
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
