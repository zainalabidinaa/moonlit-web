import XCTest
import Compression
@testable import MoonlitCore

/// Covers `Gzip.gunzip` (gzip header-skip + raw DEFLATE inflate) used for `.xml.gz`
/// EPG feeds. Builds a valid gzip payload locally so the test is deterministic and
/// needs no network, and confirms the full gunzip → XMLTVParser.parse path.
final class GzipTests: XCTestCase {

    /// Raw DEFLATE-encode via Apple's Compression (COMPRESSION_ZLIB == raw DEFLATE),
    /// then wrap in a minimal gzip container (10-byte header, dummy CRC, ISIZE).
    private func makeGzip(_ input: Data) -> Data {
        let src = [UInt8](input)
        let dstCap = src.count + 4096
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: dstCap)
        defer { dst.deallocate() }
        let written = src.withUnsafeBufferPointer { srcBuf in
            compression_encode_buffer(dst, dstCap, srcBuf.baseAddress!, srcBuf.count, nil, COMPRESSION_ZLIB)
        }
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0, 0x03]) // gzip header, FLG=0
        out.append(dst, count: written)
        out.append(contentsOf: [0, 0, 0, 0]) // dummy CRC32 (gunzip ignores it)
        let isize = UInt32(truncatingIfNeeded: input.count)
        out.append(contentsOf: [UInt8(isize & 0xff), UInt8((isize >> 8) & 0xff), UInt8((isize >> 16) & 0xff), UInt8((isize >> 24) & 0xff)])
        return out
    }

    func testGunzipRoundtrip() throws {
        let original = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 500)
        let gz = makeGzip(Data(original.utf8))
        XCTAssertTrue(Gzip.isGzipped(gz))
        XCTAssertLessThan(gz.count, original.utf8.count, "gzip should be smaller than the input")

        let inflated = Gzip.gunzip(gz)
        XCTAssertNotNil(inflated)
        XCTAssertEqual(String(decoding: inflated!, as: UTF8.self), original)
    }

    func testGunzipThenParseXmltv() throws {
        let xml = """
        <tv><channel id="c1"><display-name>Channel One</display-name></channel>
        <programme start="20260715120000 +0000" stop="20260715130000 +0000" channel="c1"><title>Show A</title></programme>
        <programme start="20260715130000 +0000" stop="20260715140000 +0000" channel="c1"><title>Show B</title></programme></tv>
        """
        let gz = makeGzip(Data(xml.utf8))
        let inflated = try XCTUnwrap(Gzip.gunzip(gz))
        let result = XMLTVParser.parse(String(decoding: inflated, as: UTF8.self))
        XCTAssertEqual(result.programs.map(\.title), ["Show A", "Show B"])
        XCTAssertEqual(result.channelMeta["c1"]?.displayName, "Channel One")
    }

    func testNonGzipReturnsNil() {
        XCTAssertNil(Gzip.gunzip(Data("plain text not gzip".utf8)))
        XCTAssertFalse(Gzip.isGzipped(Data("<tv></tv>".utf8)))
    }
}
