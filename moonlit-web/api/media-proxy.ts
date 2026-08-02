export const config = { runtime: 'edge' };

const MAX_URL_LENGTH = 4096;
const MAX_BODY_SIZE = 1_048_576;
const RATE_WINDOW_MS = 60_000;
const RATE_MAX_REQUESTS = 200;

const rateMap = new Map<string, { count: number; resetAt: number }>();
const sessionStore = new Map<string, { target: string; headers: Record<string, string>; createdAt: number }>();

const BLOCKED_HOSTS = [
  'localhost',
  '127.0.0.1',
  '0.0.0.0',
  '::1',
  '169.254.169.254',
  'metadata.google.internal',
  'metadata.tencentyun.com',
];

const BLOCKED_CIDR_PATTERNS = [
  /^10\./,
  /^172\.(1[6-9]|2\d|3[01])\./,
  /^192\.168\./,
  /^127\./,
  /^0\./,
  /^169\.254\./,
  /^fc00:/i,
  /^fd00:/i,
];

function isBlockedHost(hostname: string): boolean {
  const lower = hostname.toLowerCase();
  if (BLOCKED_HOSTS.some(h => lower === h || lower.endsWith(`.${h}`))) return true;
  return BLOCKED_CIDR_PATTERNS.some(p => p.test(lower));
}

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
  const url = new URL(req.url);
  const session = url.searchParams.get('session');
  const target = url.searchParams.get('url');

  if (req.method === 'HEAD' || req.method === 'GET') {
    if (target) {
      if (session) return proxyGet(req, target, session);
      return proxyDirect(req, target);
    }
    return new Response('Missing url parameter', {
      status: 400,
      headers: { 'Cache-Control': 'no-store' },
    });
  }

  if (req.method === 'POST' && url.pathname.endsWith('/session')) {
    return createSession(req);
  }

  return new Response('Method not allowed', {
    status: 405,
    headers: { 'Cache-Control': 'no-store' },
  });
}

