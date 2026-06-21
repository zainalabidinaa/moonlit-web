/**
 * Client-side MKV/any-container player using web-demuxer (WebAssembly) + WebCodecs.
 * Uses the library's built-in helpers: getDecoderConfig() + read() + genEncodedChunk().
 */

import { WebDemuxer } from 'web-demuxer';

export interface WebCodecsPlayerState {
  duration: number;
  currentTime: number;
  isPlaying: boolean;
  isReady: boolean;
  error: string | null;
}

type StateListener = (state: WebCodecsPlayerState) => void;

export class WebCodecsPlayerEngine {
  private demuxer: WebDemuxer | null = null;
  private videoDecoder: VideoDecoder | null = null;
  private audioDecoder: AudioDecoder | null = null;
  private audioCtx: AudioContext | null = null;
  private canvas: HTMLCanvasElement | null = null;
  private ctx: CanvasRenderingContext2D | null = null;

  private _state: WebCodecsPlayerState = {
    duration: 0, currentTime: 0, isPlaying: false, isReady: false, error: null,
  };

  private listeners = new Set<StateListener>();
  private pumpAbort: AbortController | null = null;
  private audioStartTime = 0;
  private ptsOffset = 0;
  private videoPaused = false;

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
      this.demuxer = new WebDemuxer({ wasmFilePath: `${location.origin}/web-demuxer-mini.wasm` });
      const proxied = `/api/media-proxy?url=${encodeURIComponent(url)}`;
      await this.demuxer.load(proxied);

      // Use library helpers for decoder config
      const videoConfig = await this.demuxer.getDecoderConfig('video');
      const audioConfig = await this.demuxer.getDecoderConfig('audio').catch(() => null);

      const videoStream = await this.demuxer.getMediaStream('video');
      canvas.width = videoStream.width || 1920;
      canvas.height = videoStream.height || 1080;

      this._setupVideoDecoder(videoConfig as VideoDecoderConfig);
      if (audioConfig) this._setupAudioDecoder(audioConfig as AudioDecoderConfig);

      this._setState({ duration: videoStream.duration, isReady: true });
    } catch (e) {
      this._setState({ error: `Failed to load: ${e}` });
    }
  }

  play() {
    if (!this._state.isReady || this._state.isPlaying) return;
    this.audioCtx?.resume();
    this.videoPaused = false;
    this._setState({ isPlaying: true });
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
      this.videoPaused = false;
      this._setState({ isPlaying: true });
      this._startPump(time);
    }
  }

  destroy() {
    this.pumpAbort?.abort();
    this.videoDecoder?.close();
    this.audioDecoder?.close();
    this.audioCtx?.close();
    this.demuxer?.destroy();
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  private _setState(patch: Partial<WebCodecsPlayerState>) {
    this._state = { ...this._state, ...patch };
    this.listeners.forEach(fn => fn(this._state));
  }

  private _setupVideoDecoder(config: VideoDecoderConfig) {
    this.videoDecoder = new VideoDecoder({
      output: (frame) => this._onVideoFrame(frame),
      error: (e) => this._setState({ error: `Video decoder: ${e.message}` }),
    });
    this.videoDecoder.configure(config);
  }

  private _setupAudioDecoder(config: AudioDecoderConfig) {
    try {
      this.audioDecoder = new AudioDecoder({
        output: (data) => this._onAudioData(data),
        error: (e) => console.warn('Audio decoder:', e.message),
      });
      this.audioDecoder.configure(config);
    } catch {
      this.audioDecoder = null;
    }
  }

  private _onVideoFrame(frame: VideoFrame) {
    if (!this.ctx || !this.canvas || this.videoPaused) { frame.close(); return; }

    const ptsSec = (frame.timestamp ?? 0) / 1e6;
    const now = this.audioCtx!.currentTime;
    const expectedAt = this.audioStartTime + (ptsSec - this.ptsOffset);
    const delayMs = (expectedAt - now) * 1000;

    const render = () => {
      if (this.videoPaused) { frame.close(); return; }
      this.ctx!.drawImage(frame, 0, 0, this.canvas!.width, this.canvas!.height);
      frame.close();
      this._setState({ currentTime: ptsSec });
    };

    if (delayMs > 10) setTimeout(render, delayMs);
    else render();
  }

  private _onAudioData(data: AudioData) {
    if (!this.audioCtx) { data.close(); return; }
    try {
      const buf = this.audioCtx.createBuffer(data.numberOfChannels, data.numberOfFrames, data.sampleRate);
      for (let ch = 0; ch < data.numberOfChannels; ch++) {
        data.copyTo(buf.getChannelData(ch), { planeIndex: ch, format: 'f32-planar' });
      }
      data.close();
      const src = this.audioCtx.createBufferSource();
      src.buffer = buf;
      src.connect(this.audioCtx.destination);
      const ptsSec = (data.timestamp ?? 0) / 1e6;
      const scheduleAt = this.audioStartTime + (ptsSec - this.ptsOffset);
      src.start(Math.max(scheduleAt, this.audioCtx.currentTime));
    } catch { data.close(); }
  }

  private async _startPump(fromTime: number) {
    if (!this.demuxer) return;
    this.pumpAbort = new AbortController();
    const signal = this.pumpAbort.signal;

    this.audioStartTime = this.audioCtx!.currentTime;
    this.ptsOffset = fromTime;

    const CHUNK = 10;
    let cursor = fromTime;

    try {
      while (!signal.aborted && cursor < this._state.duration) {
        const end = cursor + CHUNK;

        // read() returns ReadableStream<EncodedVideoChunk | EncodedAudioChunk>
        const videoStream = this.demuxer.read('video', cursor, end);
        const reader = videoStream.getReader();
        while (true) {
          const { done, value } = await reader.read();
          if (done || signal.aborted) break;
          this.videoDecoder?.decode(value as EncodedVideoChunk);
        }
        reader.releaseLock();

        if (this.audioDecoder) {
          const audioStream = this.demuxer.read('audio', cursor, end);
          const areader = audioStream.getReader();
          while (true) {
            const { done, value } = await areader.read();
            if (done || signal.aborted) break;
            this.audioDecoder.decode(value as EncodedAudioChunk);
          }
          areader.releaseLock();
        }

        cursor = end;
        // Pace: wait until ~3s before end of decoded window so we don't flood the decoder
        if (!signal.aborted) await new Promise<void>(r => setTimeout(r, (CHUNK - 3) * 1000));
      }
    } catch { /* pump stopped */ }
  }
}
