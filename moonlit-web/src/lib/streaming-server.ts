/**
 * Stremio streaming-server (remux) client.
 *
 * Builds the on-the-fly HLS URLs the Stremio server exposes so the browser can
 * play otherwise-unplayable streams (MKV containers, E-AC3 audio, etc.). The
 * server copies tracks the browser already supports and only transcodes what it
 * must, based on the codec list we advertise.
 *
 * Endpoint shape (Stremio server):
 *   /hlsv2/{id}/master.m3u8?mediaURL=...&videoCodecs=...&audioCodecs=...&maxAudioChannels=...
 *   /hlsv2/probe?mediaURL=...   (track/format info; used for "test"/pre-flight)
 */

export interface BrowserCodecs {
  videoCodecs: string[];
  audioCodecs: string[];
  maxAudioChannels: number;
}

/**
 * Detect what the current browser can play so the server copies instead of
 * transcoding wherever possible. H.264 + AAC is the universal baseline; we add
 * HEVC/VP9/AV1 and AC-3/E-AC3 when the platform reports support so the server
 * can stream-copy those (cheap) rather than re-encode (expensive).
 */
export function getBrowserCodecs(): BrowserCodecs {
  const video = document.createElement('video');
  const can = (t: string) => {
    try { return video.canPlayType(t) !== ''; } catch { return false; }
  };

  const videoCodecs = ['h264'];
  if (can('video/mp4; codecs="hvc1.1.6.L93.B0"') || can('video/mp4; codecs="hev1.1.6.L93.B0"')) videoCodecs.push('h265', 'hevc');
  if (can('video/webm; codecs="vp9"') || can('video/mp4; codecs="vp09.00.10.08"')) videoCodecs.push('vp9');
  if (can('video/mp4; codecs="av01.0.05M.08"')) videoCodecs.push('av1');

  const audioCodecs = ['aac', 'mp3'];
  if (can('audio/mp4; codecs="opus"') || can('audio/webm; codecs="opus"')) audioCodecs.push('opus');
  // AC-3 / E-AC3 only decode on some platforms (Safari, some Chromium builds)
  if (can('audio/mp4; codecs="ac-3"')) audioCodecs.push('ac3');
  if (can('audio/mp4; codecs="ec-3"')) audioCodecs.push('eac3');

  return { videoCodecs, audioCodecs, maxAudioChannels: 2 };
}

/** Stable short id from a URL so the server reuses the same HLS session. */
function sessionId(mediaUrl: string): string {
  let hash = 0;
  for (let i = 0; i < mediaUrl.length; i++) {
    hash = (hash << 5) - hash + mediaUrl.charCodeAt(i);
    hash |= 0;
  }
  return Math.abs(hash).toString(36);
}

/**
 * For remux-only streams (good codecs, wrong container) we tell the server to
 * accept everything — it will copy all tracks without re-encoding, giving the
 * fastest possible startup. Surround channels are preserved at up to 6ch.
 */
const BROAD_CODECS: BrowserCodecs = {
  videoCodecs: ['h264', 'h265', 'hevc', 'vp9', 'av1'],
  audioCodecs: ['aac', 'mp3', 'opus', 'ac3', 'eac3'],
  maxAudioChannels: 6,
};

/**
 * Build the HLS master-playlist URL that routes `mediaUrl` through the remux
 * server. Feed the result to the player with type 'application/x-mpegurl'.
 *
 * @param tier  'remux'     → broad codec list (server copies all streams, fast)
 *              'transcode' → browser-detected list (server re-encodes only what's needed)
 */
export function buildRemuxUrl(
  serverUrl: string,
  mediaUrl: string,
  tier: 'remux' | 'transcode' = 'transcode',
  codecs: BrowserCodecs = getBrowserCodecs()
): string {
  const effective = tier === 'remux' ? BROAD_CODECS : codecs;
  const params = new URLSearchParams();
  // Decode the URL before passing to remux server to avoid double-encoding issues
  // (e.g. ElfHosted URLs with %255B from triple-encoded bracket characters)
  let cleanUrl = mediaUrl;
  try { cleanUrl = decodeURIComponent(mediaUrl); } catch { /* leave as-is if malformed */ }
  params.set('mediaURL', cleanUrl);
  for (const c of effective.videoCodecs) params.append('videoCodecs', c);
  for (const c of effective.audioCodecs) params.append('audioCodecs', c);
  params.set('maxAudioChannels', String(effective.maxAudioChannels));
  return `${serverUrl}/hlsv2/${sessionId(mediaUrl)}/master.m3u8?${params.toString()}`;
}

/**
 * Pre-flight: confirm the server can open the source. Returns true if the probe
 * succeeds. Used by Settings "Test connection" and (optionally) before routing.
 */
export async function probeViaServer(
  serverUrl: string,
  mediaUrl: string,
  timeoutMs = 8000
): Promise<boolean> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const params = new URLSearchParams({ mediaURL: mediaUrl });
    const res = await fetch(`${serverUrl}/hlsv2/probe?${params.toString()}`, {
      signal: controller.signal,
    });
    return res.ok;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}

/** Lightweight health check for the server itself (Settings "Test connection"). */
export async function pingServer(serverUrl: string, timeoutMs = 6000): Promise<boolean> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(`${serverUrl}/settings`, { signal: controller.signal });
    return res.ok;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}
