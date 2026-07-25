// Packages/MoonlitCore/Sources/MoonlitCore/IPTV/Gzip.swift
//
// Minimal gzip inflater for EPG feeds served as `.xml.gz` (Content-Type
// octet-stream, so URLSession won't transparently decompress them). Apple's
// Compression framework decodes raw DEFLATE via COMPRESSION_ZLIB, so we strip the
// gzip header/trailer and stream-inflate the DEFLATE payload.
import Foundation
import Compression

public enum Gzip {

    /// True when `data` starts with the gzip magic bytes (0x1f 0x8b).
    public static func isGzipped(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b
    }

    /// Inflate a gzip payload. Returns nil if the data isn't valid gzip.
    public static func gunzip(_ data: Data) -> Data? {
        guard isGzipped(data), data.count > 18 else { return nil }
        let bytes = [UInt8](data)

        // --- Skip the gzip header (RFC 1952) ---
        guard bytes[2] == 8 else { return nil } // CM must be DEFLATE
        let flg = bytes[3]
        var offset = 10
        let count = bytes.count

        if flg & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= count else { return nil }
            let xlen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flg & 0x08 != 0 { // FNAME (null-terminated)
            while offset < count && bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flg & 0x10 != 0 { // FCOMMENT (null-terminated)
            while offset < count && bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flg & 0x02 != 0 { // FHCRC
            offset += 2
        }
        // Last 8 bytes are CRC32 + ISIZE; the DEFLATE stream ends before them.
        guard offset < count - 8 else { return nil }
        let deflate = data.subdata(in: (data.startIndex + offset)..<(data.startIndex + count - 8))

        return inflateRawDeflate(deflate, hint: Int(isize(bytes)))
    }

    /// The gzip trailer's ISIZE field (uncompressed size mod 2^32) — a good buffer
    /// hint, though it wraps above 4GB.
    private static func isize(_ bytes: [UInt8]) -> UInt32 {
        let n = bytes.count
        return UInt32(bytes[n - 4]) | (UInt32(bytes[n - 3]) << 8) | (UInt32(bytes[n - 2]) << 16) | (UInt32(bytes[n - 1]) << 24)
    }

    private static func inflateRawDeflate(_ deflate: Data, hint: Int) -> Data? {
        var stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!, dst_size: 0,
                                        src_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            return nil
        }
        defer { compression_stream_destroy(&stream) }

        let bufferSize = 256 * 1024
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dstBuffer.deallocate() }

        var output = Data(capacity: max(hint, bufferSize))
        return deflate.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = rawPtr.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.src_ptr = srcBase
            stream.src_size = deflate.count

            while true {
                stream.dst_ptr = dstBuffer
                stream.dst_size = bufferSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    let produced = bufferSize - stream.dst_size
                    if produced > 0 { output.append(dstBuffer, count: produced) }
                    if status == COMPRESSION_STATUS_END { return output }
                default:
                    return nil
                }
            }
        }
    }
}
