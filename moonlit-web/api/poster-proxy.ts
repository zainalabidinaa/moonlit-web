export const config = { runtime: 'edge' };

// Requests are same-origin (web.trymoonlit.app/api/poster-proxy) rather than direct
// calls to btttr.cc, so a privacy extension/ad-blocker treating the third-party
// poster-badge domain as a tracker can no longer silently blank out every poster.
// The endpoint never accepts an arbitrary target URL — it only ever rebuilds the
// exact btttr.cc poster path from a validated IMDb id and flag string, so there is
// no open-proxy/SSRF surface here.

const ID_PATTERN = /^tt\d+$/;
const FLAGS_PATTERN = /^poster(-[a-z]{1,3})?$/;

const RATE_WINDOW_MS = 60_000;
const RATE_MAX_REQUESTS = 300;
const rateMap = new Map<string, { count: number; resetAt: number }>();

function rateLimit(clientIp: string): boolean {
  const now = Date.now();
  const entry = rateMap.get(clientIp);
  if (!entry || now >= entry.resetAt) {
    rateMap.set(clientIp, { count: 1, resetAt: now + RATE_WINDOW_MS });
    return true;
  }
  if (entry.count >= RATE_MAX_REQUESTS) return false;
  entry.count++;
  return true;
}

export default async function handler(req: Request): Promise<Response> {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return new Response('Method not allowed', { status: 405, headers: { 'Cache-Control': 'no-store' } });
  }

  const clientIp = req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for') || 'unknown';
  if (!rateLimit(clientIp)) {
    return new Response('Rate limit exceeded', {
      status: 429,
      headers: { 'Cache-Control': 'no-store', 'Retry-After': '60' },
    });
  }

  const url = new URL(req.url);
  const id = url.searchParams.get('id') ?? '';
  const flags = url.searchParams.get('flags') ?? 'poster';
  const tag = url.searchParams.get('tag') === 'none' ? 'none' : 'auto';

  if (!ID_PATTERN.test(id) || !FLAGS_PATTERN.test(flags)) {
    return new Response('Invalid poster request', { status: 400, headers: { 'Cache-Control': 'no-store' } });
  }

  const target = `https://btttr.cc/${flags}/imdb/poster-default/${id}.jpg?tag=${tag}&rs=IM`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);

  try {
    const upstream = await fetch(target, {
      signal: controller.signal,
      headers: { Accept: 'image/*' },
    });

    if (!upstream.ok || !upstream.body) {
      return new Response('Poster unavailable', { status: 502, headers: { 'Cache-Control': 'no-store' } });
    }

    const headers = new Headers();
    headers.set('Content-Type', upstream.headers.get('Content-Type') || 'image/jpeg');
    // Poster art for a given (id, flags, tag) triple never changes, so cache hard —
    // this also means repeat page loads never re-hit btttr.cc at all.
    headers.set('Cache-Control', 'public, max-age=86400, s-maxage=604800, stale-while-revalidate=604800');
    return new Response(upstream.body, { status: 200, headers });
  } catch {
    return new Response('Poster proxy error', { status: 502, headers: { 'Cache-Control': 'no-store' } });
  } finally {
    clearTimeout(timeout);
  }
}
