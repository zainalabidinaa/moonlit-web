import { describe, expect, it, vi } from 'vitest';

vi.mock('mediabunny', () => {
  let conversionStarted = false;

  class AppendOnlyStreamTarget {
    constructor(writable: WritableStream<Uint8Array>) {
      const writer = writable.getWriter();
      writer.releaseLock();
    }
  }

  class Input {
    constructor() {
      conversionStarted = false;
    }

    getPrimaryVideoTrack() {
      return Promise.resolve({
        getCodec: () => Promise.resolve('avc'),
        canDecode: () => Promise.resolve(true),
      });
    }

    getPrimaryAudioTrack() {
      return Promise.resolve({
        getCodec: () => Promise.resolve('aac'),
        canDecode: () => Promise.resolve(true),
      });
    }

    dispose() {}
  }

  class Output {
    getMimeType() {
      if (!conversionStarted) throw new Error('MIME requested before conversion began');
      return Promise.resolve('video/mp4; codecs="avc1.42E01E, mp4a.40.2"');
    }
  }

  class Conversion {
    isValid = true;
    discardedTracks: unknown[] = [];
    onProgress: ((progress: number) => void) | null = null;

    static init() {
      return Promise.resolve(new Conversion());
    }

    execute() {
      conversionStarted = true;
      this.onProgress?.(1);
      return Promise.resolve();
    }

    cancel() {
      return Promise.resolve();
    }
  }

  return {
    ALL_FORMATS: [],
    AppendOnlyStreamTarget,
    Conversion,
    ConversionCanceledError: class ConversionCanceledError extends Error {},
    Input,
    Mp4OutputFormat: class Mp4OutputFormat {},
    Output,
    UrlSource: class UrlSource {},
  };
});

describe('MediabunnyRemuxer', () => {
  it('lets AppendOnlyStreamTarget own the writable stream writer', async () => {
    const { MediabunnyRemuxer } = await import('./mediabunny-remuxer');
    const onError = vi.fn();

    await new MediabunnyRemuxer().start('https://cdn.example.com/movie.mp4', {
      onChunk: vi.fn(),
      onError,
    });

    expect(onError).not.toHaveBeenCalledWith(expect.objectContaining({
      message: expect.stringContaining('WritableStream is locked'),
    }));
  });

  it('starts conversion before waiting for muxer MIME metadata', async () => {
    const { MediabunnyRemuxer } = await import('./mediabunny-remuxer');
    const onReady = vi.fn();
    const onError = vi.fn();

    await new MediabunnyRemuxer().start('https://cdn.example.com/movie.mkv', {
      onChunk: vi.fn(),
      onReady,
      onError,
    });

    expect(onReady).toHaveBeenCalledWith('video/mp4; codecs="avc1.42E01E, mp4a.40.2"');
    expect(onError).not.toHaveBeenCalled();
  });
});