async function createSession(req: Request): Promise<Response> {
  const clientIp = req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for') || 'unknown';
  if (!rateLimit(clientIp)) {
    return new Response('Rate limit exceeded', {
      status: 429,
      headers: { 'Cache-Control': 'no-store', 'Retry-After': '60' },
    });
  }

  let body: { target?: string; headers?: Record<string, string> };
  try {
    body = await readBodyJSON(req);
  } catch {
    return new Response('Invalid request body', { status: 400, headers: { 'Cache-Control': 'no-store' } });
  }

  if (!body.target || typeof body.target !== 'string') {
    return new Response('Missing target URL', { status: 400, headers: { 'Cache-Control': 'no-store' } });
  }

  let targetUrl: URL;
  try {
    targetUrl = new URL(body.target);
  } catch {
    return new Response('Invalid target URL', { status: 400, headers: { 'Cache-Control': 'no-store' } });
  }

  if (targetUrl.protocol !== 'http:' && targetUrl.protocol !== 'https:') {
    return new Response('Only http(s) targets allowed', { status: 400, headers: { 'Cache-Control': 'no-store' } });
  }

  if (isBlockedHost(targetUrl.hostname)) {
    return new Response('Target blocked', { status: 403, headers: { 'Cache-Control': 'no-store' } });
  }

  if (targetUrl.href.length > MAX_URL_LENGTH) {
    return new Response('URL too long', { status: 414, headers: { 'Cache-Control': 'no-store' } });
  }

  const sessionId = crypto.randomUUID();
  sessionStore.set(sessionId, {
    target: targetUrl.href,
    headers: body.headers ?? {},
    createdAt: Date.now(),
  });

  return new Response(JSON.stringify({ session: sessionId }), {
    status: 201,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

async function proxyGet(req: Request, target: string, sessionId: string): Promise<Response> {
  const clientIp = req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for') || 'unknown';
  if (!rateLimit(clientIp)) {
    return new Response('Rate limit exceeded', {
      status: 429,
      headers: { 'Cache-Control': 'no-store', 'Retry-After': '60' },
    });
  }

  let sessionData: { target: string; headers: Record<string, string>; createdAt: number } | null = null;
  const stored = sessionStore.get(sessionId);
  if (stored) {
    sessionData = stored;
  }

  if (!sessionData || Date.now() - sessionData.createdAt > 3_600_000) {
    return new Response('Session expired or not found', {
      status: 401,
      headers: { 'Cache-Control': 'no-store' },
    });
  }

  let targetUrl: URL;
  try {
    targetUrl = new URL(target);
  } catch {
    if (sessionData) {
      try { targetUrl = new URL(target, sessionData.target); } catch {
        return new Response('Invalid target URL', { status: 400, headers: { 'Cache-Control': 'no-store' } });
      }
    } else {
      return new Response('Invalid target URL', { status: 400, headers: { 'Cache-Control': 'no-store' } });
    }
  }

  if (targetUrl.protocol !== 'http:' && targetUrl.protocol !== 'https:') {
    return new Response('Only http(s) targets allowed', { status: 400, headers: { 'Cache-Control': 'no-store' } });
  }

  if (isBlockedHost(targetUrl.hostname)) {
    return new Response('Target blocked', { status: 403, headers: { 'Cache-Control': 'no-store' } });
  }

  const sessionHeaders = new Headers(sessionData.headers);
  const reqHeaders = new Headers();
  for (const [name, value] of sessionHeaders.entries()) {
    reqHeaders.set(name, value);
  }
  const range = req.headers.get('Range');
  if (range) reqHeaders.set('Range', range);
  reqHeaders.set('User-Agent', 'VLC/3.0.20 LibVLC/3.0.20');
  reqHeaders.set('Accept', '*/*');

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30_000);

  try {
    const proxyResp = await fetch(targetUrl.href, {
      method: 'GET',
      headers: reqHeaders,
      redirect: 'manual',
      signal: controller.signal,
    });

    const respHeaders = new Headers();
    respHeaders.set('Cache-Control', 'no-store');
    respHeaders.set('Access-Control-Allow-Origin', '*');
    respHeaders.set('Access-Control-Expose-Headers', 'Content-Type, Content-Length, Content-Range, Accept-Ranges');
    respHeaders.set('X-Content-Type-Options', 'nosniff');

    const contentType = proxyResp.headers.get('Content-Type') || '';
    if (contentType) respHeaders.set('Content-Type', contentType);
    if (proxyResp.status === 301 || proxyResp.status === 302 || proxyResp.status === 303 || proxyResp.status === 307 || proxyResp.status === 308) {
      return new Response('Redirects not allowed', { status: 502, headers: { 'Cache-Control': 'no-store' } });
    }
    if (range && (proxyResp.status === 206 || proxyResp.status === 200)) {
      const cr = proxyResp.headers.get('Content-Range');
      if (cr) respHeaders.set('Content-Range', cr);
      respHeaders.set('Accept-Ranges', proxyResp.headers.get('Accept-Ranges') || 'bytes');
    }
    const contentLength = proxyResp.headers.get('Content-Length');
    if (contentLength) respHeaders.set('Content-Length', contentLength);

    return new Response(proxyResp.body, {
      status: proxyResp.status,
      headers: respHeaders,
    });
  } catch (err) {
    return new Response(err instanceof Error ? err.message : 'Proxy error', {
      status: 502,
      headers: { 'Cache-Control': 'no-store' },
    });
  } finally {
    clearTimeout(timeout);
  }
}

async function proxyDirect(req: Request, target: string): Promise<Response> {
  const clientIp = req.headers.get('cf-connecting-ip') || req.headers.get('x-forwarded-for') || 'unknown';
  if (!rateLimit(clientIp)) {
    return new Response('Rate limit exceeded', {
      status: 429,
      headers: { 'Cache-Control': 'no-store', 'Retry-After': '60' },
    });
  }

  let targetUrl: URL;
  try { targetUrl = new URL(target); } catch {
    return new Response('Invalid target URL', { status: 400, headers: { 'Cache-Control': 'no-store' } });
  }
  if (targetUrl.protocol !== 'http:' && targetUrl.protocol !== 'https:') {
    return new Response('Only http(s) targets allowed', { status: 400, headers: { 'Cache-Control': 'no-store' } });
  }
  if (isBlockedHost(targetUrl.hostname)) {
    return new Response('Target blocked', { status: 403, headers: { 'Cache-Control': 'no-store' } });
  }

  const reqHeaders = new Headers();
  const range = req.headers.get('Range');
  if (range) reqHeaders.set('Range', range);
  reqHeaders.set('User-Agent', 'VLC/3.0.20 LibVLC/3.0.20');
  reqHeaders.set('Accept', '*/*');

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30_000);

  try {
    const proxyResp = await fetch(targetUrl.href, {
      method: 'GET',
      headers: reqHeaders,
      redirect: 'manual',
      signal: controller.signal,
    });

    const respHeaders = new Headers();
    respHeaders.set('Cache-Control', 'no-store');
    respHeaders.set('Access-Control-Allow-Origin', '*');
    respHeaders.set('Access-Control-Expose-Headers', 'Content-Type, Content-Length, Content-Range, Accept-Ranges');
    respHeaders.set('X-Content-Type-Options', 'nosniff');

    const contentType = proxyResp.headers.get('Content-Type') || '';
    if (contentType) respHeaders.set('Content-Type', contentType);
    if ([301, 302, 303, 307, 308].includes(proxyResp.status)) {
      return new Response('Redirects not allowed', { status: 502, headers: { 'Cache-Control': 'no-store' } });
    }
    if (range) {
      const cr = proxyResp.headers.get('Content-Range');
      if (cr) respHeaders.set('Content-Range', cr);
      respHeaders.set('Accept-Ranges', proxyResp.headers.get('Accept-Ranges') || 'bytes');
    }
    const contentLength = proxyResp.headers.get('Content-Length');
    if (contentLength) respHeaders.set('Content-Length', contentLength);

    return new Response(proxyResp.body, {
      status: proxyResp.status,
      headers: respHeaders,
    });
  } catch (err) {
    return new Response(err instanceof Error ? err.message : 'Proxy error', {
      status: 502,
      headers: { 'Cache-Control': 'no-store' },
    });
  } finally {
    clearTimeout(timeout);
  }
}

async function readBodyJSON(req: Request): Promise<Record<string, unknown>> {
  const contentType = req.headers.get('content-type') || '';
  if (!contentType.includes('application/json')) throw new Error('Not JSON');

  const reader = req.body?.getReader();
  if (!reader) throw new Error('No body');

  let totalLength = 0;
  const chunks: Uint8Array[] = [];
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    totalLength += value.byteLength;
    if (totalLength > MAX_BODY_SIZE) throw new Error('Body too large');
    chunks.push(value);
  }

  const allChunks = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of chunks) {
    allChunks.set(chunk, offset);
    offset += chunk.byteLength;
  }

  return JSON.parse(new TextDecoder().decode(allChunks));
}
