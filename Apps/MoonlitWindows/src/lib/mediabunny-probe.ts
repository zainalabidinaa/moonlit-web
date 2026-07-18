import {
  ALL_FORMATS,
  Input,
  UrlSource,
} from 'mediabunny';

import type { MediabunnyProbeResult } from '@/components/player/PlayerShell.stream';
import type { StreamItem } from '@/lib/types';

const PROBE_TIMEOUT_MS = 8000;

export async function probeMediabunnyPlayback(
  url: string,
  _stream: StreamItem,
): Promise<MediabunnyProbeResult> {
  let input: Input | null = null;

  try {
    input = new Input({
      source: new UrlSource(url),
      formats: ALL_FORMATS,
    });

    const result = await Promise.race([
      doProbe(input, url),
      timeout(PROBE_TIMEOUT_MS),
    ]);

    return result ?? {
      playable: false,
      transport: url.startsWith('/api/media-proxy') ? 'proxy' : 'direct',
      reason: 'probe-timeout',
    };
  } catch (error) {
    return {
      playable: false,
      transport: url.startsWith('/api/media-proxy') ? 'proxy' : 'direct',
      reason: error instanceof Error ? error.message : String(error),
    };
  } finally {
    try { input?.dispose?.(); } catch {}
  }
}

async function doProbe(input: Input, url: string): Promise<MediabunnyProbeResult> {
  const [videoTrack, audioTrack] = await Promise.all([
    input.getPrimaryVideoTrack(),
    input.getPrimaryAudioTrack(),
  ]);

  const [videoCodec, audioCodec] = await Promise.all([
    videoTrack?.getCodec() ?? Promise.resolve(null),
    audioTrack?.getCodec() ?? Promise.resolve(null),
  ]);

  const [videoDecodable, audioDecodable] = await Promise.all([
    videoTrack?.canDecode() ?? Promise.resolve(false),
    audioTrack?.canDecode() ?? Promise.resolve(false),
  ]);

  const videoOk = !videoTrack || (videoCodec !== null && videoDecodable);
  const audioOk = !audioTrack || (audioCodec !== null && audioDecodable);

  return {
    playable: videoOk && audioOk && !!(videoTrack || audioTrack),
    transport: url.startsWith('/api/media-proxy') ? 'proxy' : 'direct',
    reason: videoOk && audioOk ? undefined : 'unsupported-codecs',
  };
}

function timeout(ms: number): Promise<null> {
  return new Promise(resolve => setTimeout(() => resolve(null), ms));
}
