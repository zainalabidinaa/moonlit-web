/**
 * Client-side stream probe.
 *
 * Unlike the server-side probe in api/stremio/stream.ts, this runs in the
 * browser with the user's own IP and session — so IP-locked debrid links
 * (Real-Debrid, Torbox, etc.) can be reached. It also follows redirects,
 * giving us the final CDN URL rather than the intermediate debrid URL.
 *
 * The probe is best-effort: if it fails or times out, callers should fall
 * back to heuristic type detection and let the player handle errors.
 */

export interface StreamProbeResult {
  /** The final URL after following all redirects. */
  finalUrl: string;
  /** Detected container/playlist type. */
  type: 'application/x-mpegurl' | 'video/mp4';
}

export async function probeStreamClient(
  url: string,
  timeoutMs = 3000
): Promise<StreamProbeResult | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(url, {
      method: 'GET',
      redirect: 'follow',
      signal: controller.signal,
      headers: {
        // Request only the first kilobyte — enough to read an HLS header or MP4 ftyp box
        Range: 'bytes=0-1023',
        Accept: 'application/vnd.apple.mpegurl, application/x-mpegurl, video/mp4, */*',
      },
    });

    if (!res.ok && res.status !== 206) return null;

    const finalUrl = res.url || url;
    const ct = (res.headers.get('content-type') || '').toLowerCase();

    // Content-Type is the most reliable signal when present
    if (ct.includes('mpegurl') || ct.includes('x-mpegurl')) {
      return { finalUrl, type: 'application/x-mpegurl' };
    }
    if (ct.includes('video/mp4') || ct.includes('video/webm')) {
      return { finalUrl, type: 'video/mp4' };
    }

    // Fall back to reading the first bytes of the body
    const chunk = await res.text().catch(() => '');
    if (chunk.trimStart().startsWith('#EXTM3U')) {
      return { finalUrl, type: 'application/x-mpegurl' };
    }

    // MP4 ftyp box typically appears in the first 16 bytes
    const buf = new Uint8Array(chunk.length);
    for (let i = 0; i < Math.min(chunk.length, 20); i++) buf[i] = chunk.charCodeAt(i);
    for (let i = 0; i <= Math.min(buf.length - 4, 16); i++) {
      if (buf[i] === 0x66 && buf[i+1] === 0x74 && buf[i+2] === 0x79 && buf[i+3] === 0x70) {
        return { finalUrl, type: 'video/mp4' };
      }
    }

    // URL extension as last resort
    const lower = finalUrl.toLowerCase();
    if (lower.includes('.m3u8') || lower.includes('.m3u')) return { finalUrl, type: 'application/x-mpegurl' };
    if (lower.includes('.mp4')) return { finalUrl, type: 'video/mp4' };

    // Reachable but unidentified — assume MP4 (native <video> will try it)
    return { finalUrl, type: 'video/mp4' };
  } catch {
    // CORS block, network error, abort — not a problem, caller falls back
    return null;
  } finally {
    clearTimeout(timer);
  }
}
