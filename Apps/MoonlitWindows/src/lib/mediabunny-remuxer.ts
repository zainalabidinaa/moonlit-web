/**
 * MediabunnyRemuxer — client-side MKV→MP4 transmux engine.
 *
 * Uses Mediabunny's pure-TypeScript demuxer/muxer to repackage MKV streams
 * into fragmented MP4 (fMP4) and feeds chunks to a MediaSource for instant playback.
 *
 * Transmuxing is a stream-copy: no decoding/re-encoding → lossless, I/O-bound.
 * The first fMP4 fragment arrives in ~0.5-1s, giving a Netflix-like start.
 */

import {
  Input,
  Output,
  Conversion,
  ConversionCanceledError,
  Mp4OutputFormat,
  AppendOnlyStreamTarget,
  UrlSource,
  ALL_FORMATS,
} from 'mediabunny';

export interface RemuxerCallbacks {
  onChunk: (data: Uint8Array) => void;
  onProgress?: (progress: number) => void;
  onReady?: (mimeType: string) => void;
  onError?: (error: Error) => void;
}

export class MediabunnyRemuxer {
  private input: Input | null = null;
  private output: Output | null = null;
  private conversion: Conversion | null = null;
  private writable: WritableStream<Uint8Array> | null = null;
  private cancelled = false;
  private executing = false;

  /**
   * Start transmuxing an MKV file to fragmented MP4.
   * Calls onChunk with each fMP4 fragment as it's produced.
   * Calls onReady(mimeType) when the first fragment is available and the MIME type is known.
   */
  async start(url: string, callbacks: RemuxerCallbacks): Promise<void> {
    this.cancelled = false;

    try {
      const sourceUrl = url.startsWith('/api/media-proxy')
        ? url
        : `/api/media-proxy?url=${encodeURIComponent(url)}`;

      // Create output first — we need the WritableStream ready
      this.writable = new WritableStream<Uint8Array>({
        write: (chunk) => {
          if (!this.cancelled) callbacks.onChunk(chunk);
        },
      });

      this.output = new Output({
        format: new Mp4OutputFormat({
          fastStart: 'fragmented',
          minimumFragmentDuration: 0.5,
        }),
        target: new AppendOnlyStreamTarget(this.writable),
      });

      // Create input from proxy URL
      this.input = new Input({
        source: new UrlSource(sourceUrl),
        formats: ALL_FORMATS,
      });

      // Probe codec compatibility before conversion
      const videoTrack = await this.input.getPrimaryVideoTrack();
      const audioTrack = await this.input.getPrimaryAudioTrack();

      const videoCodec = await videoTrack?.getCodec();
      const audioCodec = await audioTrack?.getCodec();

      const videoDecodable = videoTrack ? await videoTrack.canDecode() : false;
      const audioDecodable = audioTrack ? await audioTrack.canDecode() : false;

      const videoOk = videoCodec !== null && videoDecodable;
      const audioOk = audioCodec !== null && audioDecodable;

      if (!videoOk && !audioOk) {
        throw new Error(`Unsupported codecs: video=${videoCodec ?? 'unknown'}, audio=${audioCodec ?? 'unknown'}`);
      }

      // Initialize conversion
      this.conversion = await Conversion.init({
        input: this.input,
        output: this.output,
        tracks: 'primary',
      });

      if (!this.conversion.isValid) {
        const reasons = this.conversion.discardedTracks
          .map((d) => `${d.track.type}: ${d.reason}`)
          .join(', ');
        throw new Error(`Conversion invalid: ${reasons}`);
      }

      // Set progress callback
      this.conversion.onProgress = (progress) => {
        if (!this.cancelled) callbacks.onProgress?.(progress);
      };

      // Get MIME type now that tracks are configured
      const mimeType = await this.output.getMimeType();
      callbacks.onReady?.(mimeType);

      // Execute transmux — this blocks until complete or cancelled
      this.executing = true;
      await this.conversion.execute();
      this.executing = false;
    } catch (e) {
      if (e instanceof ConversionCanceledError) return;
      callbacks.onError?.(e instanceof Error ? e : new Error(String(e)));
    } finally {
      this.executing = false;
    }
  }

  /** Cancel the current conversion and clean up resources. */
  async destroy(): Promise<void> {
    this.cancelled = true;
    if (this.executing) {
      try { await this.conversion?.cancel(); } catch {}
    }
    try { this.input?.dispose?.(); } catch {}
    this.input = null;
    this.output = null;
    this.conversion = null;
    this.writable = null;
  }
}
