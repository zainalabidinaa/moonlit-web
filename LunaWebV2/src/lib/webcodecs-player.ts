/**
 * Client-side MKV/any-container player using web-demuxer (WebAssembly) + WebCodecs.
 * Replaces the Render remux server for incompatible streams — no cold start, no round-trip.
 *
 * Architecture:
 *  web-demuxer (WASM) → raw encoded packets
 *  VideoDecoder       → VideoFrame → Canvas 2D
 *  AudioDecoder       → AudioData  → AudioContext (scheduled AudioBufferSourceNodes)
 *
 * A/V sync: AudioContext.currentTime is the clock; video frames are scheduled
 * relative to it so they render at the correct wall-clock time.
 */

import { WebDemuxer, AVMediaType } from 'web-demuxer';

export interface WebCodecsPlayerState {
  duration: number;
  currentTime: number;
  isPlaying: boolean;
  isReady: boolean;
  error: string | null;
}

type StateListener = (state: WebCodecsPlayerState) => void;

const WASM_PATH = '/web-demuxer-mini.wasm';

export class WebCodecsPlayerEngine {
  private demuxer: WebDemuxer | null = null;
  private videoDecoder: VideoDecoder | null = null;
  private audioDecoder: AudioDecoder | null = null;
  private audioCtx: AudioContext | null = null;
  private canvas: HTMLCanvasElement | null = null;
  private ctx: CanvasRenderingContext2D | null = null;

  private _state: WebCodecsPlayerState = {
    duration: 0,
    currentTime: 0,
    isPlaying: false,
    isReady: false,
    error: null,
  };

  private listeners = new Set<StateListener>();
  private pumpAbort: AbortController | null = null;
  // When playback started: audioCtx.currentTime at that moment
  private audioStartTime = 0;
  // PTS offset: the stream PTS value that corresponds to audioStartTime
  private ptsOffset = 0;
  private videoPaused = false;

  // ── Public API ───────────────────────────────────────────────────────────

  subscribe(fn: StateListener) {
    this.listeners.add(fn);
    fn(this._state);
    return () => this.listeners.delete(fn);
  }

  async load(url: string, canvas: HTMLCanvasElement) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.audioCtx = new AudioContext();

    try {
      this.demuxer = new WebDemuxer({ wasmLoaderPath: WASM_PATH });
      // Proxy through Vercel to handle CORS
      const proxied = `/api/media-proxy?url=${encodeURIComponent(url)}`;
      await this.demuxer.load(proxied);

      const videoStream = await this.demuxer.getAVStream(AVMediaType.AVMEDIA_TYPE_VIDEO);
      const audioStream = await this.demuxer.getAVStream(AVMediaType.AVMEDIA_TYPE_AUDIO).catch(() => null);

      canvas.width = videoStream.codecpar.width;
      canvas.height = videoStream.codecpar.height;

      this._setupVideoDecoder(videoStream);
      if (audioStream) this._setupAudioDecoder(audioStream);

      const duration = videoStream.duration ?? 0;
      this._setState({ duration, isReady: true });
    } catch (e) {
      this._setState({ error: String(e) });
    }
  }

  play() {
    if (!this._state.isReady || this._state.isPlaying) return;
    this.audioCtx?.resume();
    this._setState({ isPlaying: true });
    this.videoPaused = false;
    this._startPump(this._state.currentTime);
  }

  pause() {
    this.videoPaused = true;
    this.pumpAbort?.abort();
    this.audioCtx?.suspend();
    this._setState({ isPlaying: false });
  }

  async seek(time: number) {
    const wasPlaying = this._state.isPlaying;
    this.pumpAbort?.abort();
    this.videoDecoder?.flush();
    this.audioDecoder?.flush();
    this._setState({ currentTime: time, isPlaying: false });
    if (wasPlaying) {
      this._setState({ isPlaying: true });
      this.videoPaused = false;
      this._startPump(time);
    }
  }

  destroy() {
    this.pumpAbort?.abort();
    this.videoDecoder?.close();
    this.audioDecoder?.close();
    this.audioCtx?.close();
    this.demuxer?.destroy?.();
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  private _setState(patch: Partial<WebCodecsPlayerState>) {
    this._state = { ...this._state, ...patch };
    this.listeners.forEach(fn => fn(this._state));
  }

  private _setupVideoDecoder(stream: any) {
    this.videoDecoder = new VideoDecoder({
      output: (frame) => this._onVideoFrame(frame),
      error: (e) => this._setState({ error: `Video decoder: ${e.message}` }),
    });
    this.videoDecoder.configure({
      codec: stream.codecpar.codecString ?? 'avc1.64001f',
      codedWidth: stream.codecpar.width,
      codedHeight: stream.codecpar.height,
      ...(stream.codecpar.extradata?.byteLength ? { description: stream.codecpar.extradata } : {}),
    });
  }

  private _setupAudioDecoder(stream: any) {
    this.audioDecoder = new AudioDecoder({
      output: (data) => this._onAudioData(data),
      error: (e) => console.warn('Audio decoder:', e.message),
    });
    try {
      this.audioDecoder.configure({
        codec: stream.codecpar.codecString ?? 'mp4a.40.2',
        sampleRate: stream.codecpar.sampleRate,
        numberOfChannels: stream.codecpar.channels,
        ...(stream.codecpar.extradata?.byteLength ? { description: stream.codecpar.extradata } : {}),
      });
    } catch {
      // Audio codec unsupported — video-only playback
      this.audioDecoder = null;
    }
  }

  private _onVideoFrame(frame: VideoFrame) {
    if (!this.ctx || !this.canvas || this.videoPaused) { frame.close(); return; }

    const ptsSec = (frame.timestamp ?? 0) / 1e6;
    const now = this.audioCtx!.currentTime;
    const expectedTime = this.audioStartTime + (ptsSec - this.ptsOffset);
    const delay = (expectedTime - now) * 1000;

    const render = () => {
      if (this.videoPaused) { frame.close(); return; }
      this.ctx!.drawImage(frame, 0, 0, this.canvas!.width, this.canvas!.height);
      frame.close();
      this._setState({ currentTime: ptsSec });
    };

    if (delay > 10) {
      setTimeout(render, delay);
    } else {
      render();
    }
  }

  private _onAudioData(data: AudioData) {
    if (!this.audioCtx) { data.close(); return; }

    const buffer = this.audioCtx.createBuffer(
      data.numberOfChannels,
      data.numberOfFrames,
      data.sampleRate,
    );
    for (let ch = 0; ch < data.numberOfChannels; ch++) {
      const dest = buffer.getChannelData(ch);
      data.copyTo(dest, { planeIndex: ch, format: 'f32-planar' });
    }
    data.close();

    const source = this.audioCtx.createBufferSource();
    source.buffer = buffer;
    source.connect(this.audioCtx.destination);

    const ptsSec = (data.timestamp ?? 0) / 1e6;
    const scheduleAt = this.audioStartTime + (ptsSec - this.ptsOffset);
    source.start(Math.max(scheduleAt, this.audioCtx.currentTime));
  }

  private async _startPump(fromTime: number) {
    if (!this.demuxer) return;
    this.pumpAbort = new AbortController();
    const signal = this.pumpAbort.signal;

    // Sync clocks: record current audio time as the reference for PTS fromTime
    this.audioStartTime = this.audioCtx!.currentTime;
    this.ptsOffset = fromTime;

    const CHUNK_SECS = 10;
    let cursor = fromTime;

    try {
      while (!signal.aborted) {
        const end = cursor + CHUNK_SECS;

        // Video packets
        if (this.videoDecoder) {
          for await (const pkt of this.demuxer.readAVPacket(cursor, end, AVMediaType.AVMEDIA_TYPE_VIDEO)) {
            if (signal.aborted) return;
            this.videoDecoder.decode(new EncodedVideoChunk({
              type: pkt.flags === 1 ? 'key' : 'delta',
              timestamp: pkt.pts,
              duration: pkt.duration,
              data: pkt.data,
            }));
          }
        }

        // Audio packets
        if (this.audioDecoder) {
          for await (const pkt of this.demuxer.readAVPacket(cursor, end, AVMediaType.AVMEDIA_TYPE_AUDIO)) {
            if (signal.aborted) return;
            this.audioDecoder.decode(new EncodedAudioChunk({
              type: 'key',
              timestamp: pkt.pts,
              duration: pkt.duration,
              data: pkt.data,
            }));
          }
        }

        cursor = end;
        if (cursor >= this._state.duration) break;

        // Pace the pump: wait until we're ~3s from the end of the decoded window
        // so we don't flood the decoder with the whole file at once
        await new Promise<void>(resolve => setTimeout(resolve, (CHUNK_SECS - 3) * 1000));
      }
    } catch {
      // Pump aborted or stream ended — normal
    }
  }
}
